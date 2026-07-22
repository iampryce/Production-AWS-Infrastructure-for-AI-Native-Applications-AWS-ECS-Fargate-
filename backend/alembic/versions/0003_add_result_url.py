"""add result_url

Revision ID: 0003
Revises: 0002
Create Date: 2026-07-22

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0003"
down_revision: Union[str, None] = "0002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Phase 11's worker writes the generated asset to S3 and puts its URL
    # here; nullable because it doesn't exist until the job completes.
    op.add_column(
        "generation_requests",
        sa.Column("result_url", sa.String(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("generation_requests", "result_url")
