import 'calendar_sync.dart';
import 'enums.dart';
import 'event.dart';
import 'json_utils.dart';
import 'sleep.dart';

/// S1 solver options. Unset fields are omitted so the server defaults apply
/// (240 min/day, 90-min blocks, ≥ 30-min breaks, meal windows 11:30–13:00
/// and 18:00–19:00, bedtime blocks on).
class ScheduleOptions {
  const ScheduleOptions({
    this.maxStudyMinutesPerDay,
    this.blockMinutes,
    this.minBlockMinutes,
    this.minBreakMinutes,
    this.wakeBufferMinutes,
    this.bedBufferMinutes,
    this.mealWindows,
    this.includeRestBlocks,
    this.includeBedtimeBlocks,
  });

  final int? maxStudyMinutesPerDay;
  final int? blockMinutes;
  final int? minBlockMinutes;
  final int? minBreakMinutes;

  /// No study right after waking (sleep inertia).
  final int? wakeBufferMinutes;

  /// No study before the recommended bedtime.
  final int? bedBufferMinutes;
  final List<ClockWindow>? mealWindows;
  final bool? includeRestBlocks;
  final bool? includeBedtimeBlocks;

  Json toJson() => {
    'max_study_minutes_per_day': ?maxStudyMinutesPerDay,
    'block_minutes': ?blockMinutes,
    'min_block_minutes': ?minBlockMinutes,
    'min_break_minutes': ?minBreakMinutes,
    'wake_buffer_minutes': ?wakeBufferMinutes,
    'bed_buffer_minutes': ?bedBufferMinutes,
    'meal_windows': ?mealWindows?.map((w) => w.toJson()).toList(),
    'include_rest_blocks': ?includeRestBlocks,
    'include_bedtime_blocks': ?includeBedtimeBlocks,
  };
}

/// S1 `POST /schedule/generate` body.
class ScheduleRequest {
  const ScheduleRequest({
    required this.from,
    required this.to,
    this.todoIds,
    this.options,
  });

  /// Dates, inclusive; at most 14 days.
  final DateTime from;
  final DateTime to;

  /// `null` → every todo that is not done.
  final List<String>? todoIds;
  final ScheduleOptions? options;

  Json toJson() => {
    'from': formatDate(from),
    'to': formatDate(to),
    'todo_ids': todoIds,
    'options': ?options?.toJson(),
  };
}

/// One suggested block from the CP-SAT solver.
class ScheduleBlock {
  const ScheduleBlock({
    required this.index,
    required this.kind,
    this.todoId,
    required this.title,
    required this.startAt,
    required this.endAt,
    this.predictedKss,
    this.alertnessScore,
  });

  factory ScheduleBlock.fromJson(Json json) => ScheduleBlock(
    index: json['index'] as int,
    kind: EventKind.fromJson(json['kind']),
    todoId: json['todo_id'] as String?,
    title: json['title'] as String,
    startAt: parseDateTime(json['start_at']),
    endAt: parseDateTime(json['end_at']),
    predictedKss: parseDoubleOrNull(json['predicted_kss']),
    alertnessScore: json['alertness_score'] as int?,
  );

  /// Pass to S2 `blockIndexes` to apply only some blocks.
  final int index;

  /// `study`, `rest` or `bedtime`.
  final EventKind kind;
  final String? todoId;
  final String title;
  final DateTime startAt;
  final DateTime endAt;

  /// `null` for bedtime blocks.
  final double? predictedKss;
  final int? alertnessScore;

  Json toJson() => {
    'index': index,
    'kind': kind.toJson(),
    'todo_id': todoId,
    'title': title,
    'start_at': formatDateTime(startAt),
    'end_at': formatDateTime(endAt),
    'predicted_kss': predictedKss,
    'alertness_score': alertnessScore,
  };
}

class UnscheduledTodo {
  const UnscheduledTodo({
    required this.todoId,
    required this.reason,
    this.missingMinutes,
  });

  factory UnscheduledTodo.fromJson(Json json) => UnscheduledTodo(
    todoId: json['todo_id'] as String,
    reason: json['reason'] as String,
    missingMinutes: json['missing_minutes'] as int?,
  );

