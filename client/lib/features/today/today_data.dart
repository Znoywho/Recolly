import 'package:client/data/data.dart';

class TodayData {
  const TodayData({
    required this.overview,
    this.sleepDebt,
    this.quote,
    this.user,
  });

  final HomeOverview overview;
  final SleepDebt? sleepDebt;
  final Quote? quote;
  final User? user;

  static Future<TodayData> load(AppRepositories repositories) async {
    final overview = repositories.home.getOverview();
    final sleepDebt = _orNull(repositories.sleep.getSleepDebt());
    final quote = _orNull(repositories.reminders.randomQuote());
    final user = _orNull(repositories.user.getMe());
    return TodayData(
      overview: await overview,
      sleepDebt: await sleepDebt,
      quote: await quote,
      user: await user,
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
