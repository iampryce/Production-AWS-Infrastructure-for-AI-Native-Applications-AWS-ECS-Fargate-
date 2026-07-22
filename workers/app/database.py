import json
import os
from urllib.parse import quote

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Deliberately duplicated from backend/app/database.py, not imported
# across a package boundary - the two Docker build contexts (./backend,
# ./workers) can't reach into each other, and this project's other
# services (Flagsmith, Cloudflare Tunnel, monitoring) already favor a few
# duplicated lines per deployable over a shared internal package for
# exactly this reason.


def _database_url() -> str:
    # Percent-encode the RDS password before it goes into the URL - the
    # same class of bug ADR-010 found in Flower's Redis broker URL.
    db_secret = json.loads(os.environ["DB_SECRET"])
    password = quote(db_secret["password"], safe="")

    return (
        f"postgresql://{os.environ['DB_USER']}:{password}"
        f"@{os.environ['DB_HOST']}:5432/{os.environ['DB_NAME']}"
    )


engine = create_engine(_database_url(), pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
