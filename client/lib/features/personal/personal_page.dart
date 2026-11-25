import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/di/repository_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_gate.dart';
import '../sync/google_calendar_sheet.dart';
import '../today/widgets/load_error_card.dart';
import 'personal_data.dart';
import 'widgets/profile_card.dart';
import 'widgets/settings_toggle_card.dart';
import 'widgets/sleep_goal_card.dart';

class PersonalPage extends StatefulWidget {
  const PersonalPage({super.key});

  @override
  State<PersonalPage> createState() => _PersonalPageState();
}

class _PersonalPageState extends State<PersonalPage> {
  static const double _maxContentWidth = 520;
  static const double _defaultSleepGoalHours = 8;

  Future<PersonalData>? _data;
  ReminderSettings? _reminderSettings;
  HealthProfile? _healthProfile;
  double? _draftSleepGoal;
  bool _isSavingReminders = false;
  bool _isSigningOut = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<PersonalData> _load() =>
      PersonalData.load(RepositoryScope.of(context)).then((data) {
        if (mounted) {
          setState(() {
            _reminderSettings = data.reminderSettings;
            _healthProfile = data.healthProfile;
            _draftSleepGoal = null;
          });
        }
        return data;
      });

  Future<void> _refresh() {
    final next = _load();
    setState(() => _data = next);
    return next.then((_) {}, onError: (_) {});
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveReminder(String field, bool value) async {
    final current = _reminderSettings;
    if (current == null) return;
    final next = ReminderSettings.fromJson({...current.toJson(), field: value});
    setState(() {
      _reminderSettings = next;
      _isSavingReminders = true;
    });
    try {
      final saved = await RepositoryScope.of(context).reminders
          .saveSettings(next);
      if (mounted) setState(() => _reminderSettings = saved);
    } on ApiException {
      if (!mounted) return;
      setState(() => _reminderSettings = current);
      _showMessage('Chưa lưu được cài đặt nhắc nhở. Thử lại sau nhé.');
    } finally {
      if (mounted) setState(() => _isSavingReminders = false);
    }
  }

  Future<void> _saveSleepGoal(double hours) async {
    final profile = _healthProfile;
    if (profile == null || hours == profile.sleepNeedHours) return;
    try {
      final saved = await RepositoryScope.of(context).sleep.saveHealthProfile(
        HealthProfileInput(
          chronotype: profile.chronotype,
          usualSleepTime: profile.usualSleepTime,
          usualWakeTime: profile.usualWakeTime,
          sleepNeedHours: hours,
          morningPrepMinutes: profile.morningPrepMinutes,
          regularSchedule: profile.regularSchedule,
          screenTrackingEnabled: profile.screenTrackingEnabled,
        ),
      );
      if (!mounted) return;
      setState(() {
        _healthProfile = saved;
        _draftSleepGoal = null;
      });
      _showMessage(
        'Đã đặt mục tiêu ngủ ${SleepGoalCard.hoursLabel(saved.sleepNeedHours)}.',
      );
    } on ApiException {
      if (!mounted) return;
      setState(() => _draftSleepGoal = null);
      _showMessage('Chưa lưu được mục tiêu giấc ngủ. Thử lại sau nhé.');
    }
  }

  Future<void> _openGoogleCalendar() async {
    await GoogleCalendarSheet.show(context);
    if (mounted) await _refresh();
  }

  Future<void> _signOut() async {
    final navigator = Navigator.of(context);
    setState(() => _isSigningOut = true);
    final controller = AuthController(RepositoryScope.of(context));
    await controller.signOut();
    controller.dispose();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final sidePadding = screenWidth > _maxContentWidth + AppSpacing.lg * 2
        ? (screenWidth - _maxContentWidth) / 2
        : AppSpacing.lg;
    return SafeArea(
      child: FutureBuilder<PersonalData>(
        future: _data,
        builder: (context, snapshot) => RefreshIndicator(
          color: AppColors.ink,
          backgroundColor: AppColors.white,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              sidePadding,
              AppSpacing.lg,
              sidePadding,
              AppSpacing.whitespace,
            ),
            children: [
              const Text('Cá nhân', style: AppTypography.title),
              const SizedBox(height: AppSpacing.lg),
              ..._buildBody(snapshot),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody(AsyncSnapshot<PersonalData> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const [
        BrutalCard(
          child: SizedBox(
            height: 220,
            child: Center(child: CircularProgressIndicator(strokeWidth: 3)),
          ),
        ),
      ];
    }
    if (snapshot.hasError) {
      return [LoadErrorCard(error: snapshot.error!, onRetry: _refresh)];
    }
    final data = snapshot.requireData;
    final user = data.user;
    final displayName = user?.displayName;
    final reminders = _reminderSettings;
    final profile = _healthProfile;
    final canEditReminders = reminders != null && !_isSavingReminders;
    return [
      ProfileCard(
        name: displayName == null || displayName.isEmpty ? 'Bạn' : displayName,
        subtitle: user?.email,
      ),
      const SizedBox(height: AppSpacing.md),
      SettingsToggleCard(
        toggles: [
          SettingsToggle(
            label: 'Nhắc đi ngủ',
            value: reminders?.bedtimeReminderEnabled ?? false,
            onChanged: canEditReminders
                ? (value) => _saveReminder('bedtime_reminder_enabled', value)
                : null,
          ),
          SettingsToggle(
            label: 'Nhắc deadline',
            value: reminders?.deadlineReminderEnabled ?? false,
            onChanged: canEditReminders
                ? (value) => _saveReminder('deadline_reminder_enabled', value)
                : null,
          ),
          SettingsToggle(
            label: 'Câu trích dẫn mỗi ngày',
            value: reminders?.motivationEnabled ?? false,
            onChanged: canEditReminders
                ? (value) => _saveReminder('motivation_enabled', value)
                : null,
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      SleepGoalCard(
        hours:
            _draftSleepGoal ??
            profile?.sleepNeedHours ??
            _defaultSleepGoalHours,
        onChanged: profile == null
            ? null
            : (hours) => setState(() => _draftSleepGoal = hours),
        onChangeEnd: profile == null ? null : _saveSleepGoal,
      ),
      const SizedBox(height: AppSpacing.md),
      _GoogleAccountCard(
        isConnected: data.isGoogleConnected,
        onTap: _openGoogleCalendar,
      ),
      const SizedBox(height: AppSpacing.lg),
      BrutalButton(
        label: 'Đăng xuất',
        icon: Icons.logout_rounded,
        leadingIcon: true,
        color: AppColors.coral,
        onPressed: _isSigningOut ? null : _signOut,
      ),
    ];
  }
}

class _GoogleAccountCard extends StatelessWidget {
  const _GoogleAccountCard({required this.isConnected, required this.onTap});

  final bool isConnected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      hint: 'Mở cài đặt Google Calendar',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: BrutalCard(
          child: Row(
            children: [
              const Expanded(
                child: Text('Tài khoản Google', style: AppTypography.body),
              ),
              BrutalBadge(
                label: isConnected ? 'Đã kết nối' : 'Chưa kết nối',
                color: isConnected ? AppColors.green : AppColors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
