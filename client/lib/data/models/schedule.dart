import 'json_utils.dart';

class ScheduleOptions {
  const ScheduleOptions({
    this.maxStudyMinutesPerDay = 240,
    this.blockMinutes = 50,
    this.breakMinutes = 10,
  });

  final int maxStudyMinutesPerDay;
  final int blockMinutes;
  final int breakMinutes;

  Json toJson() => {
    'max_study_minutes_per_day': maxStudyMinutesPerDay,
    'block_minutes': blockMinutes,
    'break_minutes': breakMinutes,
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

  /// Dates (inclusive).
  final DateTime from;
  final DateTime to;

  /// `null` → every todo that is not done.
  final List<String>? todoIds;
  final ScheduleOptions? options;

  Json toJson() => {
    'from': formatDate(from),
    'to': formatDate(to),
    'todo_ids': todoIds,
    'options': options?.toJson(),
  };
}

/// One suggested study block from the CP-SAT solver.
class StudyBlock {
  const StudyBlock({
    required this.todoId,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.alertness,
  });

  factory StudyBlock.fromJson(Json json) => StudyBlock(
    todoId: json['todo_id'] as String,
    title: json['title'] as String,
    startAt: parseDateTime(json['start_at']),
    endAt: parseDateTime(json['end_at']),
    alertness: parseDouble(json['alertness']),
  );

  final String todoId;
  final String title;
  final DateTime startAt;
  final DateTime endAt;

  /// Predicted alertness 0–1 during the block.
  final double alertness;

  Json toJson() => {
    'todo_id': todoId,
    'title': title,
    'start_at': formatDateTime(startAt),
    'end_at': formatDateTime(endAt),
    'alertness': alertness,
  };
}

class UnscheduledTodo {
  const UnscheduledTodo({required this.todoId, required this.reason});

  factory UnscheduledTodo.fromJson(Json json) => UnscheduledTodo(
    todoId: json['todo_id'] as String,
    reason: json['reason'] as String,
  );

  final String todoId;

  /// e.g. `NOT_ENOUGH_TIME_BEFORE_DEADLINE`.
  final String reason;

  Json toJson() => {'todo_id': todoId, 'reason': reason};
}

/// S1 response. Not saved; expires after 1 hour.
class ScheduleSuggestion {
  const ScheduleSuggestion({
    required this.suggestionId,
    required this.blocks,
    required this.unscheduled,
    required this.solverStatus,
  });

  factory ScheduleSuggestion.fromJson(Json json) => ScheduleSuggestion(
    suggestionId: json['suggestion_id'] as String,
    blocks: parseList(json['blocks'], StudyBlock.fromJson),
    unscheduled: parseList(json['unscheduled'], UnscheduledTodo.fromJson),
    solverStatus: json['solver_status'] as String,
  );

  final String suggestionId;
  final List<StudyBlock> blocks;
  final List<UnscheduledTodo> unscheduled;

  /// CP-SAT status, e.g. `OPTIMAL`, `FEASIBLE`, `INFEASIBLE`.
  final String solverStatus;

  Json toJson() => {
    'suggestion_id': suggestionId,
    'blocks': [for (final b in blocks) b.toJson()],
    'unscheduled': [for (final u in unscheduled) u.toJson()],
    'solver_status': solverStatus,
  };
}
