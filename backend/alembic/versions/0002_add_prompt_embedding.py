"""add prompt embedding column

Revision ID: 0002
Revises: 0001
Create Date: 2026-07-21

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from pgvector.sqlalchemy import Vector

revision: str = "0002"
down_revision: Union[str, None] = "0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# text-embedding-3-small (OpenAI) dimension — the embedding is over the
# prompt text, used for prompt/style similarity search.
EMBEDDING_DIM = 1536


def upgrade() -> None:
    op.add_column(
        "generation_requests",
        sa.Column("prompt_embedding", Vector(EMBEDDING_DIM), nullable=True),
    )

    # HNSW over ivfflat: no training/list-count tuning needed and better
    # recall at query time, at the cost of slower index builds — a
    # reasonable trade for this dataset size.
    op.execute(
        "CREATE INDEX generation_requests_prompt_embedding_hnsw_idx "
        "ON generation_requests USING hnsw (prompt_embedding vector_cosine_ops)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS generation_requests_prompt_embedding_hnsw_idx")
    op.drop_column("generation_requests", "prompt_embedding")
