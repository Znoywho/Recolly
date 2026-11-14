import 'package:client/data/data.dart';
import 'package:flutter/widgets.dart';

class RepositoryScope extends InheritedWidget {
  const RepositoryScope({
    super.key,
    required this.repositories,
    required super.child,
  });

  final AppRepositories repositories;

  static AppRepositories of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RepositoryScope>();
    assert(scope != null, 'RepositoryScope is missing above this context.');
    return scope!.repositories;
  }

  @override
  bool updateShouldNotify(RepositoryScope oldWidget) =>
      repositories != oldWidget.repositories;
}
