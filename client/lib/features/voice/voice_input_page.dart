import 'dart:async';
import 'dart:typed_data';

import 'package:client/core/di/repository_scope.dart';
import 'package:client/data/data.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../todo/todo_form_page.dart';
import '../todo/todo_list_page.dart';

// R41 + R44: Figma "Voice_input" (5:1272) and its states (298:33 ready,
// 298:91 processing, 298:149 done, 298:207 error).
// Record → POST /voice/transcribe → (202: poll /voice/jobs) → todo form.
// Pops `true` when a todo was saved.
class VoiceInputPage extends StatefulWidget {
  const VoiceInputPage({super.key});

  @override
  State<VoiceInputPage> createState() => _VoiceInputPageState();
}

enum VoiceStep { ready, listening, processing, done, error }

const int sampleRate = 16000;
const int maxSeconds = 60;

class _VoiceInputPageState extends State<VoiceInputPage> {
  final recorder = AudioRecorder();
  StreamSubscription<Uint8List>? audioSub;
  final audio = BytesBuilder(copy: false);
  Timer? tick;
  Timer? poll;
  int seconds = 0;
  int pollTries = 0;

  VoiceStep step = VoiceStep.ready;
  VoiceTranscription? result;

  // The user's edited copy of result.todoDraft.
  TodoDraft? draft;
  String errorText = '';

  VoiceRepository get repo => RepositoryScope.of(context).voice;

  @override
  void dispose() {
    tick?.cancel();
    poll?.cancel();
    audioSub?.cancel();
    recorder.dispose();
    super.dispose();
  }

