import 'package:client/data/data.dart';
import 'package:client/features/welcome_screens/logoscreen.dart';
import 'package:flutter/material.dart';
import 'package:client/features/welcome_screens/startscreen.dart';

import 'core/di/repository_scope.dart';
import 'core/theme/app_theme.dart';
import 'features/theme_gallery/theme_gallery_page.dart';
import 'features/calendar/calendar_page_demo.dart';

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
        home: const Logoscreen(),
      ),
    );
  }
}
