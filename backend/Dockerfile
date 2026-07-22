FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY alembic.ini .
COPY alembic ./alembic
COPY app ./app

EXPOSE 8000

# Migrations run at container start, not as a separate deploy step - this
# project has no migration-runner task yet, and Alembic's own version
# table plus transactional DDL make concurrent "upgrade head" attempts
# across multiple task replicas safe in practice. Revisit if that stops
# being true for a specific future migration.
CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8000"]
