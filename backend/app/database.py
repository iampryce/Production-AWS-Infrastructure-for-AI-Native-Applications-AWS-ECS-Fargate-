import json
import os
from urllib.parse import quote

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker


def _database_url() -> str:
    # DB_SECRET is the RDS-managed master user secret (ECS injects the
    # whole JSON string, not a single field) - never a plain env var
    # holding the password directly. Percent-encode the password before
    # it goes into the URL: RDS's generated passwords exclude '/', '"',
    # '@' but not ':', which breaks URL parsing the same way it did for
    # Flower's Redis broker URL (see ADR-010) if left unencoded.
    db_secret = json.loads(os.environ["DB_SECRET"])
    password = quote(db_secret["password"], safe="")

    return (
        f"postgresql://{os.environ['DB_USER']}:{password}"
        f"@{os.environ['DB_HOST']}:5432/{os.environ['DB_NAME']}"
    )


engine = create_engine(_database_url(), pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
