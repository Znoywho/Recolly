import 'package:client/core/di/repository_scope.dart';
import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

// R33: pick events and push them to Google Calendar.
// Figma: "Google Calendar – Chọn sự kiện" 317:33, "– Kết quả đồng bộ" 317:177,
// "– Đồng bộ thành công" 328:33. Pops true when something was pushed.

const lightSlate = Color(0xFFC7CCD9);

class CalendarPushPage extends StatefulWidget {
  const CalendarPushPage({super.key, this.email});

  final String? email;

  @override
  State<CalendarPushPage> createState() => _CalendarPushPageState();
}

class _CalendarPushPageState extends State<CalendarPushPage> {
  List<CalendarEvent> events = [];
  Set<String> picked = {};
  bool loading = true;
  bool busy = false;
  String? loadError;

  // Set after a sync
  SyncResult? result;
  DateTime? syncedAt;
  List<CalendarEvent> failed = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading && events.isEmpty && loadError == null) load();
  }

  // Unsynced events from today to 4 weeks ahead, one card per event id
  Future<List<CalendarEvent>> pendingEvents() async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final list = await RepositoryScope.of(context).events.listEvents(
      from: from,
      to: from.add(const Duration(days: 28)),
    );
    final seen = <String>{};
    return list
        .where((e) => e.syncStatus != SyncStatus.synced)
        .where((e) => e.syncStatus != SyncStatus.conflict)
        .where((e) => seen.add(e.id))
        .toList();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      final list = await pendingEvents();
      if (!mounted) return;
      setState(() {
        events = list;
        picked = list.map((e) => e.id).toSet();
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        loadError = 'Không tải được lịch, thử lại nhé.';
      });
    }
  }

  Future<void> push(List<String> ids) async {
    setState(() => busy = true);
    try {
      final repos = RepositoryScope.of(context);
      final r = await repos.calendarSync.sync(eventIds: ids);
      // Find which of the sent events are still not pushed
      var still = <CalendarEvent>[];
      if (r.failed > 0) {
        final left = await pendingEvents();
        still = left.where((e) => ids.contains(e.id)).toList();
      }
      if (!mounted) return;
      setState(() {
        result = r;
        syncedAt = DateTime.now();
        failed = still;
        busy = false;
      });
      if (r.failed == 0) showDone();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => busy = false);
      showSnack(errorText(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => busy = false);
      showSnack('Không đồng bộ được, thử lại nhé.');
    }
  }

  String errorText(ApiException e) {
    if (e.code == 'CALENDAR_NOT_CONNECTED') {
      return 'Chưa kết nối Google Calendar.';
    }
    if (e.code == 'GOOGLE_SCOPE_MISSING') {
      return 'Quyền Google hết hạn, hãy kết nối lại.';
    }
    if (e.statusCode == 503) return 'Google đang bận, thử lại sau nhé.';
    return 'Không đồng bộ được, thử lại nhé.';
  }

  void showSnack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // Black rounded toast (Figma 328:33)
  void showDone() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.ink,
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.pillAll),
          content: Text(
            'Đã đồng bộ thành công',
            textAlign: TextAlign.center,
            style: AppTypography.subtitle.copyWith(
              color: AppColors.white,
              fontWeight: AppTypography.semiBold,
            ),
          ),
        ),
      );
  }

  void toggle(String id) {
    setState(() => picked.contains(id) ? picked.remove(id) : picked.add(id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                children: [
                  topBar(),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('Đẩy lịch lên Google', style: AppTypography.title),
                  const SizedBox(height: AppSpacing.xs),
                  ...result == null ? pickBody() : resultBody(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: bottomButtons(),
            ),
          ],
        ),
      ),
    );
  }

  Widget topBar() {
    return Row(
      children: [
        BrutalIconButton(
          icon: Icons.arrow_back,
          size: 40,
          onPressed: () => Navigator.pop(context, result != null),
        ),
        const Spacer(),
        const Text('Recolly', style: AppTypography.subtitle),
      ],
    );
  }

  Widget muted(String text) => Text(
    text,
    style: AppTypography.label.copyWith(
      fontWeight: AppTypography.regular,
      color: AppColors.inkMuted,
    ),
  );

  String get emailPart => widget.email == null ? '' : ' · ${widget.email}';

  List<Widget> pickBody() {
    if (loading) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: AppSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (loadError != null) {
      return [muted(loadError!)];
    }
    if (events.isEmpty) {
      return [muted('Không có sự kiện nào cần đồng bộ$emailPart')];
    }
    final widgets = <Widget>[
      muted('Đã chọn ${picked.length} / ${events.length}$emailPart'),
      const SizedBox(height: AppSpacing.sm),
      Row(
        children: [
          chip(
            'Chọn tất cả',
            () => setState(() => picked = events.map((e) => e.id).toSet()),
          ),
          const SizedBox(width: AppSpacing.xs),
          chip('Bỏ chọn', () => setState(() => picked = {})),
        ],
      ),
    ];
    DateTime? day;
    for (final e in events) {
      final start = e.startAt.toLocal();
      final d = DateTime(start.year, start.month, start.day);
      if (d != day) {
        day = d;
        widgets.add(const SizedBox(height: AppSpacing.md));
        widgets.add(
          Text(
            '${weekdayName(d)} ${two(d.day)}/${two(d.month)}',
            style: AppTypography.body.copyWith(
              fontWeight: AppTypography.semiBold,
            ),
          ),
        );
      }
      widgets.add(const SizedBox(height: AppSpacing.xs));
      widgets.add(eventCard(e, checkbox: true));
    }
    return widgets;
  }

  List<Widget> resultBody() {
    final r = result!;
    final t = syncedAt!;
    // Same wording as Figma
    final sub = [
      r.failed == 0 ? 'Không có lỗi' : '${r.failed} sự kiện bị lỗi',
      r.conflicts > 0
          ? '${r.conflicts} xung đột'
          : (r.failed == 0 ? 'không có xung đột' : 'chưa có xung đột'),
    ].join(', ');
    return [
      muted('Đồng bộ lúc ${two(t.hour)}:${two(t.minute)} hôm nay$emailPart'),
      const SizedBox(height: AppSpacing.md),
      BrutalCard(
        color: AppColors.green,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Đã đẩy ${r.pushed} sự kiện lên Google',
              style: AppTypography.body.copyWith(
                fontWeight: AppTypography.semiBold,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              sub,
              style: AppTypography.label.copyWith(
                fontWeight: AppTypography.regular,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                tag('Đã đẩy ${r.pushed}', AppColors.white),
                tag(
                  'Lỗi ${r.failed}',
                  r.failed > 0 ? AppColors.coral : AppColors.white,
                ),
                tag(
                  'Xung đột ${r.conflicts}',
                  r.conflicts > 0 ? AppColors.yellow : AppColors.white,
                ),
              ],
            ),
          ],
        ),
      ),
      if (failed.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        Text(
          'Chưa đẩy được',
          style: AppTypography.body.copyWith(
            fontWeight: AppTypography.semiBold,
          ),
        ),
        for (final e in failed) ...[
          const SizedBox(height: AppSpacing.xs),
          eventCard(e, checkbox: false),
        ],
      ],
    ];
  }

  Widget bottomButtons() {
    if (result != null) {
      final done = BrutalButton(
        label: 'Xong',
        color: AppColors.teal,
        onPressed: () => Navigator.pop(context, true),
      );
      if (failed.isEmpty) return done;
      return Row(
        children: [
          Expanded(
            child: BrutalButton(
              label: 'Thử lại',
              color: AppColors.yellow,
              onPressed: busy
                  ? null
                  : () => push(failed.map((e) => e.id).toList()),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: done),
        ],
      );
    }
    if (!loading && (events.isEmpty || loadError != null)) {
      return BrutalButton(
        label: loadError != null ? 'Thử lại' : 'Xong',
        color: AppColors.teal,
        onPressed: loadError != null ? load : () => Navigator.pop(context),
      );
    }
    return Row(
      children: [
        Expanded(
          child: BrutalButton(
            label: 'Hủy',
            color: AppColors.white,
            onPressed: () => Navigator.pop(context),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: BrutalButton(
            label: busy ? 'Đang đồng bộ...' : 'Đồng bộ ${picked.length} sự kiện',
            color: AppColors.teal,
            onPressed: busy || picked.isEmpty
                ? null
                : () => push(
                    events
                        .where((e) => picked.contains(e.id))
                        .map((e) => e.id)
                        .toList(),
                  ),
          ),
        ),
      ],
    );
  }

  Widget eventCard(CalendarEvent e, {required bool checkbox}) {
    final on = picked.contains(e.id);
    final start = e.startAt.toLocal();
    final end = e.endAt.toLocal();
    var time = '${two(start.hour)}:${two(start.minute)}';
    if (e.kind != EventKind.bedtime) {
      time += ' – ${two(end.hour)}:${two(end.minute)}';
    }
    if (!checkbox) {
      time += ' · Google từ chối, thử lại sau';
    } else if (e.location != null && e.location!.isNotEmpty) {
      time += ' · ${e.location}';
    }
    final card = BrutalCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 14,
      ),
      child: Row(
        children: [
          if (checkbox) ...[
            Container(
              width: 24,
              height: 24,
              decoration: AppTheme.brutalBox(
                color: on ? AppColors.teal : AppColors.white,
                borderRadius: const BorderRadius.all(Radius.circular(6)),
                hasShadow: false,
              ),
              child: on ? const Icon(Icons.check, size: 16) : null,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  style: AppTypography.body.copyWith(
                    fontWeight: AppTypography.semiBold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                muted(time),
                const SizedBox(height: AppSpacing.xxs),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    tag(kindName(e.kind), kindColor(e.kind)),
                    checkbox
                        ? tag(statusName(e.syncStatus), statusColor(e.syncStatus))
                        : tag('Lỗi', AppColors.coral),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (!checkbox) return card;
    return GestureDetector(onTap: () => toggle(e.id), child: card);
  }

  Widget chip(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: AppTheme.brutalBox(
          color: AppColors.white,
          borderRadius: AppRadii.pillAll,
        ),
        child: Text(text, style: AppTypography.label),
      ),
    );
  }

  Widget tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: AppTheme.brutalBox(
        color: color,
        borderRadius: AppRadii.pillAll,
        hasShadow: false,
      ),
      child: Text(text, style: AppTypography.label),
    );
  }
}

String two(int n) => n.toString().padLeft(2, '0');

String weekdayName(DateTime d) => const [
  'Thứ Hai',
  'Thứ Ba',
  'Thứ Tư',
  'Thứ Năm',
  'Thứ Sáu',
  'Thứ Bảy',
  'Chủ Nhật',
][d.weekday - 1];

String kindName(EventKind k) => switch (k) {
  EventKind.classSession => 'Môn học',
  EventKind.study => 'Ôn tập',
  EventKind.rest => 'Nghỉ',
  EventKind.bedtime => 'Giờ ngủ',
  EventKind.other => 'Khác',
};

Color kindColor(EventKind k) => switch (k) {
  EventKind.classSession => AppColors.white,
  EventKind.study => AppColors.green,
  EventKind.rest => AppColors.teal,
  EventKind.bedtime => lightSlate,
  EventKind.other => AppColors.yellow,
};

String statusName(SyncStatus s) => switch (s) {
  SyncStatus.pending => 'Có thay đổi',
  SyncStatus.error => 'Lỗi lần trước',
  _ => 'Chưa đồng bộ',
};

Color statusColor(SyncStatus s) => switch (s) {
  SyncStatus.pending => AppColors.yellow,
  SyncStatus.error => AppColors.coral,
  _ => AppColors.white,
};
