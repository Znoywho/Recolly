from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI

import app.models  # noqa: F401  register every table on Base.metadata
from app.api import api_router
from app.config import Config
from app.core.errors import install_error_handlers
from app.db.base import Base
from app.db.session import engine


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Create missing tables until migrations (Alembic) are set up
    Base.metadata.create_all(engine)
    yield


app = FastAPI(title="Recolly API", version=Config.APP_VERSION, lifespan=lifespan)
install_error_handlers(app)
app.include_router(api_router)


@app.get("/")
def read_root():
    return {"status": "ok"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8765)
