import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/di/repository_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

enum UsualBedtime {
  beforeEleven('Trước 23h', ClockTime(22, 30), Chronotype.lion),
  elevenToOne('23h đến 1h', ClockTime(0, 0), Chronotype.bear),
  afterOne('Sau 1h', ClockTime(1, 30), Chronotype.wolf);

  const UsualBedtime(this.label, this.typicalSleepTime, this.chronotype);

  final String label;
  final ClockTime typicalSleepTime;
  final Chronotype chronotype;

  static UsualBedtime fromSleepTime(ClockTime time) {
    final minutesAfterNoon = (time.hour * 60 + time.minute + 12 * 60) % 1440;
    if (minutesAfterNoon < 11 * 60) return UsualBedtime.beforeEleven;
    if (minutesAfterNoon <= 13 * 60) return UsualBedtime.elevenToOne;
    return UsualBedtime.afterOne;
  }
}

class SleepProfilePage extends StatefulWidget {
  const SleepProfilePage({super.key, this.progress = 2 / 3, this.onCompleted});

  static const double maxContentWidth = 520;
  static const int wakeTimeStepMinutes = 15;
  static const ClockTime defaultWakeTime = ClockTime(6, 30);

  final double progress;
  final ValueChanged<HealthProfile>? onCompleted;

  @override
  State<SleepProfilePage> createState() => _SleepProfilePageState();
}

class _SleepProfilePageState extends State<SleepProfilePage> {
  UsualBedtime _bedtime = UsualBedtime.elevenToOne;
  ClockTime _wakeTime = SleepProfilePage.defaultWakeTime;
  bool _hasUserEdited = false;
  bool _isSaving = false;
  bool _didRequestProfile = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didRequestProfile) return;
    _didRequestProfile = true;
    _prefillFromSavedProfile();
  }

  Future<void> _prefillFromSavedProfile() async {
    try {
      final profile = await RepositoryScope.of(context).sleep
          .getHealthProfile();
      if (!mounted || profile == null || _hasUserEdited) return;
      setState(() {
        _bedtime = UsualBedtime.fromSleepTime(profile.usualSleepTime);
        _wakeTime = profile.usualWakeTime;
      });
    } on Exception {
      return;
    }
  }

  void _selectBedtime(UsualBedtime bedtime) => setState(() {
    _hasUserEdited = true;
    _bedtime = bedtime;
  });

  void _shiftWakeTime(int minutes) => setState(() {
    _hasUserEdited = true;
    final total =
        (_wakeTime.hour * 60 + _wakeTime.minute + minutes) % (24 * 60);
    _wakeTime = ClockTime(total ~/ 60, total % 60);
  });

  String _clockLabel(ClockTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final repositories = RepositoryScope.of(context);
    setState(() => _isSaving = true);
    try {
      final saved = await repositories.sleep.saveHealthProfile(
        HealthProfileInput(
          chronotype: _bedtime.chronotype,
          usualSleepTime: _bedtime.typicalSleepTime,
          usualWakeTime: _wakeTime,
        ),
      );
      if (!mounted) return;
      final onCompleted = widget.onCompleted;
      if (onCompleted != null) {
        onCompleted(saved);
      } else {
        Navigator.of(context).maybePop();
      }
    } on ApiException {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Chưa lưu được hồ sơ giấc ngủ. Thử lại sau nhé.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final sidePadding =
                constraints.maxWidth >
                    SleepProfilePage.maxContentWidth + AppSpacing.lg * 2
                ? (constraints.maxWidth - SleepProfilePage.maxContentWidth) / 2
                : AppSpacing.lg;
            return ListView(
              padding: EdgeInsets.fromLTRB(
                sidePadding,
                AppSpacing.md,
                sidePadding,
                AppSpacing.xl,
              ),
              children: [
                Row(
                  children: [
                    BrutalIconButton(
                      icon: Icons.arrow_back_rounded,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: BrutalProgressBar(
                        value: widget.progress,
                        fillColor: AppColors.teal,
                        height: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'Bạn thường đi ngủ lúc mấy giờ?',
                  style: AppTypography.title,
                ),
                const SizedBox(height: AppSpacing.lg),
                for (final bedtime in UsualBedtime.values) ...[
                  _buildBedtimeOption(bedtime),
                  const SizedBox(height: AppSpacing.md),
                ],
                _buildWakeTimeCard(),
                const SizedBox(height: AppSpacing.lg),
                BrutalButton(
                  label: 'Tiếp tục',
                  icon: Icons.arrow_forward_rounded,
                  leadingIcon: true,
                  onPressed: _isSaving ? null : _save,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBedtimeOption(UsualBedtime bedtime) {
    final isSelected = bedtime == _bedtime;
    return Semantics(
      button: true,
      selected: isSelected,
      label: bedtime.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectBedtime(bedtime),
        child: BrutalCard(
          color: isSelected ? AppColors.green : AppColors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md + 2,
          ),
          child: Row(
            children: [
              Expanded(child: Text(bedtime.label, style: AppTypography.body)),
              Container(
                width: 28,
                height: 28,
                decoration: AppTheme.brutalBox(
                  color: isSelected ? AppColors.ink : AppColors.cream,
                  borderRadius: AppRadii.pillAll,
                  hasShadow: false,
                ),
                child: isSelected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: AppColors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWakeTimeCard() {
    return BrutalCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.wb_sunny_outlined, size: 20),
              SizedBox(width: AppSpacing.xs),
              Text('Giờ thức dậy', style: AppTypography.label),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              IconButton(
                tooltip: 'Sớm hơn ${SleepProfilePage.wakeTimeStepMinutes} phút',
                onPressed: () =>
                    _shiftWakeTime(-SleepProfilePage.wakeTimeStepMinutes),
                icon: const Icon(Icons.chevron_left_rounded, size: 30),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _clockLabel(_wakeTime),
                    semanticsLabel: 'Giờ thức dậy ${_clockLabel(_wakeTime)}',
                    style: AppTypography.display.copyWith(fontSize: 44),
                  ),
                ),
              ),
              IconButton(
                tooltip:
                    'Muộn hơn ${SleepProfilePage.wakeTimeStepMinutes} phút',
                onPressed: () =>
                    _shiftWakeTime(SleepProfilePage.wakeTimeStepMinutes),
                icon: const Icon(Icons.chevron_right_rounded, size: 30),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
