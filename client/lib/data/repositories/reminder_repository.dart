import '../api/api_client.dart';
import '../models/models.dart';

/// Reminder settings, push devices and motivation quotes (R1–R5).
abstract interface class ReminderRepository {
  Future<ReminderSettings> getSettings();

  Future<ReminderSettings> saveSettings(ReminderSettings settings);

  Future<void> registerDevice(
    String fcmToken, {
    DevicePlatform platform = DevicePlatform.android,
  });

  Future<void> unregisterDevice(String fcmToken);

  Future<Quote> randomQuote({QuoteContext context = QuoteContext.general});
}

class ApiReminderRepository implements ReminderRepository {
  ApiReminderRepository(this._client);

  final ApiClient _client;

  @override
  Future<ReminderSettings> getSettings() async =>
      ReminderSettings.fromJson(await _client.get('reminder-settings') as Json);

  @override
  Future<ReminderSettings> saveSettings(ReminderSettings settings) async =>
      ReminderSettings.fromJson(
        await _client.put('reminder-settings', body: settings.toJson()) as Json,
      );

  @override
  Future<void> registerDevice(
    String fcmToken, {
    DevicePlatform platform = DevicePlatform.android,
  }) => _client.post(
    'devices',
    body: {'fcm_token': fcmToken, 'platform': platform.value},
  );

  @override
  Future<void> unregisterDevice(String fcmToken) =>
      _client.delete('devices/${Uri.encodeComponent(fcmToken)}');

  @override
  Future<Quote> randomQuote({
    QuoteContext context = QuoteContext.general,
  }) async => Quote.fromJson(
    await _client.get('quotes/random', query: {'context': context.value})
        as Json,
  );
}
