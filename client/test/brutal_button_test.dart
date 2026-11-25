import 'package:client/core/theme/app_theme.dart';
import 'package:client/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Offset _buttonTravel(WidgetTester tester, {Type buttonType = BrutalButton}) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byType(buttonType),
      matching: find.byType(AnimatedContainer),
    ),
  );
  final translation = container.transform!.getTranslation();
  return Offset(translation.x, translation.y);
}

void main() {
  testWidgets('a quick tap still shows the pressed state and fires onPressed', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: BrutalButton(label: 'Tiếp tục', onPressed: () => taps++),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Tiếp tục')),
    );
    await tester.pump();
    expect(_buttonTravel(tester), AppShadows.offset);

    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pump();
    expect(taps, 1);
    expect(_buttonTravel(tester), AppShadows.offset);

    await tester.pump(const Duration(milliseconds: 100));
    expect(_buttonTravel(tester), Offset.zero);
  });

  testWidgets('BrutalIconButton also sinks on a quick tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: BrutalIconButton(
              icon: Icons.arrow_back_rounded,
              onPressed: () => taps++,
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(BrutalIconButton)),
    );
    await tester.pump();
    expect(
      _buttonTravel(tester, buttonType: BrutalIconButton),
      AppShadows.offset,
    );

    await gesture.up();
    await tester.pump();
    expect(taps, 1);
    expect(
      _buttonTravel(tester, buttonType: BrutalIconButton),
      AppShadows.offset,
    );

    await tester.pump(const Duration(milliseconds: 100));
    expect(_buttonTravel(tester, buttonType: BrutalIconButton), Offset.zero);
  });

  testWidgets('a disabled button never sinks', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(child: BrutalButton(label: 'Khóa', onPressed: null)),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Khóa')),
    );
    await tester.pump();
    expect(_buttonTravel(tester), Offset.zero);
    await gesture.up();
  });
}
