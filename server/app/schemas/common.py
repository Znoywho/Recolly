from pydantic import BaseModel, ConfigDict


class ORMModel(BaseModel):
    """Base for response schemas built from SQLAlchemy objects."""

    model_config = ConfigDict(from_attributes=True)


class ErrorResponse(BaseModel):
    detail: str
    code: str
