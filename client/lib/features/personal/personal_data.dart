import 'package:client/data/data.dart';

class PersonalData {
  const PersonalData({
    this.user,
    this.reminderSettings,
    this.healthProfile,
    this.calendarStatus,
  });

  final User? user;
  final ReminderSettings? reminderSettings;
  final HealthProfile? healthProfile;
  final CalendarStatus? calendarStatus;

  bool get isGoogleConnected =>
      calendarStatus?.connected ?? user?.googleCalendarConnected ?? false;

  static Future<PersonalData> load(AppRepositories repositories) async {
    final user = _orNull(repositories.user.getMe());
    final reminderSettings = _orNull(repositories.reminders.getSettings());
    final healthProfile = _orNull(repositories.sleep.getHealthProfile());
    final calendarStatus = _orNull(repositories.calendarSync.getStatus());
    return PersonalData(
      user: await user,
      reminderSettings: await reminderSettings,
      healthProfile: await healthProfile,
      calendarStatus: await calendarStatus,
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
