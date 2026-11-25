import 'package:client/core/di/repository_scope.dart';
import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../voice/voice_input_page.dart';
import 'todo_form_page.dart';

// Figma "Việc cần làm" (308:33). Opened from the week calendar header.
class TodoListPage extends StatefulWidget {
  const TodoListPage({super.key});

  @override
  State<TodoListPage> createState() => _TodoListPageState();
}

enum TodoFilter { open, done, all }

class _TodoListPageState extends State<TodoListPage> {
  List<Todo> todos = [];
  bool loading = true;
  String? error;
  TodoFilter filter = TodoFilter.open;

  TodoRepository get repo => RepositoryScope.of(context).todos;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (loading && todos.isEmpty && error == null) load();
  }

  Future<void> load() async {
    try {
      final page = await repo.listTodos(limit: 100);
      setState(() {
        todos = page.items;
        loading = false;
        error = null;
      });
    } catch (e) {
      setState(() {
        loading = false;
        error = 'Không tải được danh sách, thử lại nhé';
      });
    }
  }

  Future<void> toggleDone(Todo todo) async {
    final newStatus = todo.status == TodoStatus.done
        ? TodoStatus.todo
        : TodoStatus.done;
    try {
      final updated = await repo.updateTodo(
        todo.id,
        TodoUpdate(status: newStatus),
      );
      setState(() {
        final i = todos.indexWhere((t) => t.id == todo.id);
        if (i != -1) todos[i] = updated;
      });
    } catch (e) {
      showError('Không cập nhật được, thử lại nhé');
    }
  }

  Future<bool> askDelete(Todo todo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa việc này?'),
        content: Text(todo.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> delete(Todo todo) async {
    setState(() => todos.removeWhere((t) => t.id == todo.id));
    try {
      await repo.deleteTodo(todo.id);
    } catch (e) {
      showError('Không xóa được, thử lại nhé');
      load();
    }
  }

  Future<void> openForm([Todo? todo]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => TodoFormPage(todo: todo)),
    );
    if (changed == true) load();
  }

  Future<void> openVoice() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const VoiceInputPage()),
    );
    if (changed == true) load();
  }

  void showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  List<Todo> shownTodos() {
    final list = todos.where((t) {
      final done = t.status == TodoStatus.done;
      return switch (filter) {
        TodoFilter.open => !done,
        TodoFilter.done => done,
        TodoFilter.all => true,
      };
    }).toList();
    // Not done first, then nearest deadline, no deadline last
    list.sort((a, b) {
      final ad = a.status == TodoStatus.done ? 1 : 0;
      final bd = b.status == TodoStatus.done ? 1 : 0;
      if (ad != bd) return ad - bd;
      final x = a.deadlineAt, y = b.deadlineAt;
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return x.compareTo(y);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TopBar(),
              const SizedBox(height: AppSpacing.lg),
              const Text('Việc cần làm', style: AppTypography.title),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  for (final f in TodoFilter.values)
                    TodoChip(
                      label: filterName(f),
                      selected: filter == f,
                      selectedColor: AppColors.yellow,
                      onTap: () => setState(() => filter = f),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(child: buildBody()),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: BrutalButton(
                      label: 'Nói việc',
                      icon: Icons.mic_none,
                      leadingIcon: true,
                      color: AppColors.teal,
                      onPressed: openVoice,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: BrutalButton(
                      label: '+ Thêm việc',
                      color: AppColors.yellow,
                      onPressed: () => openForm(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildBody() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!, style: AppTypography.body),
            const SizedBox(height: AppSpacing.md),
            BrutalButton(
              label: 'Thử lại',
              expanded: false,
              onPressed: () {
                setState(() => loading = true);
                load();
              },
            ),
          ],
        ),
      );
    }
    final list = shownTodos();
    if (list.isEmpty) {
      return Center(
        child: Text(
          filter == TodoFilter.done
              ? 'Chưa có việc nào xong.'
              : 'Chưa có việc nào. Bấm "+ Thêm việc" hoặc "Nói việc" nhé!',
          textAlign: TextAlign.center,
          style: AppTypography.body,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: load,
      child: ListView.separated(
        // Room for the hard shadow under the last card
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, i) {
          final todo = list[i];
          return Dismissible(
            key: ValueKey(todo.id),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => askDelete(todo),
            onDismissed: (_) => delete(todo),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: AppSpacing.lg),
              decoration: AppTheme.brutalBox(
                color: AppColors.coral,
                hasShadow: false,
              ),
              child: const Icon(Icons.delete, color: AppColors.ink),
            ),
            child: TodoTile(
              todo: todo,
              onToggle: () => toggleDone(todo),
              onTap: () => openForm(todo),
            ),
          );
        },
      ),
    );
  }
}

