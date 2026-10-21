import 'api/api_client.dart';
import 'api/api_config.dart';
import 'mock/mock_repositories.dart';
import 'repositories/auth_repository.dart';
import 'repositories/calendar_sync_repository.dart';
import 'repositories/event_repository.dart';
import 'repositories/reminder_repository.dart';
import 'repositories/schedule_repository.dart';
import 'repositories/sleep_repository.dart';
import 'repositories/timetable_repository.dart';
import 'repositories/todo_repository.dart';
import 'repositories/user_repository.dart';
import 'repositories/voice_repository.dart';

/// Every repository the app uses. Screens depend on the interfaces only, so
/// switching between mock and real backend is one line:
///
/// ```dart
/// final repos = AppRepositories.fromEnvironment(); // USE_MOCK_API, default mock
/// final todos = await repos.todos.listTodos();
/// ```
class AppRepositories {
  const AppRepositories({
    required this.auth,
    required this.user,
    required this.sleep,
    required this.timetable,
    required this.events,
    required this.todos,
    required this.voice,
    required this.schedule,
    required this.calendarSync,
    required this.reminders,
  });

  factory AppRepositories.api(ApiClient client) => AppRepositories(
    auth: ApiAuthRepository(client),
    user: ApiUserRepository(client),
    sleep: ApiSleepRepository(client),
    timetable: ApiTimetableRepository(client),
    events: ApiEventRepository(client),
    todos: ApiTodoRepository(client),
    voice: ApiVoiceRepository(client),
    schedule: ApiScheduleRepository(client),
    calendarSync: ApiCalendarSyncRepository(client),
    reminders: ApiReminderRepository(client),
  );

  /// [latency] simulates network delay so loading states can be seen.
  factory AppRepositories.mock({Duration latency = Duration.zero}) =>
      AppRepositories(
        auth: MockAuthRepository(latency: latency),
        user: MockUserRepository(latency: latency),
        sleep: MockSleepRepository(latency: latency),
        timetable: MockTimetableRepository(latency: latency),
        events: MockEventRepository(latency: latency),
        todos: MockTodoRepository(latency: latency),
        voice: MockVoiceRepository(latency: latency),
        schedule: MockScheduleRepository(latency: latency),
        calendarSync: MockCalendarSyncRepository(latency: latency),
        reminders: MockReminderRepository(latency: latency),
      );

  /// Mock unless built with `--dart-define=USE_MOCK_API=false`.
  factory AppRepositories.fromEnvironment() => ApiConfig.useMock
      ? AppRepositories.mock(latency: const Duration(milliseconds: 300))
      : AppRepositories.api(ApiClient(baseUrl: ApiConfig.baseUrl));

  final AuthRepository auth;
  final UserRepository user;
  final SleepRepository sleep;
  final TimetableRepository timetable;
  final EventRepository events;
  final TodoRepository todos;
  final VoiceRepository voice;
  final ScheduleRepository schedule;
  final CalendarSyncRepository calendarSync;
  final ReminderRepository reminders;
}
