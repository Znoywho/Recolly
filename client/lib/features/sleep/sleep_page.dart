import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/di/repository_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../today/today_format.dart';
import '../today/widgets/load_error_card.dart';
import 'sleep_data.dart';
import 'widgets/bedtime_card.dart';
import 'widgets/sleep_debt_hero_card.dart';
import 'widgets/sleep_empty_card.dart';
import 'widgets/sleep_tip_card.dart';
import 'widgets/weekly_sleep_card.dart';

class SleepPage extends StatefulWidget {
  const SleepPage({super.key});

  @override
  State<SleepPage> createState() => _SleepPageState();
}

class _SleepPageState extends State<SleepPage> {
  static const int _debtTipThresholdMinutes = 60;
  static const int _debtTipEarlierMinutes = 30;

  Future<SleepData>? _data;
  ReminderSettings? _savedReminderSettings;
  bool _isSavingReminder = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<SleepData> _load() => SleepData.load(RepositoryScope.of(context));

  Future<void> _refresh() {
    final next = _load();
    setState(() {
      _data = next;
      _savedReminderSettings = null;
    });
    return next.then((_) {}, onError: (_) {});
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onReminderPressed(SleepData data) async {
    final settings = data.reminderSettings;
    if (settings != null && settings.bedtimeReminderEnabled) {
      _showMessage(
        'Nhắc đi ngủ đã bật, Recolly sẽ nhắc trước '
        '${settings.bedtimeReminderMinutesBefore} phút.',
      );
      return;
    }
    final repositories = RepositoryScope.of(context);
    setState(() => _isSavingReminder = true);
    try {
      final current = settings ?? await repositories.reminders.getSettings();
      final saved = await repositories.reminders.saveSettings(
        ReminderSettings.fromJson({
          ...current.toJson(),
          'bedtime_reminder_enabled': true,
        }),
      );
      if (!mounted) return;
      setState(() => _savedReminderSettings = saved);
      _showMessage(
        'Đã bật nhắc đi ngủ trước ${saved.bedtimeReminderMinutesBefore} phút.',
      );
    } on ApiException {
      if (mounted) _showMessage('Chưa bật được nhắc nhở. Thử lại sau nhé.');
    } finally {
      if (mounted) setState(() => _isSavingReminder = false);
    }
  }

  static String _minutesLabel(int minutes) =>
      minutes < 60 ? '$minutes phút' : TodayFormat.duration(minutes);

  String? _tipFor(SleepData data) {
    final earlierMinutes = data.earlierBedtimeMinutes;
    final requiredWakeAt = data.tonight?.requiredWakeAt;
    if (earlierMinutes != null && requiredWakeAt != null) {
      return 'Ngày mai bạn cần dậy lúc ${TodayFormat.clock(requiredWakeAt)}, '
          'hãy ngủ sớm hơn ${_minutesLabel(earlierMinutes)}.';
    }
    final debt = data.sleepDebt.totalDebtMinutes;
    if (debt >= _debtTipThresholdMinutes) {
      return 'Bạn đang nợ ${TodayFormat.duration(debt)} giấc ngủ, '
          'hãy ngủ sớm hơn $_debtTipEarlierMinutes phút mỗi tối để trả dần.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<SleepData>(
        future: _data,
        builder: (context, snapshot) {
          final Widget content;
          if (snapshot.connectionState != ConnectionState.done) {
            content = const _SleepLoadingCard();
          } else if (snapshot.hasError) {
            content = LoadErrorCard(error: snapshot.error!, onRetry: _refresh);
          } else {
            final savedSettings = _savedReminderSettings;
            content = _buildContent(
              savedSettings == null
                  ? snapshot.requireData
                  : snapshot.requireData.withReminderSettings(savedSettings),
            );
          }
          return RefreshIndicator(
            color: AppColors.ink,
            backgroundColor: AppColors.white,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
              ),
              children: [
                const Text('Giấc ngủ', style: AppTypography.title),
                const SizedBox(height: AppSpacing.lg),
                content,
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(SleepData data) {
    if (!data.hasSleepLogs) {
      return SleepEmptyCard(
        onLogSleep: () =>
            _showMessage('Màn ghi giấc ngủ sẽ có trong bản tiếp theo.'),
      );
    }
    final tonight = data.tonight;
    final tip = _tipFor(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SleepDebtHeroCard(totalDebtMinutes: data.sleepDebt.totalDebtMinutes),
        const SizedBox(height: AppSpacing.md),
        WeeklySleepCard(
          nights: data.sleepDebt.daily,
          goalMinutes: data.goalMinutes,
        ),
        if (tonight != null) ...[
          const SizedBox(height: AppSpacing.md),
          BedtimeCard(
            recommendedSleepAt: tonight.recommendedSleepAt,
            isReminderOn:
                data.reminderSettings?.bedtimeReminderEnabled ?? false,
            isSaving: _isSavingReminder,
            onReminderPressed: () => _onReminderPressed(data),
          ),
        ],
        if (tip != null) ...[
          const SizedBox(height: AppSpacing.md),
          SleepTipCard(message: tip),
        ],
      ],
    );
  }
}

class _SleepLoadingCard extends StatelessWidget {
  const _SleepLoadingCard();

  @override
  Widget build(BuildContext context) {
    return const BrutalCard(
      child: SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator(strokeWidth: 3)),
      ),
    );
  }
}
