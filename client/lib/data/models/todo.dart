import 'enums.dart';
import 'json_utils.dart';

/// Todo object (D1–D5).
class Todo {
  const Todo({
    required this.id,
    required this.title,
    this.description,
    required this.category,
    required this.status,
    required this.priority,
    this.deadlineAt,
    this.estimatedMinutes,
    this.difficulty,
    this.startAt,
    this.endAt,
    this.scheduledMinutes = 0,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Todo.fromJson(Json json) => Todo(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
    category: TodoCategory.fromJson(json['category']),
    status: TodoStatus.fromJson(json['status']),
    priority: Priority.fromJson(json['priority']),
    deadlineAt: parseDateTimeOrNull(json['deadline_at']),
    estimatedMinutes: json['estimated_minutes'] as int?,
    difficulty: json['difficulty'] as int?,
    startAt: parseDateTimeOrNull(json['start_at']),
    endAt: parseDateTimeOrNull(json['end_at']),
    scheduledMinutes: json['scheduled_minutes'] as int,
    completedAt: parseDateTimeOrNull(json['completed_at']),
    createdAt: parseDateTime(json['created_at']),
    updatedAt: parseDateTime(json['updated_at']),
  );

  final String id;
  final String title;
  final String? description;
  final TodoCategory category;
  final TodoStatus status;
  final Priority priority;
  final DateTime? deadlineAt;

  /// With [deadlineAt], needed for the scheduler (S1) to plan this todo.
  final int? estimatedMinutes;

  /// 1–5; hard tasks go into the golden hours (lowest predicted KSS).
  final int? difficulty;

  /// Optional fixed time.
  final DateTime? startAt;
  final DateTime? endAt;

  /// Minutes of study events already linked (read-only), for a progress
  /// bar against [estimatedMinutes].
  final int scheduledMinutes;

  /// Set by the server when [status] becomes done.
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Json toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'category': category.toJson(),
    'status': status.toJson(),
    'priority': priority.toJson(),
    'deadline_at': formatDateTimeOrNull(deadlineAt),
    'estimated_minutes': estimatedMinutes,
    'difficulty': difficulty,
    'start_at': formatDateTimeOrNull(startAt),
    'end_at': formatDateTimeOrNull(endAt),
    'scheduled_minutes': scheduledMinutes,
    'completed_at': formatDateTimeOrNull(completedAt),
    'created_at': formatDateTime(createdAt),
    'updated_at': formatDateTime(updatedAt),
  };
}

/// D2 `POST /todos` body. New todos start as `todo`.
class TodoCreate {
  const TodoCreate({
    required this.title,
    this.description,
    this.category = TodoCategory.other,
    this.priority = Priority.medium,
    this.deadlineAt,
    this.estimatedMinutes,
    this.difficulty,
    this.startAt,
    this.endAt,
  });

  final String title;
  final String? description;
  final TodoCategory category;
  final Priority priority;
  final DateTime? deadlineAt;
  final int? estimatedMinutes;
  final int? difficulty;
  final DateTime? startAt;
  final DateTime? endAt;

  Json toJson() => {
    'title': title,
    'description': description,
    'category': category.toJson(),
    'priority': priority.toJson(),
    'deadline_at': formatDateTimeOrNull(deadlineAt),
    'estimated_minutes': estimatedMinutes,
    'difficulty': difficulty,
    'start_at': formatDateTimeOrNull(startAt),
    'end_at': formatDateTimeOrNull(endAt),
  };
}

/// D4 `PATCH /todos/{id}` body. Status `done` sets `completed_at`.
class TodoUpdate {
  const TodoUpdate({
    this.title,
    this.description,
    this.category,
    this.status,
    this.priority,
    this.deadlineAt,
    this.estimatedMinutes,
    this.difficulty,
    this.startAt,
    this.endAt,
  });

