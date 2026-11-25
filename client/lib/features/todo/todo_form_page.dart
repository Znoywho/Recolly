import 'package:client/core/di/repository_scope.dart';
import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'todo_list_page.dart';

// Figma "Việc cần làm – Thêm / Sửa" (308:150).
// Create (todo == null, can be prefilled from a voice draft) or edit.
// Pops `true` when something changed.
class TodoFormPage extends StatefulWidget {
  const TodoFormPage({super.key, this.todo, this.draft, this.badge});

  final Todo? todo;
  final TodoDraft? draft;

  // "2 / 2" when coming from the voice screen
  final String? badge;

  @override
  State<TodoFormPage> createState() => _TodoFormPageState();
}

class _TodoFormPageState extends State<TodoFormPage> {
  final titleCtrl = TextEditingController();
  final minutesCtrl = TextEditingController();
  TodoCategory category = TodoCategory.study;
  Priority priority = Priority.medium;
  DateTime? date;
  TimeOfDay time = const TimeOfDay(hour: 23, minute: 59);
  String? description;
  bool saving = false;

  bool get isEdit => widget.todo != null;

  @override
  void initState() {
    super.initState();
    final t = widget.todo;
    final d = widget.draft;
    if (t != null) {
      fill(t.title, t.category, t.priority, t.deadlineAt, t.estimatedMinutes);
      description = t.description;
    } else if (d != null) {
      fill(d.title, d.category, d.priority, d.deadlineAt, d.estimatedMinutes);
      description = d.description;
    }
  }

  void fill(
    String title,
    TodoCategory c,
    Priority p,
    DateTime? deadline,
    int? minutes,
  ) {
    titleCtrl.text = title;
    minutesCtrl.text = minutes?.toString() ?? '';
    category = c;
    priority = p;
    final local = deadline?.toLocal();
    if (local != null) {
      date = DateTime(local.year, local.month, local.day);
      time = TimeOfDay.fromDateTime(local);
    }
  }

  @override
  void dispose() {
    titleCtrl.dispose();
    minutesCtrl.dispose();
    super.dispose();
  }

  DateTime? get deadline => date == null
      ? null
      : DateTime(date!.year, date!.month, date!.day, time.hour, time.minute);

  Future<void> pickDate() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: date ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (d != null) setState(() => date = d);
  }

  Future<void> pickTime() async {
    FocusScope.of(context).unfocus();
    final t = await showTimePicker(context: context, initialTime: time);
    if (t != null) {
      setState(() {
        time = t;
        // A time without a day means today
        date ??= DateUtils.dateOnly(DateTime.now());
      });
    }
  }

  Future<void> save() async {
    final title = titleCtrl.text.trim();
    if (title.isEmpty) {
      showError('Nhập tên việc trước nhé');
      return;
    }
    final minutes = int.tryParse(minutesCtrl.text.trim());

    setState(() => saving = true);
    final repo = RepositoryScope.of(context).todos;
    try {
      if (isEdit) {
        await repo.updateTodo(
          widget.todo!.id,
          TodoUpdate(
            title: title,
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
            description: description,
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
      showError('Không xóa được, thử lại nhé');
    }
  }

  void showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs, top: AppSpacing.md),
    child: Text(text, style: AppTypography.label),
  );

  Widget pickBox(String text, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.inputAll,
      child: InputDecorator(
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          suffixIcon: Icon(icon, size: 20),
        ),
        child: Text(text, maxLines: 1, style: AppTypography.body),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = date;
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
            TopBar(badge: widget.badge),
            const SizedBox(height: AppSpacing.lg),
            Text(
              isEdit ? 'Sửa việc cần làm' : 'Thêm việc cần làm',
              style: AppTypography.title,
            ),
            label('Tên việc'),
            TextField(controller: titleCtrl),
            label('Loại'),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final c in TodoCategory.values)
                  TodoChip(
                    label: categoryName(c),
                    selected: category == c,
                    onTap: () => setState(() => category = c),
                  ),
              ],
            ),
            label('Mức ưu tiên'),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                for (final p in Priority.values)
                  TodoChip(
                    label: priorityName(p),
                    selected: priority == p,
                    selectedColor: priorityColor(p),
                    onTap: () => setState(() => priority = p),
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      label('Ngày hạn'),
                      pickBox(
                        d == null
                            ? 'Chưa chọn'
                            : '${two(d.day)}/${two(d.month)}/${d.year}',
                        Icons.calendar_today_outlined,
                        pickDate,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      label('Giờ hạn'),
                      pickBox(
                        '${two(time.hour)}:${two(time.minute)}',
                        Icons.schedule,
                        pickTime,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (d != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => date = null),
                  child: const Text('Bỏ hạn'),
                ),
              ),
            label('Thời gian làm (phút)'),
            TextField(
              controller: minutesCtrl,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: BrutalButton(
                    label: 'Hủy',
                    color: AppColors.white,
                    onPressed: saving ? null : () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: BrutalButton(
                    label: saving ? 'Đang lưu...' : 'Lưu',
                    onPressed: saving ? null : save,
                  ),
                ),
              ],
            ),
            if (isEdit) ...[
              const SizedBox(height: AppSpacing.md),
              BrutalButton(
                label: 'Xóa việc này',
                icon: Icons.delete_outline,
                leadingIcon: true,
                color: AppColors.coral,
                onPressed: saving ? null : delete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
