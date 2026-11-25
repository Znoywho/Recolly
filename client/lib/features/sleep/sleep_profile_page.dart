import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/di/repository_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

/// Onboarding sleep questionnaire (R55).
///
/// Questions follow the µMCTQ (Ghotbi et al. 2020, J Biol Rhythms 35:98),
/// the 6-item short form of the Munich ChronoType Questionnaire: school
/// days per week, sleep onset and wake-up on school days and on free days,
/// and whether an alarm is used on free days. Onset means actually falling
/// asleep, not going to bed. Two extra questions screen for fragmented sleep
/// (≥ 3 nights a week for ≥ 3 months, the insomnia frequency/duration rule
/// of DSM-5 / ICSD-3). The server scores it (C1), the user sees their animal,
/// then the answers are saved (H2).
class SleepProfilePage extends StatefulWidget {
  const SleepProfilePage({super.key, this.onCompleted});

  static const double maxContentWidth = 520;
  static const int timeStepMinutes = 15;

  final ValueChanged<HealthProfile>? onCompleted;

  @override
  State<SleepProfilePage> createState() => _SleepProfilePageState();
}

enum _Step { schoolDays, freeDays, sleepQuality, result }

class _SleepProfilePageState extends State<SleepProfilePage> {
  _Step _step = _Step.schoolDays;
  int _workDays = 5;
  ClockTime _onsetWork = const ClockTime(23, 30);
  ClockTime _endWork = const ClockTime(6, 30);
  ClockTime _onsetFree = const ClockTime(0, 30);
  ClockTime _endFree = const ClockTime(9, 0);
  bool _alarmOnFreeDays = false;
  NightsPerWeek _slowOnset = NightsPerWeek.none;
  NightsPerWeek _nightWaking = NightsPerWeek.none;
  ProblemDuration? _duration;
  ChronotypeAssessment? _result;

  bool _hasUserEdited = false;
  bool _isBusy = false;
  bool _didRequestProfile = false;

  bool get _needsDuration =>
      _slowOnset == NightsPerWeek.threeOrMore ||
      _nightWaking == NightsPerWeek.threeOrMore;

  MctqAnswers get _mctq => MctqAnswers(
    sleepOnsetWork: _onsetWork,
    sleepEndWork: _endWork,
    sleepOnsetFree: _onsetFree,
    sleepEndFree: _endFree,
    workDays: _workDays,
    alarmOnFreeDays: _alarmOnFreeDays,
  );

