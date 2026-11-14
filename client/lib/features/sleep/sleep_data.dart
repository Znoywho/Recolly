import 'package:client/data/data.dart';

class SleepData {
  const SleepData({
    required this.sleepDebt,
    this.tonight,
    this.reminderSettings,
  });

  final SleepDebt sleepDebt;
  final ProjectedSleep? tonight;
  final ReminderSettings? reminderSettings;

  bool get hasSleepLogs => sleepDebt.daily.any((night) => night.hasData);

  int get goalMinutes => sleepDebt.daily.firstOrNull?.needMinutes ?? 8 * 60;

  int? get earlierBedtimeMinutes {
    final tonight = this.tonight;
    final requiredWakeAt = tonight?.requiredWakeAt;
    if (tonight == null || requiredWakeAt == null) return null;
    final minutes = tonight.naturalWakeAt.difference(requiredWakeAt).inMinutes;
    return minutes > 0 ? minutes : null;
  }

  SleepData withReminderSettings(ReminderSettings settings) => SleepData(
    sleepDebt: sleepDebt,
    tonight: tonight,
    reminderSettings: settings,
  );

  static Future<SleepData> load(AppRepositories repositories) async {
    final sleepDebt = repositories.sleep.getSleepDebt();
    final biorhythm = _orNull(repositories.sleep.getBiorhythm());
    final reminderSettings = _orNull(repositories.reminders.getSettings());
    return SleepData(
      sleepDebt: await sleepDebt,
      tonight: (await biorhythm)?.projectedSleep.firstOrNull,
      reminderSettings: await reminderSettings,
    );
  }

  static Future<T?> _orNull<T>(Future<T> future) async {
    try {
      return await future;
    } on Exception {
      return null;
    }
  }
}