  Future<void> startRecording() async {
    if (!await recorder.hasPermission()) {
      showError(
        'Bạn chưa cho Recolly dùng micro. Hãy bật quyền micro rồi thử lại.',
      );
      return;
    }
    audio.clear();
    // Raw PCM 16 kHz mono, wrapped into a wav file when done
    final stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      ),
    );
    audioSub = stream.listen(audio.add);
    seconds = 0;
    tick = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => seconds++);
      if (seconds >= maxSeconds) stopAndSend();
    });
    setState(() => step = VoiceStep.listening);
  }

  Future<void> stopAndSend() async {
    if (step != VoiceStep.listening) return;
    tick?.cancel();
    setState(() => step = VoiceStep.processing);
    await recorder.stop();
    await audioSub?.cancel();
    audioSub = null;
    final pcm = audio.takeBytes();
    if (pcm.length < sampleRate) {
      // Less than half a second of sound
      showError('Bản ghi quá ngắn. Bấm micro rồi nói lại nhé.');
      return;
    }
    try {
      final job = await repo.transcribe(
        wavFile(pcm),
        filename: 'voice.wav',
        referenceTime: DateTime.now(),
      );
      handleJob(job);
    } on ApiException catch (e) {
      showError(apiErrorText(e));
    } catch (e) {
      showError('Không gửi được bản ghi. Kiểm tra mạng rồi thử lại nhé.');
    }
  }

  void handleJob(VoiceJob job) {
    if (!mounted || step != VoiceStep.processing) return;
    if (job.status == JobStatus.succeeded && job.result != null) {
      poll?.cancel();
      setState(() {
        result = job.result;
        draft = job.result!.todoDraft;
        step = VoiceStep.done;
      });
    } else if (job.status == JobStatus.failed) {
      poll?.cancel();
      showError(
        job.error == 'VOICE_BAD_AUDIO'
            ? 'Âm thanh không rõ. Bạn thử nói lại nhé.'
            : 'Máy chủ nhận giọng nói đang lỗi. Bạn thử lại sau hoặc nhập tay nhé.',
      );
    } else if (poll == null && job.jobId != null) {
      // 202: the speech server is down, ask again every 5 s
      final id = job.jobId!;
      pollTries = 0;
      poll = Timer.periodic(const Duration(seconds: 5), (_) => checkJob(id));
    }
  }

  Future<void> checkJob(String id) async {
    pollTries++;
    // Stop after about 5 minutes, the recording stays saved on the server
    if (pollTries > 60) {
      poll?.cancel();
      showError('Máy chủ vẫn bận. Bản ghi đã được lưu, bạn thử lại sau nhé.');
      return;
    }
    try {
      handleJob(await repo.getVoiceJob(id));
    } catch (e) {
      // Network error: keep trying until the limit above
    }
  }

  void cancel() {
    poll?.cancel();
    poll = null;
    setState(() => step = VoiceStep.ready);
  }

  void showError(String text) {
    poll?.cancel();
    poll = null;
    if (!mounted) return;
    setState(() {
      errorText = text;
      step = VoiceStep.error;
    });
  }

  String apiErrorText(ApiException e) => switch (e.statusCode) {
    422 => 'Âm thanh không rõ hoặc file hỏng. Bạn thử nói lại nhé.',
    413 => 'Bản ghi dài quá. Nói ngắn hơn 60 giây nhé.',
    429 => 'Bạn dùng hơi nhiều rồi, đợi một chút rồi thử lại nhé.',
    _ => 'Máy chủ đang lỗi. Bạn thử lại hoặc nhập tay nhé.',
  };

  Future<void> openForm(TodoDraft? draft) async {
    // No draft found: keep what was said as the title
    final d =
        draft ??
        (result == null
            ? null
            : TodoDraft(
                title: result!.transcript,
                category: TodoCategory.other,
                priority: Priority.medium,
              ));
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TodoFormPage(draft: d, badge: '2 / 2'),
      ),
    );
    if (saved == true && mounted) Navigator.pop(context, true);
  }

  bool saving = false;

  // The draft is confirmed as-is: save it without opening the form.
  Future<void> saveDraft(TodoDraft draft) async {
    setState(() => saving = true);
    try {
      await RepositoryScope.of(context).todos.createTodo(
        TodoCreate(
          title: draft.title,
          description: draft.description,
          category: draft.category,
          priority: draft.priority,
          deadlineAt: draft.deadlineAt,
          estimatedMinutes: draft.estimatedMinutes,
          difficulty: draft.difficulty,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không lưu được, thử lại nhé')),
      );
    }
  }

  // What the server understood; tap a row to fix that field in place.
  Widget draftTable(TodoDraft d) {
    final deadline = d.deadlineAt;
    final minutes = d.estimatedMinutes;
    VoidCallback? tap(Future<void> Function() edit) => saving ? null : edit;
    return BrutalConfirmTable(
      headers: const ['Mục', 'Máy hiểu là (chạm để sửa)'],
      columnFlex: const [2, 3],
      rows: [
        ConfirmRow(cells: ['Tên việc', '${d.title} ✎'], onTap: tap(editTitle)),
        ConfirmRow(
          cells: ['Loại', '${categoryName(d.category)} ✎'],
          onTap: tap(
            () => pickOne(
              'Loại việc',
              TodoCategory.values,
              categoryName,
              d.category,
              (v) => editDraft(category: v),
            ),
          ),
        ),
        ConfirmRow(
          cells: ['Ưu tiên', '${priorityName(d.priority)} ✎'],
          onTap: tap(
            () => pickOne(
              'Ưu tiên',
              Priority.values,
              priorityName,
              d.priority,
              (v) => editDraft(priority: v),
            ),
          ),
        ),
        ConfirmRow(
          cells: [
            'Hạn chót',
            deadline == null
                ? 'Chưa có, chạm để thêm ✎'
                : '${weekdayName(deadline)} ${dayMonth(deadline)} '
                      '${hourMinute(deadline)} ✎',
          ],
          needsCheck: deadline == null,
          onTap: tap(editDeadline),
        ),
        ConfirmRow(
          cells: [
            'Ước tính',
            minutes == null ? 'Chưa có ✎' : '$minutes phút ✎',
          ],
          onTap: tap(
            () => pickOne(
              'Ước tính',
              const [15, 30, 60, 90, 120],
              (m) => '$m phút',
              minutes,
              (v) => editDraft(estimatedMinutes: v),
            ),
          ),
        ),
      ],
    );
  }

  // Replaces some fields of [draft] and redraws.
  void editDraft({
    String? title,
    TodoCategory? category,
    Priority? priority,
    DateTime? deadlineAt,
    int? estimatedMinutes,
  }) {
    final d = draft!;
    setState(
      () => draft = TodoDraft(
        title: title ?? d.title,
        description: d.description,
        category: category ?? d.category,
        priority: priority ?? d.priority,
        deadlineAt: deadlineAt ?? d.deadlineAt,
        estimatedMinutes: estimatedMinutes ?? d.estimatedMinutes,
        difficulty: d.difficulty,
      ),
    );
  }

  // Dialog with a text field for the todo title.
  Future<void> editTitle() async {
    // No controller: disposing one right after pop breaks the closing animation.
    var typed = draft!.title;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tên việc'),
        content: TextFormField(
          initialValue: typed,
          autofocus: true,
          onChanged: (v) => typed = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xong'),
          ),
        ],
      ),
    );
    if (ok == true && typed.trim().isNotEmpty) editDraft(title: typed.trim());
  }

  // Date picker, then time picker; keeps the old time when there was one.
  Future<void> editDeadline() async {
    final now = DateTime.now();
    final old = draft!.deadlineAt;
    final day = await showDatePicker(
      context: context,
      initialDate: old ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(old ?? DateTime(0, 1, 1, 23, 59)),
    );
    if (time == null) return;
    editDraft(
      deadlineAt: DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ),
    );
  }

  // Bottom sheet of chips; the tapped one is applied.
  Future<void> pickOne<T>(
    String title,
    List<T> options,
    String Function(T) name,
    T? current,
    void Function(T) apply,
  ) async {
    final picked = await showModalBottomSheet<T>(
      context: context,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: AppBorders.side,
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.subtitle),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final o in options)
                  TodoChip(
                    label: name(o),
                    selected: o == current,
                    onTap: () => Navigator.pop(context, o),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (picked != null) apply(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          children: [
            const TopBar(badge: '1 / 2'),
            const SizedBox(height: AppSpacing.lg),
            const Text('Nói lịch của bạn', style: AppTypography.title),
            const SizedBox(height: AppSpacing.lg),
            Center(child: micButton()),
            const SizedBox(height: AppSpacing.sm),
            statusLine(),
            const SizedBox(height: AppSpacing.lg),
            resultCard(),
            if (step == VoiceStep.done && draft != null) ...[
              const SizedBox(height: AppSpacing.md),
              const Text('Kiểm tra lại nhé', style: AppTypography.subtitle),
              const SizedBox(height: AppSpacing.xs),
              draftTable(draft!),
            ],
            const SizedBox(height: AppSpacing.lg),
            ...buttons(),
          ],
        ),
      ),
    );
  }

  Widget micButton() {
    final color = switch (step) {
      VoiceStep.processing => AppColors.yellow,
      VoiceStep.done => AppColors.green,
      VoiceStep.error => AppColors.coral,
      _ => AppColors.teal,
    };
    final listening = step == VoiceStep.listening;
    Widget ring(double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.fromBorderSide(AppBorders.side),
      ),
    );
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (listening) ...[ring(212), ring(172)],
          GestureDetector(
            onTap: switch (step) {
              VoiceStep.ready || VoiceStep.error => startRecording,
              VoiceStep.listening => stopAndSend,
              _ => null,
            },
            child: Container(
              width: 136,
              height: 136,
              decoration: AppTheme.brutalBox(
                color: color,
                borderRadius: AppRadii.pillAll,
              ),
              child: const Icon(Icons.mic_none, size: 52),
            ),
          ),
        ],
      ),
    );
  }

  Widget statusLine() {
    final (text, dot) = switch (step) {
      VoiceStep.ready => ('Bấm micro để nói', AppColors.inkMuted),
      VoiceStep.listening => ('Đang nghe...', AppColors.coral),
      VoiceStep.processing => ('Đang chuyển thành chữ...', AppColors.yellow),
      VoiceStep.done => ('Đã nhận xong', AppColors.green),
      VoiceStep.error => ('Không nhận được giọng nói', AppColors.coral),
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dot,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.ink, width: 1.5),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          text,
          style: AppTypography.label.copyWith(
            fontWeight: AppTypography.semiBold,
          ),
        ),
      ],
    );
  }

  Widget resultCard() {
    final (title, body, muted) = switch (step) {
      VoiceStep.ready => (
        'Ví dụ',
        'Thứ Sáu nộp báo cáo Lập trình Python, ưu tiên cao',
        true,
      ),
      VoiceStep.listening => (
        'Đang ghi âm',
        '${clock(seconds)} / ${clock(maxSeconds)} · Nói xong thì bấm Dừng',
        false,
      ),
      VoiceStep.processing => (
        'Đang xử lý',
        'Bản ghi đã được lưu. Nếu máy chủ bận, app sẽ tự hỏi lại sau vài giây.',
        true,
      ),
      VoiceStep.done => ('Nội dung nhận được', result?.transcript ?? '', false),
      VoiceStep.error => ('Có lỗi xảy ra', errorText, false),
    };
    return BrutalCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.label.copyWith(
              fontWeight: AppTypography.semiBold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: AppTypography.body.copyWith(
              color: muted ? AppColors.inkMuted : AppColors.ink,
            ),
          ),
          if (step == VoiceStep.done && draft == null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Chưa tách được việc từ câu này, bạn điền thêm ở bước sau nhé.',
              style: AppTypography.caption.copyWith(color: AppColors.inkMuted),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> buttons() {
    const gap = SizedBox(height: AppSpacing.md);
    switch (step) {
      case VoiceStep.ready:
        return [
          BrutalButton(
            label: 'Bắt đầu nói',
            color: AppColors.teal,
            onPressed: startRecording,
          ),
        ];
      case VoiceStep.listening:
        return [
          BrutalButton(
            label: 'Dừng',
            icon: Icons.stop_outlined,
            leadingIcon: true,
            color: AppColors.coral,
            onPressed: stopAndSend,
          ),
        ];
      case VoiceStep.processing:
        return [
          BrutalButton(label: 'Hủy', color: AppColors.white, onPressed: cancel),
        ];
      case VoiceStep.done:
        final draft = this.draft;
        return [
          BrutalButton(
            label: 'Nói lại',
            color: AppColors.white,
            onPressed: saving
                ? null
                : () => setState(() => step = VoiceStep.ready),
          ),
          gap,
          if (draft == null)
            BrutalButton(
              label: 'Dùng kết quả này',
              onPressed: () => openForm(null),
            )
          else ...[
            BrutalButton(
              label: 'Sửa chi tiết',
              color: AppColors.yellow,
              onPressed: saving ? null : () => openForm(draft),
            ),
            gap,
            BrutalButton(
              label: saving ? 'Đang lưu...' : 'Đúng rồi, lưu',
              onPressed: saving ? null : () => saveDraft(draft),
            ),
          ],
        ];
      case VoiceStep.error:
        return [
          BrutalButton(
            label: 'Thử lại',
            color: AppColors.yellow,
            onPressed: () => setState(() => step = VoiceStep.ready),
          ),
          gap,
          BrutalButton(
            label: 'Nhập tay',
            color: AppColors.white,
            onPressed: () => openForm(null),
          ),
        ];
    }
  }
}

// 7 -> "0:07"
String clock(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

// 44-byte wav header in front of 16-bit mono PCM
Uint8List wavFile(Uint8List pcm) {
  final header = ByteData(44);
  void text(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  text(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  return (BytesBuilder()
        ..add(header.buffer.asUint8List())
        ..add(pcm))
      .takeBytes();
}
