import uuid

from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session

from .celery_app import celery_app
from .database import get_db
from .models import GenerationRequest
from .schemas import GenerationCreate, GenerationResponse

app = FastAPI(title="heartstamp generation API")

# Phase 12: the frontend is a separate origin (localhost:3000 in dev, no
# fixed hosting domain yet - out of this phase's scope). Permissive on
# purpose, not an oversight: this API has no cookies/session auth to leak
# via CSRF-style abuse, and every field it returns (a prompt, a status, a
# public S3/CloudFront result URL) is already meant to be readable by
# whoever holds the generation's UUID.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
def health():
    # Also what the ALB target group's health check hits (Phase 4).
    return {"status": "ok"}


@app.post("/generations", response_model=GenerationResponse, status_code=201)
def create_generation(payload: GenerationCreate, db: Session = Depends(get_db)):
    generation = GenerationRequest(prompt=payload.prompt)
    db.add(generation)
    db.commit()
    db.refresh(generation)

    # By task name only, not an imported function - the Celery worker
    # that actually implements "generate_content" doesn't exist until
    # Phase 11. This still puts a real message on the real Redis queue;
    # nothing here is mocked, it's just not consumed yet.
    celery_app.send_task("generate_content", args=[str(generation.id)])

    return generation


@app.get("/generations/{generation_id}", response_model=GenerationResponse)
def get_generation(generation_id: uuid.UUID, db: Session = Depends(get_db)):
    generation = db.get(GenerationRequest, generation_id)
    if generation is None:
        raise HTTPException(status_code=404, detail="generation request not found")
    return generation