  final String todoId;

  /// `NOT_ENOUGH_TIME_BEFORE_DEADLINE`, `MISSING_DEADLINE`,
  /// `MISSING_ESTIMATE`, `DEADLINE_PASSED`, `DAILY_LIMIT_REACHED` or
  /// `ALREADY_SCHEDULED`.
  final String reason;
  final int? missingMinutes;

  Json toJson() => {
    'todo_id': todoId,
    'reason': reason,
    'missing_minutes': missingMinutes,
  };
}

class ScheduleStats {
  const ScheduleStats({
    required this.studyMinutes,
    this.meanPredictedKss,
    required this.goldenHourRatio,
    required this.solveMs,
  });

  factory ScheduleStats.fromJson(Json json) => ScheduleStats(
    studyMinutes: json['study_minutes'] as int,
    meanPredictedKss: parseDoubleOrNull(json['mean_predicted_kss']),
    goldenHourRatio: parseDouble(json['golden_hour_ratio']),
    solveMs: json['solve_ms'] as int,
  );

  final int studyMinutes;
  final double? meanPredictedKss;

  /// Share of study minutes inside golden hours, 0–1.
  final double goldenHourRatio;
  final int solveMs;

  Json toJson() => {
    'study_minutes': studyMinutes,
    'mean_predicted_kss': meanPredictedKss,
    'golden_hour_ratio': goldenHourRatio,
    'solve_ms': solveMs,
  };
}

/// S1 response. Not saved; S2 answers `410 SUGGESTION_EXPIRED` after
/// [expiresAt].
class ScheduleSuggestion {
  const ScheduleSuggestion({
    required this.suggestionId,
    required this.expiresAt,
    required this.from,
    required this.to,
    required this.solverStatus,
    required this.blocks,
    required this.unscheduled,
    required this.stats,
    required this.model,
  });

  factory ScheduleSuggestion.fromJson(Json json) => ScheduleSuggestion(
    suggestionId: json['suggestion_id'] as String,
    expiresAt: parseDateTime(json['expires_at']),
    from: parseDate(json['from']),
    to: parseDate(json['to']),
    solverStatus: json['solver_status'] as String,
    blocks: parseList(json['blocks'], ScheduleBlock.fromJson),
    unscheduled: parseList(json['unscheduled'], UnscheduledTodo.fromJson),
    stats: ScheduleStats.fromJson(json['stats'] as Json),
    model: ModelSummary.fromJson(json['model'] as Json),
  );

  final String suggestionId;
  final DateTime expiresAt;
  final DateTime from;
  final DateTime to;

  /// `OPTIMAL`, `FEASIBLE`, `INFEASIBLE`, `MODEL_INVALID` or `UNKNOWN`.
  final String solverStatus;
  final List<ScheduleBlock> blocks;
  final List<UnscheduledTodo> unscheduled;
  final ScheduleStats stats;
  final ModelSummary model;

  Json toJson() => {
    'suggestion_id': suggestionId,
    'expires_at': formatDateTime(expiresAt),
    'from': formatDate(from),
    'to': formatDate(to),
    'solver_status': solverStatus,
    'blocks': [for (final b in blocks) b.toJson()],
    'unscheduled': [for (final u in unscheduled) u.toJson()],
    'stats': stats.toJson(),
    'model': model.toJson(),
  };
}

/// S2 `POST /schedule/apply` response.
class ScheduleApplyResult {
  const ScheduleApplyResult({required this.events, this.sync});

  factory ScheduleApplyResult.fromJson(Json json) => ScheduleApplyResult(
    events: parseList(json['events'], CalendarEvent.fromJson),
    sync: json['sync'] == null
        ? null
        : SyncResult.fromJson(json['sync'] as Json),
  );

  final List<CalendarEvent> events;

  /// `null` when `sync_to_google` was false.
  final SyncResult? sync;

  Json toJson() => {
    'events': [for (final e in events) e.toJson()],
    'sync': sync?.toJson(),
  };
}