  SleepQualityAnswers get _sleepQuality => SleepQualityAnswers(
    slowOnsetNights: _slowOnset,
    nightWakingNights: _nightWaking,
    duration: _needsDuration ? _duration : null,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didRequestProfile) return;
    _didRequestProfile = true;
    _prefillFromSavedProfile();
  }

  // Re-doing the quiz from Personal starts from the previous answers.
  Future<void> _prefillFromSavedProfile() async {
    try {
      final profile = await RepositoryScope.of(context).sleep
          .getHealthProfile();
      if (!mounted || profile == null || _hasUserEdited) return;
      setState(() {
        final mctq = profile.mctq;
        _onsetWork = mctq?.sleepOnsetWork ?? profile.usualSleepTime;
        _endWork = mctq?.sleepEndWork ?? profile.usualWakeTime;
        if (mctq != null) {
          _onsetFree = mctq.sleepOnsetFree;
          _endFree = mctq.sleepEndFree;
          _alarmOnFreeDays = mctq.alarmOnFreeDays;
          _workDays = (mctq.workDays ?? _workDays).clamp(1, 6);
        }
        final quality = profile.sleepQuality;
        if (quality != null) {
          _slowOnset = quality.slowOnsetNights;
          _nightWaking = quality.nightWakingNights;
          _duration = quality.duration;
        }
      });
    } on Exception {
      return;
    }
  }

  // Wraps every answer change so a late prefill never overwrites it.
  void _edit(VoidCallback change) => setState(() {
    _hasUserEdited = true;
    change();
  });

  void _back() {
    if (_step == _Step.schoolDays) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _step = _Step.values[_step.index - 1]);
    }
  }

  Future<void> _next() async {
    if (_step == _Step.sleepQuality) return _assess();
    if (_step == _Step.result) return _save();
    setState(() => _step = _Step.values[_step.index + 1]);
  }

  // C1: score the answers on the server, then show the animal.
  Future<void> _assess() async {
    if (_needsDuration && _duration == null) {
      _showError('Chọn xem tình trạng này kéo dài bao lâu nhé.');
      return;
    }
    await _busy(() async {
      final result = await RepositoryScope.of(context).sleep.assessChronotype(
        ChronotypeAssessmentRequest(
          mctq: _mctq,
          regularSchedule: true,
          sleepQuality: _sleepQuality,
        ),
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _step = _Step.result;
      });
    }, 'Chưa tính được nhịp sinh học. Thử lại sau nhé.');
  }

  // H2: save the answers; the server recomputes the chronotype from them.
  Future<void> _save() async {
    final result = _result!;
    await _busy(() async {
      final saved = await RepositoryScope.of(context).sleep.saveHealthProfile(
        HealthProfileInput(
          chronotype: result.chronotype,
          usualSleepTime: _onsetWork,
          usualWakeTime: _endWork,
          mctq: _mctq,
          regularSchedule: true,
          sleepQuality: _sleepQuality,
        ),
      );
      if (!mounted) return;
      final onCompleted = widget.onCompleted;
      if (onCompleted != null) {
        onCompleted(saved);
      } else {
        Navigator.of(context).maybePop();
      }
    }, 'Chưa lưu được hồ sơ giấc ngủ. Thử lại sau nhé.');
  }

  Future<void> _busy(Future<void> Function() work, String errorText) async {
    setState(() => _isBusy = true);
    try {
      await work();
    } on ApiException {
      if (mounted) _showError(errorText);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showError(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
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
                      onPressed: _isBusy ? null : _back,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: BrutalProgressBar(
                        value: (_step.index + 1) / _Step.values.length,
                        fillColor: AppColors.teal,
                        height: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                ...switch (_step) {
                  _Step.schoolDays => _buildSchoolDays(),
                  _Step.freeDays => _buildFreeDays(),
                  _Step.sleepQuality => _buildSleepQuality(),
                  _Step.result => _buildResult(_result!),
                },
                const SizedBox(height: AppSpacing.lg),
                BrutalButton(
                  label: switch (_step) {
                    _Step.sleepQuality => 'Xem con vật của bạn',
                    _Step.result => 'Lưu và tiếp tục',
                    _ => 'Tiếp tục',
                  },
                  icon: Icons.arrow_forward_rounded,
                  leadingIcon: true,
                  onPressed: _isBusy ? null : _next,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildSchoolDays() => [
    const Text('Ngày đi học', style: AppTypography.title),
    const SizedBox(height: AppSpacing.xs),
    const Text(
      'Nghĩ về một tuần học bình thường gần đây nhé.',
      style: AppTypography.body,
    ),
    const SizedBox(height: AppSpacing.lg),
    const Text('Mỗi tuần bạn đi học mấy ngày?', style: AppTypography.label),
    const SizedBox(height: AppSpacing.xs),
    _ChoiceRow<int>(
      values: const [1, 2, 3, 4, 5, 6],
      selected: _workDays,
      labelOf: (days) => '$days',
      semanticsOf: (days) => '$days ngày đi học',
      onSelected: (days) => _edit(() => _workDays = days),
    ),
    const SizedBox(height: AppSpacing.md),
    _TimeCard(
      label: 'Ngủ thiếp đi lúc',
      hint: 'Lúc thật sự ngủ, không phải lúc lên giường',
      icon: Icons.bedtime_outlined,
      time: _onsetWork,
      onChanged: (time) => _edit(() => _onsetWork = time),
    ),
    const SizedBox(height: AppSpacing.md),
    _TimeCard(
      label: 'Thức dậy lúc',
      icon: Icons.wb_sunny_outlined,
      time: _endWork,
      onChanged: (time) => _edit(() => _endWork = time),
    ),
  ];

  List<Widget> _buildFreeDays() => [
    const Text('Ngày nghỉ', style: AppTypography.title),
    const SizedBox(height: AppSpacing.xs),
    const Text(
      'Ngày không có lịch học, không phải dậy sớm.',
      style: AppTypography.body,
    ),
    const SizedBox(height: AppSpacing.lg),
    _TimeCard(
      label: 'Ngủ thiếp đi lúc',
      hint: 'Lúc thật sự ngủ, không phải lúc lên giường',
      icon: Icons.bedtime_outlined,
      time: _onsetFree,
      onChanged: (time) => _edit(() => _onsetFree = time),
    ),
    const SizedBox(height: AppSpacing.md),
    _TimeCard(
      label: 'Thức dậy lúc',
      icon: Icons.wb_sunny_outlined,
      time: _endFree,
      onChanged: (time) => _edit(() => _endFree = time),
    ),
    const SizedBox(height: AppSpacing.md),
    BrutalCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      // Own Material so the tile's ink is not hidden by the card colour.
      child: Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Ngày nghỉ mình vẫn đặt báo thức',
            style: AppTypography.body,
          ),
          value: _alarmOnFreeDays,
          onChanged: (value) => _edit(() => _alarmOnFreeDays = value),
        ),
      ),
    ),
  ];

  List<Widget> _buildSleepQuality() => [
    const Text('Chất lượng giấc ngủ', style: AppTypography.title),
    const SizedBox(height: AppSpacing.xs),
    const Text('Tính trong tháng gần đây.', style: AppTypography.body),
    const SizedBox(height: AppSpacing.lg),
    const Text(
      'Mấy đêm mỗi tuần bạn mất hơn 30 phút mới ngủ được?',
      style: AppTypography.label,
    ),
    const SizedBox(height: AppSpacing.xs),
    _ChoiceRow<NightsPerWeek>(
      values: NightsPerWeek.values,
      selected: _slowOnset,
      labelOf: _nightsLabel,
      semanticsOf: (n) => 'Khó ngủ ${_nightsLabel(n)}',
      onSelected: (n) => _edit(() => _slowOnset = n),
    ),
    const SizedBox(height: AppSpacing.lg),
    const Text(
      'Mấy đêm mỗi tuần bạn tỉnh giữa đêm rồi không ngủ lại được?',
      style: AppTypography.label,
    ),
    const SizedBox(height: AppSpacing.xs),
    _ChoiceRow<NightsPerWeek>(
      values: NightsPerWeek.values,
      selected: _nightWaking,
      labelOf: _nightsLabel,
      semanticsOf: (n) => 'Tỉnh giữa đêm ${_nightsLabel(n)}',
      onSelected: (n) => _edit(() => _nightWaking = n),
    ),
    if (_needsDuration) ...[
      const SizedBox(height: AppSpacing.lg),
      const Text(
        'Tình trạng này kéo dài bao lâu rồi?',
        style: AppTypography.label,
      ),
      const SizedBox(height: AppSpacing.xs),
      _ChoiceRow<ProblemDuration>(
        values: ProblemDuration.values,
        selected: _duration,
        labelOf: (d) => switch (d) {
          ProblemDuration.underOneMonth => '< 1 tháng',
          ProblemDuration.oneToThreeMonths => '1–3 tháng',
          ProblemDuration.overThreeMonths => '> 3 tháng',
        },
        semanticsOf: (d) => 'Kéo dài ${d.value}',
        onSelected: (d) => _edit(() => _duration = d),
      ),
    ],
  ];

  static String _nightsLabel(NightsPerWeek n) => switch (n) {
    NightsPerWeek.none => '0 đêm',
    NightsPerWeek.oneToTwo => '1–2 đêm',
    NightsPerWeek.threeOrMore => '3+ đêm',
  };

  List<Widget> _buildResult(ChronotypeAssessment result) {
    final animal = MascotAnimal.of(result.chronotype);
    final shortfall = result.sleepShortfallHours;
    return [
      BrutalCard(
        color: result.chronotype.badgeColor,
        child: Column(
          children: [
            AnimalMascot(animal: animal, size: 140),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Bạn là ${animal.displayName}!',
              textAlign: TextAlign.center,
              style: AppTypography.title.copyWith(
                color: result.chronotype.badgeForegroundColor,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _animalTagline(result.chronotype),
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: result.chronotype.badgeForegroundColor,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      BrutalCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nhịp tự nhiên của bạn', style: AppTypography.label),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Ngủ ${result.naturalSleepTime} – dậy ${result.naturalWakeTime}',
              style: AppTypography.subtitle,
            ),
            if (shortfall != null && shortfall > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Trung bình bạn đang thiếu khoảng '
                '${shortfall.toStringAsFixed(1)} giờ ngủ mỗi đêm.',
                style: AppTypography.body,
              ),
            ],
          ],
        ),
      ),
      if (result.sleepConcern != SleepConcern.none) ...[
        const SizedBox(height: AppSpacing.md),
        BrutalCard(
          color: AppColors.teal,
          child: Row(
            children: [
              const AnimalMascot(animal: MascotAnimal.dolphin, size: 64),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  result.sleepConcern == SleepConcern.dolphin
                      ? 'Bạn ngủ chập chờn như cá heo. Nếu kéo dài, '
                            'nên gặp bác sĩ hoặc phòng y tế trường nhé.'
                      : 'Giấc ngủ của bạn hơi chập chờn, Recolly sẽ '
                            'để ý giúp bạn.',
                  style: AppTypography.body,
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  static String _animalTagline(Chronotype chronotype) => switch (chronotype) {
    Chronotype.lion => 'Dậy sớm, tỉnh táo nhất vào buổi sáng.',
    Chronotype.bear => 'Theo nhịp mặt trời, năng lượng cao giữa ngày.',
    Chronotype.wolf => 'Cú đêm, đầu óc sáng nhất vào chiều tối.',
  };
}

/// One row of brutalist pill choices; exactly one value is selected.
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.semanticsOf,
    required this.onSelected,
  });

  final List<T> values;
  final T? selected;
  final String Function(T value) labelOf;
  final String Function(T value) semanticsOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final value in values)
          Semantics(
            button: true,
            selected: value == selected,
            label: semanticsOf(value),
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelected(value),
              child: Container(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: AppTheme.brutalBox(
                  color: value == selected ? AppColors.green : AppColors.white,
                  borderRadius: AppRadii.pillAll,
                  hasShadow: value == selected,
                ),
                child: Text(
                  labelOf(value),
                  textAlign: TextAlign.center,
                  style: AppTypography.body,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A clock time that moves in 15-minute steps and wraps past midnight.
class _TimeCard extends StatelessWidget {
  const _TimeCard({
    required this.label,
    required this.icon,
    required this.time,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? hint;
  final IconData icon;
  final ClockTime time;
  final ValueChanged<ClockTime> onChanged;

  // Adds [minutes] to [time], wrapping around 24 h.
  void _shift(int minutes) {
    final total = (time.minutesSinceMidnight + minutes) % (24 * 60);
    onChanged(ClockTime(total ~/ 60, total % 60));
  }

  @override
  Widget build(BuildContext context) {
    const step = SleepProfilePage.timeStepMinutes;
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
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text(label, style: AppTypography.label)),
            ],
          ),
          if (hint != null) Text(hint!, style: AppTypography.caption),
          Row(
            children: [
              IconButton(
                tooltip: '$label: sớm hơn $step phút',
                onPressed: () => _shift(-step),
                icon: const Icon(Icons.chevron_left_rounded, size: 30),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    time.toJson(),
                    semanticsLabel: '$label ${time.toJson()}',
                    style: AppTypography.display.copyWith(fontSize: 44),
                  ),
                ),
              ),
              IconButton(
                tooltip: '$label: muộn hơn $step phút',
                onPressed: () => _shift(step),
                icon: const Icon(Icons.chevron_right_rounded, size: 30),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
