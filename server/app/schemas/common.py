from datetime import datetime
from typing import Any, ClassVar, Self

from pydantic import BaseModel, ConfigDict, ValidationInfo, field_validator, model_validator


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    @field_validator("*", mode="after")
    @classmethod
    def _to_user_timezone(cls, value: Any, info: ValidationInfo) -> Any:
        """Responses use the user's timezone: validate with `context={"tz": ZoneInfo(...)}`."""
        tz = info.context.get("tz") if info.context else None
        if tz is not None and isinstance(value, datetime) and value.tzinfo is not None:
            return value.astimezone(tz)
        return value


class PatchModel(BaseModel):
    """PATCH body: at least one field; omitted = unchanged; `null` clears nullable fields only."""

    non_nullable: ClassVar[frozenset[str]] = frozenset()

    @model_validator(mode="after")
    def _check_patch(self) -> Self:
        if not self.model_fields_set:
            raise ValueError("At least one field is required")
        for name in self.non_nullable & self.model_fields_set:
            if getattr(self, name) is None:
                raise ValueError(f"{name} cannot be null")
        return self

    def changes(self) -> dict[str, Any]:
        return {name: getattr(self, name) for name in self.model_fields_set}


class ErrorResponse(BaseModel):
    detail: str
    code: str
