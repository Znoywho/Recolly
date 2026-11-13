import 'package:client/features/welcome_screens/startscreen.dart';
import 'package:client/widgets/brutal_button.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class Logoscreen extends StatelessWidget {
  const Logoscreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.teal,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: BrutalButton(
            label: "Bắt đầu",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => Startscreen()),
              );
            },
            color: AppColors.green,
          ),
        ),
      ),
      body: SafeArea(
        child: SizedBox.expand(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: const [
                Image(
                  image: AssetImage('assets/splashLogo_original.png'),
                  width: 300,
                  height: 300,
                  fit: BoxFit.cover,
                ),
                Text(
                  'Recolly',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 70,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: .center,
                  selectionColor: AppColors.slate,
                ),
                Text('Học đủ, ngủ đủ'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
