import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum NotificationCategory {
  sleep('Giấc ngủ', Icons.bedtime_outlined, AppColors.teal),
  deadline('Deadline', Icons.schedule_rounded, AppColors.coral),
  study('Học tập', Icons.star_outline_rounded, AppColors.green),
  motivation('Học tập', Icons.flag_outlined, AppColors.yellow);

  const NotificationCategory(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

class AppNotification {
  const AppNotification({
    required this.category,
    required this.title,
    required this.time,
    required this.message,
  });

  final NotificationCategory category;
  final String title;
  final DateTime time;
  final String message;
}

class NotificationsData {
  const NotificationsData({required this.notifications, this.chronotype});

  static const int _dailyQuoteHour = 8;

  final List<AppNotification> notifications;

  /// The user's animal, shown as the mascot giving each reminder.
  /// `null` before onboarding.
  final Chronotype? chronotype;

  static Future<NotificationsData> load(AppRepositories repositories) async {
    final overview = repositories.home.getOverview();
    final settings = _orNull(repositories.reminders.getSettings());
    final quote = _orNull(repositories.reminders.randomQuote());
    final profile = _orNull(repositories.sleep.getHealthProfile());
    return NotificationsData.from(
      overview: await overview,
      settings: await settings,
      quote: await quote,
      chronotype: (await profile)?.chronotype,
    );
  }

  factory NotificationsData.from({
    required HomeOverview overview,
    ReminderSettings? settings,
    Quote? quote,
    Chronotype? chronotype,
  }) {
    final now = overview.now.time;
    final tonight = overview.tonight;
    final studySessions = overview.todayEvents
        .where((event) => event.kind == EventKind.study)
        .toList();
    final finishedSessions = studySessions
        .where((event) => !event.endAt.isAfter(now))
        .toList();
    final notifications = <AppNotification>[
      if (tonight != null && (settings?.bedtimeReminderEnabled ?? true))
        AppNotification(
          category: NotificationCategory.sleep,
          title: 'Đến giờ đi ngủ rồi',
          time: tonight.recommendedSleepAt,
          message: 'Tạm gác việc học, nghỉ ngơi thôi.',
        ),
      if (settings?.deadlineReminderEnabled ?? true)
        for (final todo in overview.upcomingTodos)
          if (todo.status != TodoStatus.done &&
              todo.deadlineAt != null &&
              todo.deadlineAt!.isAfter(now))
            AppNotification(
              category: NotificationCategory.deadline,
              title:
                  '${todo.title} hết hạn sau '
                  '${remainingLabel(todo.deadlineAt!.difference(now))}',
              time: todo.deadlineAt!,
              message: 'Nhớ kiểm tra bài trước khi nộp nhé.',
            ),
      if (studySessions.isNotEmpty)
        AppNotification(
          category: NotificationCategory.study,
          title:
              'Bạn đã hoàn thành ${finishedSessions.length}/'
              '${studySessions.length} phiên ôn',
          time: finishedSessions.isEmpty
              ? studySessions.first.startAt
              : finishedSessions.last.endAt,
          message: finishedSessions.length == studySessions.length
              ? 'Xong hết phiên ôn hôm nay, nghỉ ngơi xứng đáng!'
              : 'Thêm một bước gần hơn tới mục tiêu!',
        ),
      if (quote != null && (settings?.motivationEnabled ?? true))
        AppNotification(
          category: NotificationCategory.motivation,
          title: quote.text,
          time: DateTime(
            overview.date.year,
            overview.date.month,
            overview.date.day,
            _dailyQuoteHour,
          ),
          message: 'Giữ nhịp đều, đừng quên nghỉ ngơi.',
        ),
    ]..sort(_byCategoryThenTime);
    return NotificationsData(
      notifications: notifications,
      chronotype: chronotype,
    );
  }

  static int _byCategoryThenTime(AppNotification a, AppNotification b) {
    final byCategory = a.category.index.compareTo(b.category.index);
    return byCategory != 0 ? byCategory : a.time.compareTo(b.time);
  }

  static String remainingLabel(Duration remaining) {
    if (remaining.inDays >= 1) return '${remaining.inDays} ngày';
    if (remaining.inHours >= 1) return '${remaining.inHours} giờ';
    return '${remaining.inMinutes.clamp(1, 59)} phút';
  }

  static Future<T?> _orNull<T>(Future<T> future) async {
    try {
      return await future;
    } on Exception {
      return null;
    }
  }
}
