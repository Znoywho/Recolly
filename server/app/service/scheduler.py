"""CP-SAT study planner (S1/S2, R24-R27): puts todo study blocks into free time.

Time is cut into 15-minute slots of local time. A slot is free when it is in the future, the
user is awake (sleep from the sleep timeline), it is not inside the wake / bed buffers, a meal
window, or any event (classes, manual and Google events, already applied blocks).

Hard constraints: a block sits on free slots of one day and ends before its todo's deadline;
blocks keep `min_break_minutes` apart; at most `max_study_minutes_per_day` per day.
Objective: Σ predicted KSS × slots, weighted by difficulty (hard work goes to golden hours),
plus a large penalty per unscheduled slot (weighted by priority) and a tiny one per hour of
delay, so the earlier of two equally alert slots wins.
"""

import math
import time
import uuid
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from typing import Any

from ortools.sat.python import cp_model
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.errors import ApiError, not_found
from app.models.enums import Priority
from app.models.event import Event
from app.models.todo import Todo
from app.models.user import User
from app.repository.todo_repository import TodoRepository
from app.schemas.schedule import ScheduleOptions
from app.service.event_service import occurrences
from app.service.sleep.timeline import Timeline, alertness_score

SLOT = timedelta(minutes=15)
SLOT_MINUTES = 15
DAY_SLOTS = 96
STEPS_PER_SLOT = 3  # 5-minute timeline steps
MAX_DAYS = 15       # `to` at most 14 days after `from`
SOLVE_SECONDS = 5.0
KSS_SCALE = 100     # KSS 3.25 -> 325 (CP-SAT needs integers)
UNSCHEDULED_PENALTY = 10_000  # per slot, x priority: always worse than any placement
PRIORITY_FACTOR = {Priority.LOW: 1, Priority.MEDIUM: 2, Priority.HIGH: 3}
SUGGESTION_TTL = timedelta(hours=1)
BEDTIME_TITLE = "Đi ngủ"
REST_TITLE = "Nghỉ giải lao"


@dataclass
class Block:
    todo: Todo
    slots: int
    starts: list[int] = field(default_factory=list)  # allowed start slots


@dataclass
class Suggestion:
    user_id: uuid.UUID
    expires_at: datetime
    blocks: list[dict[str, Any]]


# Suggestions live one hour, so memory is enough (single API process).
_suggestions: dict[uuid.UUID, Suggestion] = {}


def _ceil_slots(minutes: int) -> int:
    return math.ceil(minutes / SLOT_MINUTES)


def split_minutes(remaining: int, options: ScheduleOptions) -> list[int]:
    """Block sizes in slots: full blocks, then the rest (never shorter than min_block_minutes)."""
    full, rest = divmod(remaining, options.block_minutes)
    sizes = [_ceil_slots(options.block_minutes)] * full
    if rest:
        sizes.append(_ceil_slots(max(rest, options.min_block_minutes)))
    return sizes


