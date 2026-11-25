import 'package:client/core/di/repository_scope.dart';
import 'package:client/data/data.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/theme/app_theme.dart';
import '../auth/google_auth.dart';
import 'calendar_push_page.dart';
import 'conflict_auto_resolver.dart';
import '../../widgets/widgets.dart';

// R32: Google Calendar connect sheet (Figma "Google Calendar – Đã kết nối"
// 273:33 and "– Chưa kết nối" 273:140).
// Open it with GoogleCalendarSheet.show(context).

const calendarScopes = ['https://www.googleapis.com/auth/calendar.events'];

class GoogleCalendarSheet extends StatefulWidget {
  const GoogleCalendarSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      // Cover the bottom nav bar too (Figma)
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.ink.withValues(alpha: 0.22),
      builder: (_) => const GoogleCalendarSheet(),
    );
  }

  @override
  State<GoogleCalendarSheet> createState() => _GoogleCalendarSheetState();
}

class _GoogleCalendarSheetState extends State<GoogleCalendarSheet> {
  CalendarStatus? status;
  bool loading = true;
  bool busy = false;
  String? error;

  CalendarSyncRepository get repo => RepositoryScope.of(context).calendarSync;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading && status == null && error == null) load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      var s = await repo.getStatus();
      s = await keepTwoWay(s);
      if (!mounted) return;
      setState(() {
        status = s;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'Không tải được trạng thái, thử lại nhé.';
      });
    }
  }

  // R46: turn on two-way sync and clear conflicts quietly, errors ignored
  Future<CalendarStatus> keepTwoWay(CalendarStatus s) async {
    if (!s.connected) return s;
    try {
      if (!s.twoWaySync) s = await repo.updateSettings(twoWaySync: true);
      if (s.conflictCount > 0 && await resolveAllConflicts(repo) > 0) {
        s = await repo.getStatus();
      }
    } catch (_) {}
    return s;
  }

  void showSnack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // Ask Google for a server auth code with the calendar scope.
  Future<String?> getGoogleCode() async {
    if (ApiConfig.useMock) return 'mock-server-auth-code';
    await ensureGoogleReady();
    final account = await GoogleSignIn.instance.authenticate(
      scopeHint: calendarScopes,
    );
    final auth = await account.authorizationClient.authorizeServer(
      calendarScopes,
    );
    return auth?.serverAuthCode;
  }

  Future<void> connect() async {
    setState(() => busy = true);
    try {
      final code = await getGoogleCode();
      if (code == null) {
        showSnack('Bạn chưa cấp quyền Google Calendar.');
      } else {
        final s = await repo.connect(code);
        if (!mounted) return;
        setState(() => status = s);
        showSnack('Đã kết nối Google Calendar.');
      }
    } on GoogleSignInException catch (e) {
      // User closed the Google popup -> do nothing
      if (e.code != GoogleSignInExceptionCode.canceled) {
        showSnack('Đăng nhập Google lỗi, thử lại nhé.');
      }
    } on ApiException catch (e) {
      showSnack(
        e.code == 'GOOGLE_SCOPE_MISSING'
            ? 'Bạn chưa cấp quyền Google Calendar.'
            : 'Không kết nối được, thử lại nhé.',
      );
    } catch (e) {
      showSnack('Không kết nối được, thử lại nhé.');
    }
    if (mounted) setState(() => busy = false);
  }

  // R33: pick which events to push, then reload the status
  Future<void> openPush() async {
    final pushed = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => CalendarPushPage(email: status?.googleEmail),
      ),
    );
    if (pushed == true && mounted) load();
  }

  Future<void> disconnect() async {
    // Figma 331:51, tap outside = cancel
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.ink.withValues(alpha: 0.22),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: AppTheme.brutalBox(color: AppColors.cream),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ngắt kết nối Google Calendar?',
                style: AppTypography.subtitle.copyWith(fontSize: 20),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Lịch trong app vẫn giữ nguyên. Các sự kiện sẽ không còn '
                'được đẩy lên Google.',
                style: AppTypography.body,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: BrutalButton(
                      label: 'Hủy',
                      color: AppColors.white,
                      onPressed: () => Navigator.pop(context, false),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: BrutalButton(
                      label: 'Ngắt',
                      color: AppColors.coral,
                      onPressed: () => Navigator.pop(context, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      await repo.disconnect();
      final s = await repo.getStatus();
      if (!mounted) return;
      setState(() => status = s);
    } catch (e) {
      showSnack('Không ngắt được, thử lại nhé.');
    }
    if (mounted) setState(() => busy = false);
  }

  static String two(int n) => n.toString().padLeft(2, '0');

  String lastSyncText(DateTime? d) {
    if (d == null) return 'Chưa đồng bộ lần nào';
    final t = d.toLocal();
    final now = DateTime.now();
    final time = '${two(t.hour)}:${two(t.minute)}';
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return 'Đồng bộ lần cuối: $time hôm nay';
    }
    return 'Đồng bộ lần cuối: $time ${two(t.day)}/${two(t.month)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: AppTheme.brutalBox(
        color: AppColors.cream,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: AppRadii.pillAll,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('Google Calendar', style: AppTypography.title),
              const SizedBox(height: AppSpacing.sm),
              ...body(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> body() {
    if (loading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (error != null) {
      return [
        Text(error!, style: AppTypography.body),
        const SizedBox(height: AppSpacing.lg),
        BrutalButton(
          label: 'Thử lại',
          icon: Icons.refresh,
          leadingIcon: true,
          color: AppColors.white,
          onPressed: load,
        ),
      ];
    }
    final s = status!;
    if (!s.connected) {
      return [
        tag('Chưa kết nối', AppColors.coral),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Kết nối để đẩy lịch học và lịch ôn lên Google Calendar, '
          'xem được trên mọi thiết bị.',
          style: AppTypography.body.copyWith(fontSize: 17, height: 1.4),
        ),
        const SizedBox(height: AppSpacing.lg),
        BrutalButton(
          label: 'Kết nối Google Calendar',
          icon: Icons.link,
          leadingIcon: true,
          onPressed: busy ? null : connect,
        ),
      ];
    }
    return [
      infoRow(Icons.mail_outline, s.googleEmail ?? 'Tài khoản Google'),
      const SizedBox(height: AppSpacing.xs),
      infoRow(Icons.schedule, lastSyncText(s.lastSyncedAt)),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: 10,
        runSpacing: AppSpacing.sm,
        children: [
          tag('Đã kết nối', AppColors.green),
          if (s.pendingCount > 0)
            GestureDetector(
              onTap: busy ? null : openPush,
              child: tag('${s.pendingCount} sự kiện chờ', AppColors.yellow),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      BrutalButton(
        label: 'Đồng bộ ngay',
        icon: Icons.sync,
        leadingIcon: true,
        color: AppColors.teal,
        onPressed: busy ? null : openPush,
      ),
      const SizedBox(height: AppSpacing.sm),
      disconnectButton(),
    ];
  }

  // Red label + icon (Figma), BrutalButton only has ink text
  Widget disconnectButton() {
    final color = busy ? AppColors.inkMuted : AppColors.danger;
    return GestureDetector(
      onTap: busy ? null : disconnect,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: AppTheme.brutalBox(
          color: busy ? AppColors.disabled : AppColors.coral,
          borderRadius: AppRadii.pillAll,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.link_off, size: 18, color: color),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Ngắt kết nối',
              style: AppTypography.button.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.ink),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(text, style: AppTypography.body)),
      ],
    );
  }

  // Pill tag with hard shadow (same as event detail)
  Widget tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: AppTheme.brutalBox(
        color: color,
        borderRadius: AppRadii.pillAll,
      ),
      child: Text(text, style: AppTypography.label),
    );
  }
}
