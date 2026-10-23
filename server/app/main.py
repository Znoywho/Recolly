from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI

import app.models.user  # noqa: F401  register tables on Base.metadata
from app.db.base import Base
from app.db.session import engine


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Create missing tables until migrations (Alembic) are set up
    Base.metadata.create_all(engine)
    yield


app = FastAPI(title="Recolly API", lifespan=lifespan)


@app.get("/")
def read_root():
    return {"status": "ok"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8765)
