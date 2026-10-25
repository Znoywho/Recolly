import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import 'core/di/repository_scope.dart';
import 'core/theme/theme.dart';
import 'features/theme_gallery/theme_gallery_page.dart';

class RecollyApp extends StatefulWidget {
  const RecollyApp({super.key, this.repositories});

  final AppRepositories? repositories;

  @override
  State<RecollyApp> createState() => _RecollyAppState();
}

class _RecollyAppState extends State<RecollyApp> {
  late final AppRepositories _repositories =
      widget.repositories ?? AppRepositories.fromEnvironment();

  @override
  Widget build(BuildContext context) {
    return RepositoryScope(
      repositories: _repositories,
      child: MaterialApp(
        title: 'Recolly',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const ThemeGalleryPage(),
      ),
    );
  }
}
