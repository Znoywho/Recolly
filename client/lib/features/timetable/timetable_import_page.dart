import 'package:client/core/di/repository_scope.dart';
import 'package:client/data/data.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../voice/voice_input_page.dart';
import 'scan_page.dart';
import 'scan_result_page.dart';

// R13: take or pick a timetable photo, upload it, then go to the scan screen.
// Pops `true` when the timetable was saved.
class TimetableImportPage extends StatefulWidget {
  const TimetableImportPage({super.key});

  @override
  State<TimetableImportPage> createState() => _TimetableImportPageState();
}

class _TimetableImportPageState extends State<TimetableImportPage> {
  final picker = ImagePicker();
  bool uploading = false;

  TimetableRepository get repo => RepositoryScope.of(context).timetable;

  Future<void> pickPhoto(ImageSource source) async {
    final XFile? file;
    try {
      file = await picker.pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 85,
      );
    } catch (e) {
      showMessage('Không mở được camera hoặc thư viện ảnh');
      return;
    }
    if (file == null) return;

    final bytes = await file.readAsBytes();
    // Server limit is 10 MB
    if (bytes.length > 10 * 1024 * 1024) {
      showMessage('Ảnh lớn quá (tối đa 10 MB), chọn ảnh khác nhé');
      return;
    }

    setState(() => uploading = true);
    OcrJob job;
    try {
      job = await repo.uploadTimetablePhoto(bytes, filename: file.name);
    } catch (e) {
      setState(() => uploading = false);
      showMessage('Không tải ảnh lên được, thử lại nhé');
      return;
    }
    setState(() => uploading = false);
    if (!mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScanPage(jobId: job.jobId, photo: bytes),
      ),
    );
    if (!mounted) return;

    if (result is List<SubjectDraft>) {
      openResult(result);
    } else if (result == ScanPage.retake) {
      pickPhoto(ImageSource.camera);
    } else if (result == ScanPage.pickOther) {
      pickPhoto(ImageSource.gallery);
    } else if (result == ScanPage.manual) {
      openResult([]);
    }
  }

  // R14: check / edit the subjects, then save. Close this page when saved.
  Future<void> openResult(List<SubjectDraft> subjects) async {
    final saved = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ScanResultPage(subjects: subjects)),
    );
    if (saved == true && mounted) Navigator.pop(context, true);
  }

  void showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: BrutalIconButton(
                icon: Icons.arrow_back,
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text('Thêm thời khóa biểu', style: AppTypography.title),
            const SizedBox(height: AppSpacing.xl),
            BrutalCard(
              borderStyle: BrutalBorderStyle.dashed,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: AppTheme.brutalBox(color: AppColors.teal),
                    child: uploading
                        ? const Padding(
                            padding: EdgeInsets.all(22),
                            child: CircularProgressIndicator(
                              color: AppColors.ink,
                              strokeWidth: 3,
                            ),
                          )
                        : const Icon(Icons.photo_camera_outlined, size: 34),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    uploading
                        ? 'Đang tải ảnh lên...'
                        : 'Chụp ảnh thời khóa biểu của bạn',
                    style: AppTypography.body,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            BrutalButton(
              label: 'Chụp ảnh',
              icon: Icons.photo_camera_outlined,
              leadingIcon: true,
              onPressed: uploading
                  ? null
                  : () => pickPhoto(ImageSource.camera),
            ),
            const SizedBox(height: AppSpacing.md),
            BrutalButton(
              label: 'Chọn từ thư viện',
              icon: Icons.photo_library_outlined,
              leadingIcon: true,
              color: AppColors.white,
              onPressed: uploading
                  ? null
                  : () => pickPhoto(ImageSource.gallery),
            ),
            const SizedBox(height: AppSpacing.md),
            BrutalButton(
              label: 'Nhập bằng giọng nói',
              icon: Icons.mic_none,
              leadingIcon: true,
              color: AppColors.yellow,
              onPressed: uploading
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const VoiceInputPage(),
                      ),
                    ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Bạn có thể chỉnh lại kết quả sau khi quét.',
              textAlign: TextAlign.center,
              style: AppTypography.label,
            ),
          ],
        ),
      ),
    );
  }
}
