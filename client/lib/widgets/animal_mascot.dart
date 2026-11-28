import 'dart:math' as math;

import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// The four sleep animals drawn as mascots. Lion / bear / wolf are the
/// chronotypes; dolphin is the light-sleeper flag (`sleep_concern`).
enum MascotAnimal {
  lion('Sư tử'),
  bear('Gấu'),
  wolf('Sói'),
  dolphin('Cá heo');

  const MascotAnimal(this.displayName);

  final String displayName;

  /// Mascot for a chronotype.
  static MascotAnimal of(Chronotype chronotype) => switch (chronotype) {
    Chronotype.lion => MascotAnimal.lion,
    Chronotype.bear => MascotAnimal.bear,
    Chronotype.wolf => MascotAnimal.wolf,
  };
}

/// A neo-brutalist animal face (thick ink outline, flat colours) drawn in
/// code, so the app needs no image assets for it.
class AnimalMascot extends StatelessWidget {
  const AnimalMascot({super.key, required this.animal, this.size = 96});

  final MascotAnimal animal;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: animal.displayName,
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: _MascotPainter(animal),
      ),
    );
  }
}

/// Paints one animal on a 100×100 grid scaled to the widget size.
class _MascotPainter extends CustomPainter {
  _MascotPainter(this.animal);

  final MascotAnimal animal;

  static const _lionMane = Color(0xFFE8A33D);
  static const _bearFur = Color(0xFFB98552);
  static const _muzzle = Color(0xFFF6E7C8);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    switch (animal) {
      case MascotAnimal.lion:
        _paintLion(canvas);
      case MascotAnimal.bear:
        _paintBear(canvas);
      case MascotAnimal.wolf:
        _paintWolf(canvas);
      case MascotAnimal.dolphin:
        _paintDolphin(canvas);
    }
  }

  // Fills [path] with [color], then outlines it in ink: the brutalist look.
  void _shape(Canvas canvas, Path path, Color color, {double stroke = 3.5}) {
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  Path _circle(double x, double y, double r) =>
      Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: r));

  // Two dot eyes, a nose and a small smile shared by the land animals.
  void _paintFace(Canvas canvas, {double eyeY = 48, double noseY = 62}) {
    final ink = Paint()..color = AppColors.ink;
    canvas.drawCircle(Offset(39, eyeY), 4, ink);
    canvas.drawCircle(Offset(61, eyeY), 4, ink);
    canvas.drawPath(
      Path()
        ..moveTo(45, noseY)
        ..lineTo(55, noseY)
        ..lineTo(50, noseY + 6)
        ..close(),
      ink,
    );
    canvas.drawPath(
      Path()
        ..moveTo(42, noseY + 10)
        ..quadraticBezierTo(50, noseY + 16, 58, noseY + 10),
      Paint()
        ..color = AppColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintLion(Canvas canvas) {
    // Mane: a ring of 12 round tufts behind the face.
    final mane = Path();
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      mane.addOval(
        Rect.fromCircle(
          center: Offset(50 + 34 * math.cos(a), 54 + 34 * math.sin(a)),
          radius: 13,
        ),
      );
    }
    _shape(canvas, mane, _lionMane);
    _shape(canvas, _circle(50, 54, 31), AppColors.yellow);
    _shape(canvas, _circle(50, 68, 13), _muzzle, stroke: 3);
    _paintFace(canvas, eyeY: 47);
  }

  void _paintBear(Canvas canvas) {
    _shape(canvas, _circle(24, 28, 13), _bearFur);
    _shape(canvas, _circle(76, 28, 13), _bearFur);
    _shape(canvas, _circle(50, 56, 36), _bearFur);
    _shape(canvas, _circle(50, 68, 14), _muzzle, stroke: 3);
    _paintFace(canvas, eyeY: 50);
  }

  void _paintWolf(Canvas canvas) {
    Path ear(double tipX, double baseLeft, double baseRight) => Path()
      ..moveTo(baseLeft, 40)
      ..lineTo(tipX, 6)
      ..lineTo(baseRight, 36)
      ..close();
    _shape(canvas, ear(22, 14, 42), AppColors.slate);
    _shape(canvas, ear(78, 58, 86), AppColors.slate);
    final head = Path()
      ..moveTo(12, 40)
      ..quadraticBezierTo(50, 14, 88, 40)
      ..quadraticBezierTo(92, 70, 50, 94)
      ..quadraticBezierTo(8, 70, 12, 40)
      ..close();
    _shape(canvas, head, AppColors.slate);
    final snout = Path()
      ..moveTo(36, 60)
      ..quadraticBezierTo(50, 52, 64, 60)
      ..quadraticBezierTo(60, 84, 50, 88)
      ..quadraticBezierTo(40, 84, 36, 60)
      ..close();
    _shape(canvas, snout, AppColors.white, stroke: 3);
    final white = Paint()..color = AppColors.white;
    canvas.drawCircle(const Offset(37, 48), 6, white);
    canvas.drawCircle(const Offset(63, 48), 6, white);
    _paintFace(canvas, eyeY: 48, noseY: 64);
  }

  void _paintDolphin(Canvas canvas) {
    final fin = Path()
      ..moveTo(44, 30)
      ..quadraticBezierTo(50, 10, 64, 12)
      ..quadraticBezierTo(58, 22, 60, 32)
      ..close();
    _shape(canvas, fin, AppColors.teal);
    final tail = Path()
      ..moveTo(18, 52)
      ..lineTo(4, 40)
      ..lineTo(8, 60)
      ..lineTo(4, 78)
      ..lineTo(20, 66)
      ..close();
    _shape(canvas, tail, AppColors.teal);
    final body = Path()
      ..moveTo(16, 60)
      ..quadraticBezierTo(30, 26, 66, 30)
      ..quadraticBezierTo(86, 34, 96, 56)
      ..quadraticBezierTo(84, 62, 74, 62)
      ..quadraticBezierTo(46, 82, 16, 60)
      ..close();
    _shape(canvas, body, AppColors.teal);
    final belly = Path()
      ..moveTo(40, 66)
      ..quadraticBezierTo(60, 70, 74, 62)
      ..quadraticBezierTo(58, 78, 40, 66)
      ..close();
    _shape(canvas, belly, AppColors.white, stroke: 2.5);
    canvas.drawCircle(const Offset(74, 46), 4, Paint()..color = AppColors.ink);
  }

  @override
  bool shouldRepaint(_MascotPainter oldDelegate) =>
      oldDelegate.animal != animal;
}
