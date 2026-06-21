import os
from fastapi import FastAPI

app = FastAPI(title="myapp")

APP_VERSION = os.getenv("APP_VERSION", "dev")
APP_ENV = os.getenv("APP_ENV", "local")


@app.get("/")
def root():
    return {"message": "hello from myapp", "env": APP_ENV}


@app.get("/healthz")
def healthz():
    """Used by Kubernetes liveness/readiness probes."""
    return {"status": "ok"}


@app.get("/version")
def version():
    """Used to verify which build is actually running in a given environment."""
    return {"version": APP_VERSION, "env": APP_ENV}
