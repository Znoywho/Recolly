import 'enums.dart';
import 'json_utils.dart';

class QuietHours {
  const QuietHours({required this.start, required this.end});

  factory QuietHours.fromJson(Json json) => QuietHours(
    start: ClockTime.fromJson(json['start']),
    end: ClockTime.fromJson(json['end']),
  );

  final ClockTime start;
  final ClockTime end;

  Json toJson() => {'start': start.toJson(), 'end': end.toJson()};
}

/// R1 / R2 reminder settings.
class ReminderSettings {
  const ReminderSettings({
    required this.bedtimeReminderEnabled,
    required this.bedtimeReminderMinutesBefore,
    required this.deadlineReminderEnabled,
    required this.deadlineReminderHoursBefore,
    required this.motivationEnabled,
    this.quietHours,
  });

  factory ReminderSettings.fromJson(Json json) => ReminderSettings(
    bedtimeReminderEnabled: json['bedtime_reminder_enabled'] as bool,
    bedtimeReminderMinutesBefore:
        json['bedtime_reminder_minutes_before'] as int,
    deadlineReminderEnabled: json['deadline_reminder_enabled'] as bool,
    deadlineReminderHoursBefore:
        (json['deadline_reminder_hours_before'] as List).cast<int>(),
    motivationEnabled: json['motivation_enabled'] as bool,
    quietHours: json['quiet_hours'] == null
        ? null
        : QuietHours.fromJson(json['quiet_hours'] as Json),
  );

  final bool bedtimeReminderEnabled;
  final int bedtimeReminderMinutesBefore;
  final bool deadlineReminderEnabled;

  /// e.g. `[24, 2]` → remind 24h and 2h before each deadline.
  final List<int> deadlineReminderHoursBefore;
  final bool motivationEnabled;
  final QuietHours? quietHours;

  Json toJson() => {
    'bedtime_reminder_enabled': bedtimeReminderEnabled,
    'bedtime_reminder_minutes_before': bedtimeReminderMinutesBefore,
    'deadline_reminder_enabled': deadlineReminderEnabled,
    'deadline_reminder_hours_before': deadlineReminderHoursBefore,
    'motivation_enabled': motivationEnabled,
    'quiet_hours': quietHours?.toJson(),
  };
}

/// R5 `GET /quotes/random`.
class Quote {
  const Quote({required this.text, this.author, required this.source});

  factory Quote.fromJson(Json json) => Quote(
    text: json['text'] as String,
    author: json['author'] as String?,
    source: QuoteSource.fromJson(json['source']),
  );

  final String text;
  final String? author;
  final QuoteSource source;

  Json toJson() => {'text': text, 'author': author, 'source': source.toJson()};
}
