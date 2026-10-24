import 'enums.dart';
import 'json_utils.dart';

/// A class in the timetable before it is saved: an OCR result row (T2) or a
/// row the user typed / edited, sent to T4 `POST /timetable`.
class SubjectDraft {
  const SubjectDraft({
    required this.name,
    this.code,
    this.room,
    this.lecturer,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.startDate,
    required this.endDate,
    this.color,
    this.confidence,
  });

  factory SubjectDraft.fromJson(Json json) => SubjectDraft(
    name: json['name'] as String,
    code: json['code'] as String?,
    room: json['room'] as String?,
    lecturer: json['lecturer'] as String?,
    dayOfWeek: json['day_of_week'] as int,
    startTime: ClockTime.fromJson(json['start_time']),
    endTime: ClockTime.fromJson(json['end_time']),
    startDate: parseDate(json['start_date']),
    endDate: parseDate(json['end_date']),
    color: json['color'] as String?,
    confidence: (json['confidence'] as num?)?.toDouble(),
  );

  final String name;
  final String? code;
  final String? room;
  final String? lecturer;

  /// 1 = Monday … 7 = Sunday (same as [DateTime.weekday]).
  final int dayOfWeek;
  final ClockTime startTime;
  final ClockTime endTime;

  /// First and last week of the course.
  final DateTime startDate;
  final DateTime endDate;

  /// Hex color such as `#FFD23F`.
  final String? color;

  /// OCR confidence 0–1. Only set on OCR results; not sent to T4.
  final double? confidence;

  /// Body for T4 (without `confidence`).
  Json toJson() => {
    'name': name,
    'code': code,
    'room': room,
    'lecturer': lecturer,
    'day_of_week': dayOfWeek,
    'start_time': startTime.toJson(),
    'end_time': endTime.toJson(),
    'start_date': formatDate(startDate),
    'end_date': formatDate(endDate),
    'color': color,
  };
}

/// A saved class (T3–T6).
class Subject {
  const Subject({
    required this.id,
    required this.name,
    this.code,
    this.room,
    this.lecturer,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.startDate,
    required this.endDate,
    this.color,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Subject.fromJson(Json json) => Subject(
    id: json['id'] as String,
    name: json['name'] as String,
    code: json['code'] as String?,
    room: json['room'] as String?,
    lecturer: json['lecturer'] as String?,
    dayOfWeek: json['day_of_week'] as int,
    startTime: ClockTime.fromJson(json['start_time']),
    endTime: ClockTime.fromJson(json['end_time']),
    startDate: parseDate(json['start_date']),
    endDate: parseDate(json['end_date']),
    color: json['color'] as String?,
    createdAt: parseDateTime(json['created_at']),
    updatedAt: parseDateTime(json['updated_at']),
  );

  final String id;
  final String name;
  final String? code;
  final String? room;
  final String? lecturer;

  /// 1 = Monday … 7 = Sunday.
  final int dayOfWeek;
  final ClockTime startTime;
  final ClockTime endTime;
  final DateTime startDate;
  final DateTime endDate;
  final String? color;
  final DateTime createdAt;
  final DateTime updatedAt;

  Json toJson() => {
    'id': id,
    'name': name,
    'code': code,
    'room': room,
    'lecturer': lecturer,
    'day_of_week': dayOfWeek,
    'start_time': startTime.toJson(),
    'end_time': endTime.toJson(),
    'start_date': formatDate(startDate),
    'end_date': formatDate(endDate),
    'color': color,
    'created_at': formatDateTime(createdAt),
    'updated_at': formatDateTime(updatedAt),
  };
}

/// T5 `PATCH /timetable/{id}` body. The server also updates the subject's
/// recurring class event.
class SubjectUpdate {
  const SubjectUpdate({
    this.name,
    this.code,
    this.room,
    this.lecturer,
    this.dayOfWeek,
    this.startTime,
    this.endTime,
    this.startDate,
    this.endDate,
    this.color,
  });

  final String? name;
  final Nullable<String>? code;
  final Nullable<String>? room;
  final Nullable<String>? lecturer;
  final int? dayOfWeek;
  final ClockTime? startTime;
  final ClockTime? endTime;
  final DateTime? startDate;
  final DateTime? endDate;
  final Nullable<String>? color;

  Json toJson() {
    final json = <String, Object?>{
      'name': ?name,
      'day_of_week': ?dayOfWeek,
      'start_time': ?startTime?.toJson(),
      'end_time': ?endTime?.toJson(),
      'start_date': ?formatDateOrNull(startDate),
      'end_date': ?formatDateOrNull(endDate),
    };
    putNullable(json, 'code', code);
    putNullable(json, 'room', room);
    putNullable(json, 'lecturer', lecturer);
    putNullable(json, 'color', color);
    return json;
  }
}

/// T1 / T2 OCR job.
class OcrJob {
  const OcrJob({
    required this.jobId,
    required this.status,
    this.error,
    this.subjects = const [],
    this.createdAt,
  });

  factory OcrJob.fromJson(Json json) {
    final result = json['result'] as Json?;
    return OcrJob(
      jobId: json['job_id'] as String,
      status: JobStatus.fromJson(json['status']),
      error: json['error'] as String?,
      subjects: result == null
          ? const []
          : parseList(result['subjects'], SubjectDraft.fromJson),
      createdAt: parseDateTimeOrNull(json['created_at']),
    );
  }

  final String jobId;
  final JobStatus status;

  /// Error code when [status] is failed: `OCR_NO_TABLE_FOUND`,
  /// `OCR_LOW_QUALITY` or `OCR_MODEL_ERROR` (scan-failed screen, R62).
  final String? error;

  /// Parsed rows when [status] is succeeded.
  final List<SubjectDraft> subjects;

  /// `null` in the T1 upload response.
  final DateTime? createdAt;

  Json toJson() => {
    'job_id': jobId,
    'status': status.toJson(),
    'error': error,
    'result': status == JobStatus.succeeded
        ? {
            'subjects': [
              for (final s in subjects)
                {...s.toJson(), 'confidence': s.confidence},
            ],
          }
        : null,
    'created_at': formatDateTimeOrNull(createdAt),
  };
}
