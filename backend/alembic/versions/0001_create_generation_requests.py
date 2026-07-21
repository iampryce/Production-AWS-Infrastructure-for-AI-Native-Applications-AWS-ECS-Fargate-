"""create generation_requests

Revision ID: 0001
Revises:
Create Date: 2026-07-21

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Enabling pgvector here (not via a Terraform/RDS parameter group) is
    # deliberate — RDS Postgres 16 ships the extension already available,
    # so turning it on is schema DDL like any other, and belongs in a
    # migration, not infrastructure code.
    op.execute("CREATE EXTENSION IF NOT EXISTS vector")

    op.create_table(
        "generation_requests",
        sa.Column("id", sa.dialects.postgresql.UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), primary_key=True),
        sa.Column("status", sa.String(length=32), nullable=False, server_default="pending"),
        sa.Column("prompt", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
    )


def downgrade() -> None:
    op.drop_table("generation_requests")
