import os
from urllib.parse import quote

from celery import Celery


def _broker_url() -> str:
    host = os.environ["REDIS_HOST"]
    port = os.environ["REDIS_PORT"]
    scheme = "rediss" if os.environ.get("REDIS_TLS", "true").lower() == "true" else "redis"

    # REDIS_AUTH_SECRET is absent for local dev (docker-compose runs Redis
    # with no AUTH at all) - ElastiCache's real AUTH token, when present,
    # gets percent-encoded for the same reason as the DB password in
    # database.py (see ADR-010's Flower bug).
    token = os.environ.get("REDIS_AUTH_SECRET", "")
    if token:
        encoded_token = quote(token, safe="")
        return f"{scheme}://:{encoded_token}@{host}:{port}/0"
    return f"{scheme}://{host}:{port}/0"


celery_app = Celery("heartstamp", broker=_broker_url())
