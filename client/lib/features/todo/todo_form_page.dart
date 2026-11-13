import 'package:client/core/di/repository_scope.dart';
import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'todo_list_page.dart';

// Create a todo (todo == null) or edit one. Pops `true` when something changed.
class TodoFormPage extends StatefulWidget {
  const TodoFormPage({super.key, this.todo});

  final Todo? todo;

  @override
  State<TodoFormPage> createState() => _TodoFormPageState();
}

class _TodoFormPageState extends State<TodoFormPage> {
  final titleCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  final minutesCtrl = TextEditingController();
  TodoCategory category = TodoCategory.study;
  Priority priority = Priority.medium;
  DateTime? deadline;
  bool saving = false;

  bool get isEdit => widget.todo != null;

  @override
  void initState() {
    super.initState();
    final t = widget.todo;
    if (t != null) {
      titleCtrl.text = t.title;
      noteCtrl.text = t.description ?? '';
      minutesCtrl.text = t.estimatedMinutes?.toString() ?? '';
      category = t.category;
      priority = t.priority;
      deadline = t.deadlineAt?.toLocal();
    }
  }

  @override
  void dispose() {
    titleCtrl.dispose();
    noteCtrl.dispose();
    minutesCtrl.dispose();
    super.dispose();
  }

  Future<void> pickDeadline() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: deadline ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: deadline != null
          ? TimeOfDay.fromDateTime(deadline!)
          : const TimeOfDay(hour: 23, minute: 59),
    );
    if (time == null) return;
    setState(() {
      deadline = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> save() async {
    final title = titleCtrl.text.trim();
    if (title.isEmpty) {
      showError('Nhập tên việc trước nhé');
      return;
    }
    final note = noteCtrl.text.trim();
    final minutes = int.tryParse(minutesCtrl.text.trim());

    setState(() => saving = true);
    final repo = RepositoryScope.of(context).todos;
    try {
      if (isEdit) {
        await repo.updateTodo(
          widget.todo!.id,
          TodoUpdate(
            title: title,
            description: Nullable(note.isEmpty ? null : note),
            category: category,
            priority: priority,
            deadlineAt: Nullable(deadline),
            estimatedMinutes: Nullable(minutes),
          ),
        );
      } else {
        await repo.createTodo(
          TodoCreate(
            title: title,
            description: note.isEmpty ? null : note,
            category: category,
            priority: priority,
            deadlineAt: deadline,
            estimatedMinutes: minutes,
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => saving = false);
      showError('Không lưu được, thử lại nhé');
    }
  }

  Future<void> delete() async {
    setState(() => saving = true);
    try {
      await RepositoryScope.of(context).todos.deleteTodo(widget.todo!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => saving = false);
      showError('Không xoá được, thử lại nhé');
    }
  }

  void showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String deadlineText() {
    final d = deadline;
    if (d == null) return 'Chưa có hạn';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}  ${two(d.day)}/${two(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Sửa việc' : 'Thêm việc')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          TextField(
            controller: titleCtrl,
            decoration: const InputDecoration(labelText: 'Tên việc'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: noteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Ghi chú'),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text('Loại', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final c in TodoCategory.values)
                ChoiceChip(
                  label: Text(categoryName(c)),
                  selected: category == c,
                  onSelected: (_) => setState(() => category = c),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text('Mức ưu tiên', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              for (final p in Priority.values)
                ChoiceChip(
                  label: Text(priorityName(p)),
                  selected: priority == p,
                  onSelected: (_) => setState(() => priority = p),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text('Deadline', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          BrutalCard(
            hasShadow: false,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xxs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(deadlineText(), style: AppTypography.body),
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_month),
                  onPressed: pickDeadline,
                ),
                if (deadline != null)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => deadline = null),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: minutesCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Thời lượng ước tính (phút)',
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          BrutalButton(
            label: saving ? 'Đang lưu...' : 'Lưu',
            onPressed: saving ? null : save,
          ),
          if (isEdit) ...[
            const SizedBox(height: AppSpacing.md),
            BrutalButton(
              label: 'Xoá việc này',
              color: AppColors.coral,
              onPressed: saving ? null : delete,
            ),
          ],
        ],
      ),
    );
  }
}
