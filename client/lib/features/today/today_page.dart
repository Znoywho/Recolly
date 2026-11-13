import 'package:flutter/material.dart';

import '../../core/di/repository_scope.dart';
import '../../core/theme/app_theme.dart';
import 'biorhythm_page.dart';
import 'today_data.dart';
import 'today_format.dart';
import 'widgets/alertness_score_card.dart';
import 'widgets/load_error_card.dart';
import 'widgets/motivation_dialog.dart';
import 'widgets/quote_card.dart';
import 'widgets/sleep_debt_card.dart';
import 'widgets/today_header.dart';
import 'widgets/today_skeleton.dart';
import 'widgets/today_timeline.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key, this.onProfilePressed});

  final VoidCallback? onProfilePressed;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  Future<TodayData>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_data == null) MotivationDialog.precacheTrophy(context);
    _data ??= _load();
  }

  Future<TodayData> _load() => TodayData.load(RepositoryScope.of(context));

  Future<void> _refresh() {
    final next = _load();
    setState(() => _data = next);
    return next.then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<TodayData>(
        future: _data,
        builder: (context, snapshot) {
          final Widget content;
          if (snapshot.connectionState != ConnectionState.done) {
            content = const TodaySkeleton();
          } else if (snapshot.hasError) {
            content = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TodayHeader(
                  greeting: TodayFormat.greeting(DateTime.now()),
                  name: 'bạn',
                  onProfilePressed: widget.onProfilePressed,
                ),
                const SizedBox(height: AppSpacing.lg),
                LoadErrorCard(error: snapshot.error!, onRetry: _refresh),
              ],
            );
          } else {
            content = _TodayContent(
              data: snapshot.requireData,
              onProfilePressed: widget.onProfilePressed,
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
              children: [content],
            ),
          );
        },
      ),
    );
  }
}

class _TodayContent extends StatelessWidget {
  const _TodayContent({required this.data, this.onProfilePressed});

  final TodayData data;
  final VoidCallback? onProfilePressed;

  @override
  Widget build(BuildContext context) {
    final overview = data.overview;
    final displayName = data.user?.displayName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TodayHeader(
          greeting: TodayFormat.greeting(overview.now.time),
          name: displayName == null || displayName.isEmpty
              ? 'bạn'
              : displayName,
          onProfilePressed: onProfilePressed,
        ),
        const SizedBox(height: AppSpacing.lg),
        AlertnessScoreCard(
          snapshot: alertnessSnapshotOf(overview),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const BiorhythmPage()),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SleepDebtCard(
          totalDebtMinutes: overview.sleepDebt7dMinutes,
          nights: data.sleepDebt?.daily ?? const [],
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text('Lịch hôm nay', style: AppTypography.subtitle),
        const SizedBox(height: AppSpacing.md),
        TodayTimeline(entries: TimelineEntry.forDay(overview)),
        const SizedBox(height: AppSpacing.lg),
        QuoteCard(
          text: data.quote?.text ?? QuoteCard.fallbackText,
          onTap: () => MotivationDialog.show(context),
        ),
      ],
    );
  }
}
