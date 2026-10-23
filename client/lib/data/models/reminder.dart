import 'enums.dart';
import 'json_utils.dart';

/// R1 / R2 reminder settings.
class ReminderSettings {
  const ReminderSettings({
    required this.bedtimeReminderEnabled,
    required this.bedtimeReminderMinutesBefore,
    required this.deadlineReminderEnabled,
    required this.deadlineReminderHoursBefore,
    required this.kssPromptEnabled,
    required this.kssPromptsPerDay,
    required this.kssPromptWindow,
    required this.sleepConfirmEnabled,
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
    kssPromptEnabled: json['kss_prompt_enabled'] as bool,
    kssPromptsPerDay: json['kss_prompts_per_day'] as int,
    kssPromptWindow: ClockWindow.fromJson(json['kss_prompt_window'] as Json),
    sleepConfirmEnabled: json['sleep_confirm_enabled'] as bool,
    motivationEnabled: json['motivation_enabled'] as bool,
    quietHours: json['quiet_hours'] == null
        ? null
        : ClockWindow.fromJson(json['quiet_hours'] as Json),
  );

  final bool bedtimeReminderEnabled;

  /// Before tonight's `recommended_sleep_at` (H8 projected sleep).
  final int bedtimeReminderMinutesBefore;
  final bool deadlineReminderEnabled;

  /// e.g. `[24, 2]` → remind 24h and 2h before each deadline.
  final List<int> deadlineReminderHoursBefore;

  /// Sleepiness check-in pushes (1–6 a day inside [kssPromptWindow]).
  final bool kssPromptEnabled;
  final int kssPromptsPerDay;
  final ClockWindow kssPromptWindow;

  /// Morning push to confirm last night's inferred sleep.
  final bool sleepConfirmEnabled;
  final bool motivationEnabled;
  final ClockWindow? quietHours;

  Json toJson() => {
    'bedtime_reminder_enabled': bedtimeReminderEnabled,
    'bedtime_reminder_minutes_before': bedtimeReminderMinutesBefore,
    'deadline_reminder_enabled': deadlineReminderEnabled,
    'deadline_reminder_hours_before': deadlineReminderHoursBefore,
    'kss_prompt_enabled': kssPromptEnabled,
    'kss_prompts_per_day': kssPromptsPerDay,
    'kss_prompt_window': kssPromptWindow.toJson(),
    'sleep_confirm_enabled': sleepConfirmEnabled,
    'motivation_enabled': motivationEnabled,
    'quiet_hours': quietHours?.toJson(),
  };
}

/// R5 `GET /quotes/random`.
class Quote {
  const Quote({
    required this.text,
    this.author,
    required this.source,
    required this.context,
  });

  factory Quote.fromJson(Json json) => Quote(
    text: json['text'] as String,
    author: json['author'] as String?,
    source: QuoteSource.fromJson(json['source']),
    context: QuoteContext.fromJson(json['context']),
  );

  final String text;
  final String? author;
  final QuoteSource source;
  final QuoteContext context;

  Json toJson() => {
    'text': text,
    'author': author,
    'source': source.toJson(),
    'context': context.toJson(),
  };
}
