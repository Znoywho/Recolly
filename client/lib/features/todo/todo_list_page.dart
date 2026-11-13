import 'package:client/core/di/repository_scope.dart';
import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'todo_form_page.dart';

class TodoListPage extends StatefulWidget {
  const TodoListPage({super.key});

  @override
  State<TodoListPage> createState() => _TodoListPageState();
}

class _TodoListPageState extends State<TodoListPage> {
  List<Todo> todos = [];
  bool loading = true;
  String? error;

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
        title: const Text('Xoá việc này?'),
        content: Text(todo.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá'),
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
      showError('Không xoá được, thử lại nhé');
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

  void showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // Split todos into groups by deadline. Done ones go last.
  Map<String, List<Todo>> groupTodos() {
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day + 1);
    final groups = <String, List<Todo>>{
      'Quá hạn': [],
      'Hôm nay': [],
      'Sắp tới': [],
      'Không có hạn': [],
      'Đã xong': [],
    };
    for (final t in todos) {
      final d = t.deadlineAt?.toLocal();
      if (t.status == TodoStatus.done) {
        groups['Đã xong']!.add(t);
      } else if (d == null) {
        groups['Không có hạn']!.add(t);
      } else if (d.isBefore(now)) {
        groups['Quá hạn']!.add(t);
      } else if (d.isBefore(endOfToday)) {
        groups['Hôm nay']!.add(t);
      } else {
        groups['Sắp tới']!.add(t);
      }
    }
    groups.removeWhere((key, list) => list.isEmpty);
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Việc cần làm')),
      floatingActionButton: BrutalIconButton(
        icon: Icons.add,
        color: AppColors.green,
        size: 56,
        onPressed: () => openForm(),
      ),
      body: buildBody(),
    );
  }

  Widget buildBody() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
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
        ),
      );
    }
    if (todos.isEmpty) {
      return const Center(
        child: Text(
          'Chưa có việc nào. Bấm + để thêm nhé!',
          style: AppTypography.body,
        ),
      );
    }

    final groups = groupTodos();
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.whitespace,
        ),
        children: [
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.sm,
                bottom: AppSpacing.xs,
              ),
              child: Text(
                '${entry.key} (${entry.value.length})',
                style: AppTypography.subtitle,
              ),
            ),
            for (final todo in entry.value)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Dismissible(
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
                ),
              ),
          ],
        ],
      ),
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
      child: BrutalCard(
        color: done ? AppColors.cream : AppColors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Checkbox(value: done, onChanged: (_) => onToggle()),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    todo.title,
                    style: AppTypography.body.copyWith(
                      fontWeight: AppTypography.semiBold,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(subtitleText(), style: AppTypography.caption),
                ],
              ),
            ),
            if (todo.priority == Priority.high && !done)
              const Padding(
                padding: EdgeInsets.only(right: AppSpacing.xs),
                child: Icon(Icons.priority_high, color: AppColors.coral),
              ),
          ],
        ),
      ),
    );
  }

  String subtitleText() {
    final parts = <String>[categoryName(todo.category)];
    final d = todo.deadlineAt?.toLocal();
    if (d != null) {
      String two(int n) => n.toString().padLeft(2, '0');
      parts.add('Hạn ${two(d.hour)}:${two(d.minute)} ${two(d.day)}/${two(d.month)}');
    }
    if (todo.estimatedMinutes != null) {
      parts.add('~${todo.estimatedMinutes} phút');
    }
    return parts.join(' · ');
  }
}

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
