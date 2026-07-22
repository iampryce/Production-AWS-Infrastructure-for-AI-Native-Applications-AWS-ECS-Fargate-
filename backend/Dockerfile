# Placeholder for Phase 5 (decoupled deploy pipeline) - proves the real
# build/push/deploy path works end to end before the real FastAPI app
# exists. Same behavior as the Docker-Hub-pulled placeholder this replaces
# in terraform/modules/ecs (see use_placeholder_images there): serves a
# basic HTTP response on the app port, enough to pass a real ALB health
# check. Replaced by the real FastAPI app in Phase 10.
FROM python:3.12-slim

EXPOSE 8000

CMD ["python3", "-m", "http.server", "8000"]
