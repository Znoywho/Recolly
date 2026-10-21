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
  final int? estimatedMinutes;

  /// 1–5; hard tasks go into peak alertness windows.
  final int? difficulty;

  /// Optional fixed time.
  final DateTime? startAt;
  final DateTime? endAt;
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
    'created_at': formatDateTime(createdAt),
    'updated_at': formatDateTime(updatedAt),
  };
}

/// D2 `POST /todos` body.
class TodoCreate {
  const TodoCreate({
    required this.title,
    this.description,
    this.category = TodoCategory.other,
    this.status = TodoStatus.todo,
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
  final TodoStatus status;
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
    'status': status.toJson(),
    'priority': priority.toJson(),
    'deadline_at': formatDateTimeOrNull(deadlineAt),
    'estimated_minutes': estimatedMinutes,
    'difficulty': difficulty,
    'start_at': formatDateTimeOrNull(startAt),
    'end_at': formatDateTimeOrNull(endAt),
  };
}

/// D4 `PATCH /todos/{id}` body.
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

/// D1 filters.
class TodoQuery {
  const TodoQuery({this.status, this.category, this.dueBefore});

  final TodoStatus? status;
  final TodoCategory? category;
  final DateTime? dueBefore;

  Map<String, Object?> toQuery() => {
    'status': status?.value,
    'category': category?.value,
    'due_before': formatDateTimeOrNull(dueBefore),
  };
}

/// Todo parsed from a voice recording (V1). Not saved; the app sends it to
/// D2 after the user confirms.
class TodoDraft {
  const TodoDraft({
    required this.title,
    this.category,
    this.deadlineAt,
    this.estimatedMinutes,
    this.priority,
  });

  factory TodoDraft.fromJson(Json json) => TodoDraft(
    title: json['title'] as String,
    category: json['category'] == null
        ? null
        : TodoCategory.fromJson(json['category']),
    deadlineAt: parseDateTimeOrNull(json['deadline_at']),
    estimatedMinutes: json['estimated_minutes'] as int?,
    priority: json['priority'] == null
        ? null
        : Priority.fromJson(json['priority']),
  );

  final String title;
  final TodoCategory? category;
  final DateTime? deadlineAt;
  final int? estimatedMinutes;
  final Priority? priority;

  Json toJson() => {
    'title': title,
    'category': category?.toJson(),
    'deadline_at': formatDateTimeOrNull(deadlineAt),
    'estimated_minutes': estimatedMinutes,
    'priority': priority?.toJson(),
  };
}

/// V1 `POST /voice/transcribe` response.
class VoiceTranscription {
  const VoiceTranscription({required this.transcript, this.todoDraft});

  factory VoiceTranscription.fromJson(Json json) => VoiceTranscription(
    transcript: json['transcript'] as String,
    todoDraft: json['todo_draft'] == null
        ? null
        : TodoDraft.fromJson(json['todo_draft'] as Json),
  );

  final String transcript;

  /// `null` if no todo could be extracted from the transcript.
  final TodoDraft? todoDraft;

  Json toJson() => {
    'transcript': transcript,
    'todo_draft': todoDraft?.toJson(),
  };
}
