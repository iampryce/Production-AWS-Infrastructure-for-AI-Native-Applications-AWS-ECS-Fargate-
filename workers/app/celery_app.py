import os
from urllib.parse import quote

from celery import Celery


def _broker_url() -> str:
    host = os.environ["REDIS_HOST"]
    port = os.environ["REDIS_PORT"]
    scheme = "rediss" if os.environ.get("REDIS_TLS", "true").lower() == "true" else "redis"

    token = os.environ.get("REDIS_AUTH_SECRET", "")
    if token:
        encoded_token = quote(token, safe="")
        return f"{scheme}://:{encoded_token}@{host}:{port}/0"
    return f"{scheme}://{host}:{port}/0"


# include=["app.tasks"] so `celery -A app.celery_app worker` registers
# generate_content without a separate explicit import somewhere.
celery_app = Celery("heartstamp", broker=_broker_url(), include=["app.tasks"])
