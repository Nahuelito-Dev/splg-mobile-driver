import 'package:flutter/material.dart';

/// Mancha blanca curva de la parte alta de la bienvenida (viewBox 414x448),
/// con la ilustración adentro.
class WelcomeBlob extends StatelessWidget {
  const WelcomeBlob({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return ClipPath(
      clipper: const _BlobClipper(),
      child: Container(
        width: width,
        height: width * 448 / 414,
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(
            width * 0.11, width * 0.2, width * 0.11, width * 0.1),
        child: child,
      ),
    );
  }
}

class _BlobClipper extends CustomClipper<Path> {
  const _BlobClipper();

  @override
  Path getClip(Size size) {
    final sx = size.width / 414;
    final sy = size.height / 448;
    final p = Path()
      ..moveTo(0, 386.5 * sy)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..cubicTo(414 * sx, 143 * sy, 414 * sx, 412.5 * sy, 414 * sx, 412.5 * sy)
      ..cubicTo(333 * sx, 439.5 * sy, 263.7 * sx, 451 * sy, 163 * sx, 446 * sy)
      ..cubicTo(82.4 * sx, 442 * sy, 20.5 * sx, 404.9 * sy, 0, 386.5 * sy)
      ..close();
    return p;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