class Planner:
    def __init__(self, db: Session, user: User, timeline: Timeline, first_day: date, days: int,
                 now: datetime, options: ScheduleOptions):
        self.db, self.user, self.timeline = db, user, timeline
        self.tz = timeline.tz
        self.options = options
        self.start = datetime.combine(first_day, datetime.min.time(), self.tz)
        self.n = days * DAY_SLOTS
        self.now = now
        self.kss: list[float | None] = []
        self.free = [True] * self.n
        self._build_slots()

    # ─────────────────────────── slots ───────────────────────────

    def slot_time(self, slot: int) -> datetime:
        return self.start + slot * SLOT

    def slot_of(self, dt: datetime) -> int:
        return math.floor((dt.astimezone(self.tz) - self.start) / SLOT)

    def _block_range(self, start: datetime, end: datetime) -> None:
        first = max(0, self.slot_of(start))
        last = min(self.n, math.ceil((end.astimezone(self.tz) - self.start) / SLOT))
        for s in range(first, last):
            self.free[s] = False

    def _build_slots(self) -> None:
        base = self.timeline.index(self.start)
        for s in range(self.n):
            values = [self.timeline.kss(base + s * STEPS_PER_SLOT + k) for k in range(STEPS_PER_SLOT)]
            awake = all(v is not None for v in values)
            self.kss.append(sum(values) / STEPS_PER_SLOT if awake else None)
            if not awake or self.slot_time(s) < self.now:
                self.free[s] = False

        o = self.options
        end = self.slot_time(self.n)
        for episode in self.timeline.episodes(self.start - timedelta(days=1), end + timedelta(days=1)):
            self._block_range(episode.start - timedelta(minutes=o.bed_buffer_minutes), episode.start)
            self._block_range(episode.end, episode.end + timedelta(minutes=o.wake_buffer_minutes))

        events = self.db.scalars(select(Event).where(Event.user_id == self.user.id,
                                                     Event.start_at < end)).all()
        for occ in occurrences(events, self.start, end, self.tz):
            if not occ.event.all_day:
                self._block_range(occ.start, occ.end)

        for day in range(self.n // DAY_SLOTS):
            midnight = self.slot_time(day * DAY_SLOTS)
            for window in o.meal_windows:
                begin = datetime.combine(midnight.date(), window.start, self.tz)
                finish = datetime.combine(midnight.date(), window.end, self.tz)
                if finish <= begin:  # crosses midnight
                    finish += timedelta(days=1)
                self._block_range(begin, finish)

    def allowed_starts(self, slots: int, deadline: datetime) -> list[int]:
        """Starts where the block fits on free slots of one day and ends by the deadline."""
        last_end = min(self.n, self.slot_of(deadline))
        starts = []
        for s in range(0, self.n - slots + 1):
            if s + slots > last_end or s // DAY_SLOTS != (s + slots - 1) // DAY_SLOTS:
                continue
            if all(self.free[s:s + slots]):
                starts.append(s)
        return starts

    def mean_kss(self, start: int, slots: int) -> float:
        return sum(self.kss[start:start + slots]) / slots

    # ─────────────────────────── solve ───────────────────────────

    def solve(self, blocks: list[Block]) -> tuple[str, dict[int, int], int]:
        """Returns (status, block index -> start slot of placed blocks, solve ms)."""
        o = self.options
        gap = _ceil_slots(o.min_break_minutes)
        cap = o.max_study_minutes_per_day // SLOT_MINUTES
        model = cp_model.CpModel()
        starts, present, intervals, objective = {}, {}, [], []
        per_day: dict[int, list[cp_model.LinearExpr]] = {}  # slots studied on each day

        for i, block in enumerate(blocks):
            if not block.starts:
                continue
            start = model.new_int_var_from_domain(cp_model.Domain.from_values(block.starts), f"s{i}")
            is_on = model.new_bool_var(f"p{i}")
            starts[i], present[i] = start, is_on
            intervals.append(model.new_optional_fixed_size_interval_var(start, block.slots + gap, is_on, f"iv{i}"))

            weight = 2 + (block.todo.difficulty or 3)  # difficulty 1..5 -> 3..7
            table = [0] * self.n
            for s in block.starts:
                table[s] = weight * round(self.mean_kss(s, block.slots) * KSS_SCALE) * block.slots + s // 4
            cost = model.new_int_var(0, max(table), f"c{i}")
            model.add_element(start, table, cost)
            placed_cost = model.new_int_var(0, max(table), f"pc{i}")
            model.add(placed_cost == cost).only_enforce_if(is_on)
            model.add(placed_cost == 0).only_enforce_if(~is_on)
            penalty = UNSCHEDULED_PENALTY * PRIORITY_FACTOR[block.todo.priority] * block.slots
            objective += [placed_cost, penalty * (1 - is_on)]

            # A placed block sits on exactly one day, which counts towards that day's cap.
            day_flags = []
            for day in sorted({s // DAY_SLOTS for s in block.starts}):
                on_day = model.new_bool_var(f"d{i}_{day}")
                model.add(start >= day * DAY_SLOTS).only_enforce_if(on_day)
                model.add(start < (day + 1) * DAY_SLOTS).only_enforce_if(on_day)
                day_flags.append(on_day)
                per_day.setdefault(day, []).append(block.slots * on_day)
            model.add(sum(day_flags) == is_on)

        for studied in per_day.values():
            model.add(sum(studied) <= cap)

        # Blocks of one todo keep their order (also breaks the symmetry between equal blocks).
        for i in starts:
            j = i + 1
            if j in starts and blocks[j].todo is blocks[i].todo:
                model.add(starts[j] >= starts[i] + blocks[i].slots + gap).only_enforce_if(
                    [present[i], present[j]])

        model.add_no_overlap(intervals)
        model.minimize(sum(objective))
        solver = cp_model.CpSolver()
        solver.parameters.max_time_in_seconds = SOLVE_SECONDS
        solver.parameters.num_workers = 8
        began = time.perf_counter()
        status = solver.solve(model)
        solve_ms = round((time.perf_counter() - began) * 1000)
        placed = {}
        if status in (cp_model.OPTIMAL, cp_model.FEASIBLE):
            placed = {i: solver.value(starts[i]) for i in starts if solver.boolean_value(present[i])}
        return solver.status_name(status), placed, solve_ms

    def day_is_full(self, day: int, placed: dict[int, int], blocks: list[Block], slots: int) -> bool:
        """True if `slots` more would break that day's study limit."""
        used = sum(blocks[i].slots for i, s in placed.items() if s // DAY_SLOTS == day)
        return (used + slots) * SLOT_MINUTES > self.options.max_study_minutes_per_day


def check_range(first_day: date, last_day: date) -> int:
    """Number of days in [first_day, last_day]; 400 when backwards or longer than allowed."""
    if last_day < first_day:
        raise ApiError(400, "INVALID_RANGE", "`to` must not be before `from`")
    days = (last_day - first_day).days + 1
    if days > MAX_DAYS:
        raise ApiError(400, "RANGE_TOO_LARGE", "Range is longer than 14 days")
    return days


def generate(db: Session, user: User, timeline: Timeline, first_day: date, last_day: date,
             todo_ids: list[uuid.UUID] | None, options: ScheduleOptions,
             now: datetime) -> dict[str, Any]:
    """S1: a suggestion (not saved) as a ScheduleSuggestion dict."""
    days = check_range(first_day, last_day)
    todos_repo = TodoRepository(db)
    if todo_ids is not None:
        found = set(db.scalars(select(Todo.id).where(Todo.user_id == user.id, Todo.id.in_(todo_ids))).all())
        if set(todo_ids) - found:
            raise not_found("todo")
    todos = list(todos_repo.not_done(user.id, todo_ids))

    planner = Planner(db, user, timeline, first_day, days, now, options)
    scheduled = todos_repo.scheduled_minutes(t.id for t in todos)
    blocks: list[Block] = []
    unscheduled: list[dict[str, Any]] = []
    for todo in todos:
        remaining = (todo.estimated_minutes or 0) - scheduled.get(todo.id, 0)
        if todo.deadline_at is None:
            unscheduled.append({"todo_id": todo.id, "reason": "MISSING_DEADLINE",
                                "missing_minutes": todo.estimated_minutes})
        elif todo.estimated_minutes is None:
            unscheduled.append({"todo_id": todo.id, "reason": "MISSING_ESTIMATE", "missing_minutes": None})
        elif todo.deadline_at <= now:
            unscheduled.append({"todo_id": todo.id, "reason": "DEADLINE_PASSED",
                                "missing_minutes": max(remaining, 0)})
        elif remaining <= 0:
            unscheduled.append({"todo_id": todo.id, "reason": "ALREADY_SCHEDULED", "missing_minutes": 0})
        else:
            for slots in split_minutes(remaining, options):
                blocks.append(Block(todo, slots, planner.allowed_starts(slots, todo.deadline_at)))

    status, placed, solve_ms = planner.solve(blocks)

    missing: dict[uuid.UUID, tuple[int, bool]] = {}
    for i, block in enumerate(blocks):
        if i in placed:
            continue
        days_of_block = {s // DAY_SLOTS for s in block.starts}
        capped = bool(days_of_block) and all(planner.day_is_full(d, placed, blocks, block.slots)
                                             for d in days_of_block)
        minutes, all_capped = missing.get(block.todo.id, (0, True))
        missing[block.todo.id] = (minutes + block.slots * SLOT_MINUTES, all_capped and capped)
    for todo_id, (minutes, capped) in missing.items():
        unscheduled.append({"todo_id": todo_id, "missing_minutes": minutes,
                            "reason": "DAILY_LIMIT_REACHED" if capped else "NOT_ENOUGH_TIME_BEFORE_DEADLINE"})

    result_blocks: list[dict[str, Any]] = []
    for i, start in placed.items():
        block = blocks[i]
        kss = planner.mean_kss(start, block.slots)
        result_blocks.append({"kind": "study", "todo_id": block.todo.id, "title": block.todo.title,
                              "start_at": planner.slot_time(start),
                              "end_at": planner.slot_time(start + block.slots),
                              "predicted_kss": round(kss, 2), "alertness_score": alertness_score(kss)})
    study = sorted(result_blocks, key=lambda b: b["start_at"])
    study_minutes = sum((b["end_at"] - b["start_at"]).total_seconds() / 60 for b in study)
    mean_kss = None
    if study_minutes:
        mean_kss = round(sum(b["predicted_kss"] * (b["end_at"] - b["start_at"]).total_seconds() / 60
                             for b in study) / study_minutes, 2)

    peaks = [w for d in range(days) for w in timeline.windows(first_day + timedelta(days=d))[0]]
    golden = sum(max(timedelta(0), min(b["end_at"], w.end) - max(b["start_at"], w.start)).total_seconds() / 60
                 for b in study for w in peaks)

    if options.include_rest_blocks and options.min_break_minutes:
        rest = timedelta(minutes=options.min_break_minutes)
        for b in study:
            first, last = planner.slot_of(b["end_at"]), planner.slot_of(b["end_at"] + rest)
            if last <= planner.n and all(planner.free[first:last]):
                result_blocks.append({"kind": "rest", "todo_id": None, "title": REST_TITLE,
                                      "start_at": b["end_at"], "end_at": b["end_at"] + rest,
                                      "predicted_kss": None, "alertness_score": None})
    if options.include_bedtime_blocks:
        for d in range(days):
            night = timeline.night(first_day + timedelta(days=d))
            wake = night.required_wake_at or night.natural_wake_at
            if night.recommended_sleep_at >= now and wake > night.recommended_sleep_at:
                result_blocks.append({"kind": "bedtime", "todo_id": None, "title": BEDTIME_TITLE,
                                      "start_at": night.recommended_sleep_at, "end_at": wake,
                                      "predicted_kss": None, "alertness_score": None})

    result_blocks.sort(key=lambda b: (b["start_at"], b["kind"]))
    for index, block in enumerate(result_blocks):
        block["index"] = index

    suggestion_id = uuid.uuid4()
    expires_at = now + SUGGESTION_TTL
    _prune(now)
    _suggestions[suggestion_id] = Suggestion(user.id, expires_at, result_blocks)
    return {
        "suggestion_id": suggestion_id,
        "expires_at": expires_at,
        "from_": first_day,
        "to": last_day,
        "solver_status": status,
        "blocks": result_blocks,
        "unscheduled": unscheduled,
        "stats": {"study_minutes": round(study_minutes), "mean_predicted_kss": mean_kss,
                  "golden_hour_ratio": round(golden / study_minutes, 2) if study_minutes else 0.0,
                  "solve_ms": solve_ms},
    }


def _prune(now: datetime) -> None:
    for key in [k for k, s in _suggestions.items() if s.expires_at <= now]:
        del _suggestions[key]


def get_suggestion(user: User, suggestion_id: uuid.UUID, now: datetime) -> Suggestion:
    suggestion = _suggestions.get(suggestion_id)
    if suggestion is None or suggestion.user_id != user.id:
        raise ApiError(404, "SUGGESTION_NOT_FOUND", "Suggestion not found")
    if suggestion.expires_at <= now:
        del _suggestions[suggestion_id]
        raise ApiError(410, "SUGGESTION_EXPIRED", "Suggestion expired; generate a new one")
    return suggestion


def discard_suggestion(suggestion_id: uuid.UUID) -> None:
    """After S2, so the same blocks cannot be applied twice."""
    _suggestions.pop(suggestion_id, None)
