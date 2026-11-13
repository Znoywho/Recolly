import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/di/repository_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'today_format.dart';
import 'widgets/energy_chart_card.dart';
import 'widgets/load_error_card.dart';

class BiorhythmPage extends StatefulWidget {
  const BiorhythmPage({super.key});

  @override
  State<BiorhythmPage> createState() => _BiorhythmPageState();
}

class _BiorhythmPageState extends State<BiorhythmPage> {
  Future<Biorhythm>? _biorhythm;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _biorhythm ??= _load();
  }

  Future<Biorhythm> _load() => RepositoryScope.of(context).sleep.getBiorhythm();

  void _retry() => setState(() => _biorhythm = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: BrutalIconButton(
                icon: Icons.arrow_back_rounded,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('Nhịp sinh học\nhôm nay', style: AppTypography.title),
            const SizedBox(height: AppSpacing.lg),
            FutureBuilder<Biorhythm>(
              future: _biorhythm,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const _LoadingCard();
                }
                final error = snapshot.error;
                if (error != null) {
                  return LoadErrorCard(error: error, onRetry: _retry);
                }
                return _BiorhythmContent(biorhythm: snapshot.requireData);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BiorhythmContent extends StatelessWidget {
  const _BiorhythmContent({required this.biorhythm});

  static const int _eveningStartHour = 19;

  final Biorhythm biorhythm;

  List<Widget> _tips() {
    final peak = biorhythm.peakWindows.firstOrNull;
    final daytimeLow = biorhythm.lowWindows
        .where((w) => w.start.hour < _eveningStartHour)
        .firstOrNull;
    final eveningLow = biorhythm.lowWindows
        .where((w) => w.start.hour >= _eveningStartHour)
        .firstOrNull;
    return [
      if (peak != null)
        _RhythmTipCard(
          icon: Icons.menu_book_outlined,
          color: AppColors.green,
          text:
              'Nên ôn bài khó lúc ${TodayFormat.window(peak.start, peak.end)}',
        ),
      if (daytimeLow != null) ...[
        _RhythmTipCard(
          icon: Icons.bedtime_outlined,
          color: AppColors.coral,
          text:
              'Tránh học lúc ${TodayFormat.clock(daytimeLow.start)}, bạn dễ buồn ngủ',
        ),
        _RhythmTipCard(
          icon: Icons.coffee_outlined,
          color: AppColors.teal,
          text: 'Nên nghỉ ngơi lúc ${TodayFormat.clock(daytimeLow.start)}',
        ),
      ],
      if (eveningLow != null) ...[
        _RhythmTipCard(
          icon: Icons.bedtime_outlined,
          color: AppColors.coral,
          text:
              'Bạn buồn ngủ từ ${TodayFormat.clock(eveningLow.start)}, đừng để bài khó tới tối',
        ),
        _RhythmTipCard(
          icon: Icons.nightlight_outlined,
          color: AppColors.teal,
          text:
              'Nên chuẩn bị đi ngủ lúc ${TodayFormat.clock(eveningLow.start)}',
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tips = _tips();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EnergyChartCard(biorhythm: biorhythm),
        const SizedBox(height: AppSpacing.lg),
        const Text('Học theo nhịp của bạn', style: AppTypography.subtitle),
        const SizedBox(height: AppSpacing.md),
        if (tips.isEmpty)
          const BrutalCard(
            borderStyle: BrutalBorderStyle.dashed,
            hasShadow: false,
            color: AppColors.cream,
            child: Text(
              'Chưa đủ dữ liệu để gợi ý. Ghi giấc ngủ vài ngày để Recolly hiểu nhịp của bạn.',
              style: AppTypography.body,
            ),
          )
        else
          for (final (index, tip) in tips.indexed) ...[
            if (index > 0) const SizedBox(height: AppSpacing.md),
            tip,
          ],
      ],
    );
  }
}

class _RhythmTipCard extends StatelessWidget {
  const _RhythmTipCard({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return BrutalCard(
      color: color,
      child: Row(
        children: [
          Icon(icon, size: 26),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: AppTypography.body)),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const BrutalCard(
      child: SizedBox(
        height: 260,
        child: Center(child: CircularProgressIndicator(strokeWidth: 3)),
      ),
    );
  }
}
