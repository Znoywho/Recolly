import 'dart:async';
import 'dart:typed_data';

import 'package:client/core/di/repository_scope.dart';
import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';

// R62: waits for the OCR job (scanning screen) and shows the
// scan failed screen if it does not work.
// Pops with List<SubjectDraft> on success, or one of the action strings below.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.jobId, required this.photo});

  static const retake = 'retake';
  static const pickOther = 'pick_other';
  static const manual = 'manual';

  final String jobId;
  final Uint8List photo;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  TimetableRepository? repo;
  Timer? timer;
  JobStatus status = JobStatus.queued;
  String? errorCode;
  bool failed = false;
  int tries = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (repo == null) {
      repo = RepositoryScope.of(context).timetable;
      timer = Timer.periodic(const Duration(seconds: 2), (_) => check());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> check() async {
    tries++;
    // Give up after about 2 minutes
    if (tries > 60) {
      showFailed('TIMEOUT');
      return;
    }
    try {
      final job = await repo!.getOcrJob(widget.jobId);
      if (!mounted || failed) return;
      if (job.status == JobStatus.succeeded) {
        timer?.cancel();
        Navigator.pop(context, job.subjects);
      } else if (job.status == JobStatus.failed) {
        showFailed(job.error);
      } else {
        setState(() => status = job.status);
      }
    } catch (e) {
      // Network error: keep trying, the timeout above stops it
    }
  }

  void showFailed(String? code) {
    timer?.cancel();
    if (!mounted) return;
    setState(() {
      failed = true;
      errorCode = code;
    });
  }

  String errorText() {
    switch (errorCode) {
      case 'OCR_NO_TABLE_FOUND':
        return 'Không thấy bảng thời khóa biểu trong ảnh. Hãy chụp cả bảng nhé.';
      case 'OCR_LOW_QUALITY':
        return 'Ảnh bị mờ hoặc thiếu sáng. Hãy chụp lại gần hơn.';
      case 'TIMEOUT':
        return 'Quét lâu quá rồi. Thử lại sau một chút nhé.';
      default:
        return 'Có lỗi khi đọc ảnh. Hãy thử lại hoặc nhập thủ công.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Row(
              children: [
                BrutalIconButton(
                  icon: Icons.arrow_back,
                  onPressed: () => Navigator.pop(context),
                ),
                const Expanded(
                  child: Text(
                    'Recolly',
                    textAlign: TextAlign.center,
                    style: AppTypography.subtitle,
                  ),
                ),
                const BrutalBadge(label: '1 / 2'),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (failed) ...failedView() else ...scanningView(),
          ],
        ),
      ),
    );
  }

  List<Widget> scanningView() {
    final progress = status == JobStatus.processing ? 0.65 : 0.25;
    return [
      const Text('Quét thời khóa biểu', style: AppTypography.title),
      const SizedBox(height: AppSpacing.lg),
      BrutalCard(
        color: AppColors.teal,
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: ClipRRect(
          borderRadius: AppRadii.inputAll,
          child: Image.memory(
            widget.photo,
            height: 260,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      BrutalProgressBar(value: progress, fillColor: AppColors.green, height: 24),
      const SizedBox(height: AppSpacing.md),
      Text(
        status == JobStatus.processing
            ? 'Đang đọc thời khóa biểu...'
            : 'Đang chờ đến lượt quét...',
        textAlign: TextAlign.center,
        style: AppTypography.body,
      ),
      const Text(
        'Quá trình này mất khoảng vài giây',
        textAlign: TextAlign.center,
        style: AppTypography.body,
      ),
      const SizedBox(height: AppSpacing.lg),
      BrutalButton(
        label: 'Hủy',
        color: AppColors.white,
        onPressed: () => Navigator.pop(context),
      ),
    ];
  }

  List<Widget> failedView() {
    return [
      BrutalCard(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: AppTheme.brutalBox(
                color: AppColors.coral,
                borderRadius: AppRadii.pillAll,
              ),
              child: const Icon(Icons.close, size: 48),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Chưa đọc được ảnh',
              textAlign: TextAlign.center,
              style: AppTypography.title,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              errorText(),
              textAlign: TextAlign.center,
              style: AppTypography.body,
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      BrutalButton(
        label: 'Chụp lại',
        icon: Icons.photo_camera_outlined,
        leadingIcon: true,
        onPressed: () => Navigator.pop(context, ScanPage.retake),
      ),
      const SizedBox(height: AppSpacing.md),
      BrutalButton(
        label: 'Chọn ảnh khác',
        icon: Icons.photo_library_outlined,
        leadingIcon: true,
        color: AppColors.white,
        onPressed: () => Navigator.pop(context, ScanPage.pickOther),
      ),
      const SizedBox(height: AppSpacing.md),
      BrutalButton(
        label: 'Nhập thủ công',
        color: AppColors.white,
        onPressed: () => Navigator.pop(context, ScanPage.manual),
      ),
    ];
  }
}
