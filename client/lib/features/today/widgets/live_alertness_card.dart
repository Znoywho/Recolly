import 'package:client/data/data.dart';
import 'package:flutter/widgets.dart';

import '../../../core/di/repository_scope.dart';
import 'alertness_score_card.dart';

class LiveAlertnessCard extends StatefulWidget {
  const LiveAlertnessCard({super.key});

  @override
  State<LiveAlertnessCard> createState() => _LiveAlertnessCardState();
}

class _LiveAlertnessCardState extends State<LiveAlertnessCard> {
  Future<HomeOverview>? _overview;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _overview ??= _loadOverview();
  }

  Future<HomeOverview> _loadOverview() =>
      RepositoryScope.of(context).home.getOverview();

  void _retry() => setState(() => _overview = _loadOverview());

  static AlertnessSnapshot _snapshotOf(AsyncSnapshot<HomeOverview> result) {
    if (result.connectionState != ConnectionState.done) {
      return const AlertnessLoading();
    }
    final error = result.error;
    if (error != null) return AlertnessFailed(_describeError(error));
    final now = result.requireData.now;
    final score = now.alertnessScore;
    if (score == null) return const AlertnessUnavailable();
    return AlertnessReady(
      score: score,
      predictedKss: now.kssPred,
      isAsleep: now.asleep,
    );
  }

  static String _describeError(Object error) => switch (error) {
    ApiException(isNetworkError: true) =>
      'Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.',
    ApiException(isNotFound: true) =>
      'Chưa có hồ sơ giấc ngủ, hãy hoàn tất onboarding trước.',
    _ => 'Có lỗi khi tải dữ liệu. Thử lại sau nhé.',
  };

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HomeOverview>(
      future: _overview,
      builder: (context, result) =>
          AlertnessScoreCard(snapshot: _snapshotOf(result), onRetry: _retry),
    );
  }
}
