import uuid

from sqlalchemy import Column, DateTime, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import declarative_base

Base = declarative_base()


class GenerationRequest(Base):
    __tablename__ = "generation_requests"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    status = Column(String(32), nullable=False, default="pending")
    prompt = Column(Text, nullable=False)
    result_url = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now())

    # prompt_embedding (Alembic 0002) isn't mapped here - nothing in this
    # phase's API reads or writes it.
