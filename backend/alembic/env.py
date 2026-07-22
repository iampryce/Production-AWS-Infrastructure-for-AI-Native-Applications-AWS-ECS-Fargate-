import os
from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# No ORM models yet (app code lands in Phase 10) — migrations are written
# directly against the schema, so there's no metadata to autogenerate from.
target_metadata = None


def get_url() -> str:
    # DATABASE_URL is an explicit override for one-off local runs; nothing
    # sets it in ECS. The real path (matching Phase 10's app code and the
    # ECS task definitions - DB_HOST/DB_NAME/DB_USER/DB_SECRET) is
    # app.database's own URL builder, reused here rather than duplicated,
    # since it's the one place that knows to percent-encode the RDS
    # password before it goes into a URL.
    url = os.environ.get("DATABASE_URL")
    if url:
        return url

    from app.database import _database_url

    return _database_url()


def run_migrations_offline() -> None:
    """Emit SQL to stdout without a live DB connection (alembic upgrade head --sql)."""
    context.configure(
        url=get_url(),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    configuration = config.get_section(config.config_ini_section) or {}
    configuration["sqlalchemy.url"] = get_url()

    connectable = engine_from_config(
        configuration,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