  final String? title;
  final Nullable<String>? description;
  final TodoCategory? category;
  final TodoStatus? status;
  final Priority? priority;
  final Nullable<DateTime>? deadlineAt;
  final Nullable<int>? estimatedMinutes;
  final Nullable<int>? difficulty;
  final Nullable<DateTime>? startAt;
  final Nullable<DateTime>? endAt;

  Json toJson() {
    final json = <String, Object?>{
      'title': ?title,
      'category': ?category?.toJson(),
      'status': ?status?.toJson(),
      'priority': ?priority?.toJson(),
    };
    putNullable(json, 'description', description);
    putNullable(json, 'deadline_at', deadlineAt, formatDateTime);
    putNullable(json, 'estimated_minutes', estimatedMinutes);
    putNullable(json, 'difficulty', difficulty);
    putNullable(json, 'start_at', startAt, formatDateTime);
    putNullable(json, 'end_at', endAt, formatDateTime);
    return json;
  }
}

/// D1 sort order.
enum TodoSort {
  deadlineAsc('deadline_at'),
  deadlineDesc('-deadline_at'),
  priorityAsc('priority'),
  priorityDesc('-priority'),
  createdAsc('created_at'),
  createdDesc('-created_at');

  const TodoSort(this.value);
  final String value;
}

/// D1 filters. [statuses] may hold several values (`?status=a&status=b`).
class TodoQuery {
  const TodoQuery({
    this.statuses = const [],
    this.category,
    this.dueBefore,
    this.dueAfter,
    this.sort,
  });

  final List<TodoStatus> statuses;
  final TodoCategory? category;
  final DateTime? dueBefore;
  final DateTime? dueAfter;

  /// Server default: deadline first, todos without a deadline last.
  final TodoSort? sort;

  Map<String, Object?> toQuery() => {
    'status': [for (final s in statuses) s.value],
    'category': category?.value,
    'due_before': formatDateTimeOrNull(dueBefore),
    'due_after': formatDateTimeOrNull(dueAfter),
    'sort': sort?.value,
  };
}

/// Todo parsed from a voice recording (V1). Not saved; the app lets the
/// user edit it, then sends it to D2.
class TodoDraft {
  const TodoDraft({
    required this.title,
    this.description,
    required this.category,
    required this.priority,
    this.deadlineAt,
    this.estimatedMinutes,
    this.difficulty,
  });

  factory TodoDraft.fromJson(Json json) => TodoDraft(
    title: json['title'] as String,
    description: json['description'] as String?,
    category: TodoCategory.fromJson(json['category']),
    priority: Priority.fromJson(json['priority']),
    deadlineAt: parseDateTimeOrNull(json['deadline_at']),
    estimatedMinutes: json['estimated_minutes'] as int?,
    difficulty: json['difficulty'] as int?,
  );

  final String title;
  final String? description;
  final TodoCategory category;
  final Priority priority;
  final DateTime? deadlineAt;
  final int? estimatedMinutes;
  final int? difficulty;

  Json toJson() => {
    'title': title,
    'description': description,
    'category': category.toJson(),
    'priority': priority.toJson(),
    'deadline_at': formatDateTimeOrNull(deadlineAt),
    'estimated_minutes': estimatedMinutes,
    'difficulty': difficulty,
  };
}

/// V1 `POST /voice/transcribe` response.
class VoiceTranscription {
  const VoiceTranscription({
    required this.transcript,
    this.todoDraft,
    required this.parser,
  });

  factory VoiceTranscription.fromJson(Json json) => VoiceTranscription(
    transcript: json['transcript'] as String,
    todoDraft: json['todo_draft'] == null
        ? null
        : TodoDraft.fromJson(json['todo_draft'] as Json),
    parser: json['parser'] as String,
  );

  final String transcript;

  /// `null` if no todo could be extracted from the transcript.
  final TodoDraft? todoDraft;

  /// `gemini`, or `rules` when Gemini was down.
  final String parser;

  Json toJson() => {
    'transcript': transcript,
    'todo_draft': todoDraft?.toJson(),
    'parser': parser,
  };
}
