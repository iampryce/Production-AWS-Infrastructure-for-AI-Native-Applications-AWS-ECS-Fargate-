import json
import os

import boto3
from celery import Task
from openai import APIConnectionError, APITimeoutError, InternalServerError, OpenAI, RateLimitError

from .celery_app import celery_app
from .database import SessionLocal
from .models import GenerationRequest


def _s3_client():
    # S3_ENDPOINT_URL is unset in real AWS - the boto3 default (real S3)
    # applies. Only set locally, pointed at MinIO.
    return boto3.client("s3", endpoint_url=os.environ.get("S3_ENDPOINT_URL") or None)


def _ensure_local_bucket(s3, bucket_name: str) -> None:
    # Only relevant for local MinIO testing - the real bucket already
    # exists (Phase 6), and the celery task role deliberately has no
    # s3:CreateBucket permission there.
    if not os.environ.get("S3_ENDPOINT_URL"):
        return
    try:
        s3.create_bucket(Bucket=bucket_name)
    except Exception:
        pass


class _GenerationTask(Task):
    # Runs once, only when Celery has genuinely given up (all retries
    # exhausted) - not on every transient failure, so a request that
    # succeeds on retry never gets marked "failed" first.
    def on_failure(self, exc, task_id, args, kwargs, einfo):
        generation_id = args[0] if args else None
        if not generation_id:
            return
        db = SessionLocal()
        try:
            generation = db.get(GenerationRequest, generation_id)
            if generation is not None:
                generation.status = "failed"
                db.commit()
        finally:
            db.close()


@celery_app.task(
    base=_GenerationTask,
    name="generate_content",
    # Only the AI provider's own transient failure modes retry - a bug in
    # this code (KeyError, etc.) should fail loudly, not retry forever.
    autoretry_for=(RateLimitError, APIConnectionError, APITimeoutError, InternalServerError),
    retry_backoff=True,
    retry_backoff_max=60,
    retry_jitter=True,
    max_retries=3,
)
def generate_content(generation_id: str) -> None:
    db = SessionLocal()
    try:
        generation = db.get(GenerationRequest, generation_id)
        if generation is None:
            return

        generation.status = "processing"
        db.commit()

        client = OpenAI(api_key=os.environ["OPENAI_API_KEY"])
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "system",
                    "content": "Write a short, warm, personalized message based on the user's request.",
                },
                {"role": "user", "content": generation.prompt},
            ],
        )
        message = response.choices[0].message.content

        bucket_name = os.environ["ASSETS_BUCKET_NAME"]
        # "assets/" prefix is load-bearing, not cosmetic: CloudFront's
        # /assets/* cache behavior has no origin_path rewrite (Phase 6),
        # so a request to <site>/assets/generations/<id>.json maps
        # directly to this S3 key - a mismatch here 403s at the edge
        # (discovered for real: the first live object was stored without
        # this prefix and CloudFront couldn't find it).
        key = f"assets/generations/{generation_id}.json"
        s3 = _s3_client()
        _ensure_local_bucket(s3, bucket_name)
        s3.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps({"message": message}).encode("utf-8"),
            ContentType="application/json",
        )

        generation.status = "completed"
        generation.result_url = f"{os.environ['PUBLIC_ASSET_BASE_URL']}/{key}"
        db.commit()
    finally:
        db.close()
