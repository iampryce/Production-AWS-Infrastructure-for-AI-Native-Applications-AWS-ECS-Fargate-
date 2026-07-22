import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class GenerationCreate(BaseModel):
    prompt: str = Field(min_length=1, max_length=4000)


class GenerationResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    status: str
    prompt: str
    result_url: Optional[str] = None
    created_at: datetime
    updated_at: datetime
