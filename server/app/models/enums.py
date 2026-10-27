from enum import StrEnum

from sqlalchemy import Enum


class Chronotype(StrEnum):
    """Shown as animals; computed from MSFsc in app.service.sleep.chronotype."""

    LION = "lion"
    BEAR = "bear"
    WOLF = "wolf"


class ChronotypeSpectrum(StrEnum):
    """Position on the lion <-> wolf slider; null for a self-reported chronotype."""

    EARLY = "early"
    SLIGHTLY_EARLY = "slightly_early"
    INTERMEDIATE = "intermediate"
    SLIGHTLY_LATE = "slightly_late"
    LATE = "late"


class ChronotypeSource(StrEnum):
    MCTQ = "mctq"
    RMEQ = "rmeq"
    SELF_REPORT = "self_report"


class RmeqCategory(StrEnum):
    DEFINITELY_MORNING = "definitely_morning"
    MODERATELY_MORNING = "moderately_morning"
    NEITHER = "neither"
    MODERATELY_EVENING = "moderately_evening"
    DEFINITELY_EVENING = "definitely_evening"


class SleepConcern(StrEnum):
    """Fragmented-sleep screening flag; dolphin is not a chronotype."""

    NONE = "none"
    WATCH = "watch"
    DOLPHIN = "dolphin"


class SleepSource(StrEnum):
    MANUAL = "manual"
    SCREEN_INFERRED = "screen_inferred"


class EventSource(StrEnum):
    MANUAL = "manual"
    OCR = "ocr"
    SCHEDULER = "scheduler"
    GOOGLE = "google"


class EventKind(StrEnum):
    CLASS = "class"
    STUDY = "study"
    REST = "rest"
    BEDTIME = "bedtime"
    OTHER = "other"


class SyncStatus(StrEnum):
    NOT_SYNCED = "not_synced"
    PENDING = "pending"
    SYNCED = "synced"
    CONFLICT = "conflict"
    ERROR = "error"


class TodoStatus(StrEnum):
    TODO = "todo"
    IN_PROGRESS = "in_progress"
    DONE = "done"


class TodoCategory(StrEnum):
    STUDY = "study"
    ASSIGNMENT = "assignment"
    EXAM = "exam"
    PERSONAL = "personal"
    OTHER = "other"


class Priority(StrEnum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class JobStatus(StrEnum):
    QUEUED = "queued"
    PROCESSING = "processing"
    SUCCEEDED = "succeeded"
    FAILED = "failed"


class DevicePlatform(StrEnum):
    ANDROID = "android"
    IOS = "ios"


class ConflictResolution(StrEnum):
    KEEP_LOCAL = "local"
    KEEP_GOOGLE = "google"


def str_enum(enum_cls: type[StrEnum]) -> Enum:
    """Store enum values as VARCHAR + CHECK, avoiding native PG enums (painful to migrate)."""
    return Enum(
        enum_cls,
        native_enum=False,
        create_constraint=True,
        length=32,
        values_callable=lambda cls: [member.value for member in cls],
    )