// Back button + "Recolly", same as the other pushed screens
class TopBar extends StatelessWidget {
  const TopBar({super.key, this.badge});

  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        BrutalIconButton(
          icon: Icons.arrow_back,
          size: 40,
          onPressed: () => Navigator.maybePop(context),
        ),
        const Expanded(
          child: Text(
            'Recolly',
            textAlign: TextAlign.center,
            style: AppTypography.subtitle,
          ),
        ),
        // Keeps the title centered when there is no badge
        badge == null
            ? const SizedBox(width: 40)
            : BrutalBadge(label: badge!),
      ],
    );
  }
}

class TodoTile extends StatelessWidget {
  const TodoTile({
    super.key,
    required this.todo,
    required this.onToggle,
    required this.onTap,
  });

  final Todo todo;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = todo.status == TodoStatus.done;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: done ? 0.85 : 1,
        child: BrutalCard(
          color: done ? AppColors.cream : AppColors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 14,
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: onToggle,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: AppTheme.brutalBox(
                    color: done ? AppColors.green : AppColors.white,
                    borderRadius: const BorderRadius.all(Radius.circular(6)),
                    hasShadow: false,
                  ),
                  child: done ? const Icon(Icons.check, size: 16) : null,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todo.title,
                      style: AppTypography.body.copyWith(
                        fontWeight: AppTypography.semiBold,
                        color: done ? AppColors.inkMuted : AppColors.ink,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitleText(),
                      style: AppTypography.caption.copyWith(
                        color: AppColors.inkMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Wrap(
                      spacing: 6,
                      children: [
                        TodoTag(label: categoryName(todo.category)),
                        TodoTag(
                          label: priorityName(todo.priority),
                          color: priorityColor(todo.priority),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String subtitleText() {
    if (todo.status == TodoStatus.done) {
      final d = todo.completedAt?.toLocal();
      return d == null ? 'Xong' : 'Xong · ${dayMonth(d)}';
    }
    final d = todo.deadlineAt?.toLocal();
    if (d == null) return 'Không có hạn';
    return 'Hạn: ${weekdayName(d)} ${dayMonth(d)} · ${hourMinute(d)}';
  }
}

// Small pill with border and hard shadow (filters, category, priority)
class TodoChip extends StatelessWidget {
  const TodoChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedColor = AppColors.teal,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // Space for the shadow so it is not cut off in a Wrap
        margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: AppTheme.brutalBox(
          color: selected ? selectedColor : AppColors.white,
          borderRadius: AppRadii.pillAll,
        ),
        child: Text(
          label,
          style: AppTypography.label.copyWith(
            fontWeight: AppTypography.semiBold,
          ),
        ),
      ),
    );
  }
}

class TodoTag extends StatelessWidget {
  const TodoTag({super.key, required this.label, this.color = AppColors.white});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: AppTheme.brutalBox(
        color: color,
        borderRadius: AppRadii.pillAll,
        hasShadow: false,
      ),
      child: Text(
        label,
        style: AppTypography.label.copyWith(fontWeight: AppTypography.semiBold),
      ),
    );
  }
}

String filterName(TodoFilter f) => switch (f) {
  TodoFilter.open => 'Chưa xong',
  TodoFilter.done => 'Đã xong',
  TodoFilter.all => 'Tất cả',
};

String categoryName(TodoCategory c) => switch (c) {
  TodoCategory.study => 'Học',
  TodoCategory.assignment => 'Bài tập',
  TodoCategory.exam => 'Thi',
  TodoCategory.personal => 'Cá nhân',
  TodoCategory.other => 'Khác',
};

String priorityName(Priority p) => switch (p) {
  Priority.low => 'Thấp',
  Priority.medium => 'Vừa',
  Priority.high => 'Cao',
};

Color priorityColor(Priority p) => switch (p) {
  Priority.low => AppColors.teal,
  Priority.medium => AppColors.yellow,
  Priority.high => AppColors.coral,
};

String two(int n) => n.toString().padLeft(2, '0');
String dayMonth(DateTime d) => '${two(d.day)}/${two(d.month)}';
String hourMinute(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

String weekdayName(DateTime d) => const [
  'Thứ Hai',
  'Thứ Ba',
  'Thứ Tư',
  'Thứ Năm',
  'Thứ Sáu',
  'Thứ Bảy',
  'Chủ Nhật',
][d.weekday - 1];
