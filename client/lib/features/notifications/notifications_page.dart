import 'package:flutter/material.dart';

import '../../core/di/repository_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../today/widgets/load_error_card.dart';
import 'notifications_data.dart';
import 'widgets/notification_card.dart';

enum NotificationFilter {
  all('Tất cả', {}),
  sleep('Giấc ngủ', {NotificationCategory.sleep}),
  deadline('Deadline', {NotificationCategory.deadline}),
  study('Học tập', {
    NotificationCategory.study,
    NotificationCategory.motivation,
  });

  const NotificationFilter(this.label, this.categories);

  final String label;
  final Set<NotificationCategory> categories;

  bool matches(AppNotification notification) =>
      categories.isEmpty || categories.contains(notification.category);
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static const double _maxContentWidth = 520;

  Future<NotificationsData>? _data;
  NotificationFilter _filter = NotificationFilter.all;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<NotificationsData> _load() =>
      NotificationsData.load(RepositoryScope.of(context));

  Future<void> _refresh() {
    final next = _load();
    setState(() => _data = next);
    return next.then((_) {}, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final sidePadding = screenWidth > _maxContentWidth + AppSpacing.lg * 2
        ? (screenWidth - _maxContentWidth) / 2
        : AppSpacing.lg;
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: FutureBuilder<NotificationsData>(
          future: _data,
          builder: (context, snapshot) => RefreshIndicator(
            color: AppColors.ink,
            backgroundColor: AppColors.white,
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                sidePadding,
                AppSpacing.md,
                sidePadding,
                AppSpacing.lg,
              ),
              children: [
                Row(
                  children: [
                    BrutalIconButton(
                      icon: Icons.arrow_back_rounded,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    const Expanded(
                      child: Text('Thông báo', style: AppTypography.title),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _FilterBar(
                  selected: _filter,
                  onSelected: (filter) => setState(() => _filter = filter),
                ),
                const SizedBox(height: AppSpacing.lg),
                ..._buildBody(snapshot),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody(AsyncSnapshot<NotificationsData> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const [
        BrutalCard(
          child: SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator(strokeWidth: 3)),
          ),
        ),
      ];
    }
    if (snapshot.hasError) {
      return [LoadErrorCard(error: snapshot.error!, onRetry: _refresh)];
    }
    final notifications = snapshot.requireData.notifications
        .where(_filter.matches)
        .toList();
    return [
      Row(
        children: [
          const Expanded(child: Text('Hôm nay', style: AppTypography.label)),
          Text('${notifications.length} thông báo', style: AppTypography.label),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      if (notifications.isEmpty)
        const BrutalCard(
          borderStyle: BrutalBorderStyle.dashed,
          hasShadow: false,
          child: Text(
            'Chưa có thông báo nào ở mục này.',
            textAlign: TextAlign.center,
            style: AppTypography.body,
          ),
        )
      else
        for (final notification in notifications) ...[
          NotificationCard(
            notification: notification,
            chronotype: snapshot.requireData.chronotype,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
    ];
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});

  final NotificationFilter selected;
  final ValueChanged<NotificationFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final filter in NotificationFilter.values) ...[
            BrutalButton(
              label: filter.label,
              expanded: false,
              color: filter == selected ? AppColors.teal : AppColors.white,
              onPressed: () => onSelected(filter),
            ),
            if (filter != NotificationFilter.values.last)
              const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}
