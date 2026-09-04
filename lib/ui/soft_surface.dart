import 'package:flutter/material.dart';

import 'soft_theme.dart';

/// The whole visual language, in three words.
///
/// * [raised] — you can press it, or it is a thing you can pick up.
/// * [flat] — you read it.
/// * [inset] — you put something into it (text, sound, a value).
///
/// Every surface *of the page* is one of these three. [floating] is not one
/// of them: it is for the transient overlay that sits above the page rather
/// than being moulded out of it, so it casts a real shadow instead of
/// carrying a lit edge. Only the toast uses it.
enum SoftDepth { raised, flat, inset, floating }

/// A single moulded surface. All depth in the app is drawn by this widget.
class SoftSurface extends StatelessWidget {
  const SoftSurface({
    super.key,
    required this.child,
    this.depth = SoftDepth.raised,
    this.radius = SoftShape.surfaceRadius,
    this.padding = EdgeInsets.zero,
    this.fill,
    this.intensity = 1,
  });

  final Widget child;
  final SoftDepth depth;
  final BorderRadius radius;
  final EdgeInsetsGeometry padding;

  /// Overrides the moulded face — used only by the one accent-filled action.
  final Color? fill;

  /// Scales the shadow for smaller controls. 1 is a page-level surface.
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final p = SoftPalette.of(context);
    final padded = Padding(padding: padding, child: child);

    switch (depth) {
      case SoftDepth.flat:
        return DecoratedBox(
          decoration: BoxDecoration(
            color: fill ?? p.base,
            borderRadius: radius,
          ),
          child: padded,
        );
      case SoftDepth.raised:
        return DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            gradient: fill == null ? p.raisedFace : null,
            borderRadius: radius,
            boxShadow: p.raisedShadow(depth: intensity),
          ),
          child: padded,
        );
      case SoftDepth.floating:
        return DecoratedBox(
          decoration: BoxDecoration(
            color: fill ?? p.faceHigh,
            borderRadius: radius,
            boxShadow: p.floatingShadow,
          ),
          child: padded,
        );
      case SoftDepth.inset:
        return CustomPaint(
          painter: _InsetPainter(
            radius: radius,
            fill: fill ?? p.well,
            light: p.shadowLight,
            dark: p.shadowDark,
            spread: 5 * intensity,
            blur: 7 * intensity,
          ),
          child: padded,
        );
    }
  }
}

/// Flutter has no inner [BoxShadow], so the pressed-in look is painted:
/// clip to the shape, then blur the *outside* of a shifted copy of it so the
/// soft edge falls inward. Two passes, one per light source.
class _InsetPainter extends CustomPainter {
  const _InsetPainter({
    required this.radius,
    required this.fill,
    required this.light,
    required this.dark,
    required this.spread,
    required this.blur,
  });

  final BorderRadius radius;
  final Color fill;
  final Color light;
  final Color dark;
  final double spread;
  final double blur;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = radius.toRRect(Offset.zero & size);
    canvas.drawRRect(rrect, Paint()..color = fill);
    canvas.save();
    canvas.clipRRect(rrect);
    _edge(canvas, rrect, dark, Offset(spread, spread));
    _edge(canvas, rrect, light, Offset(-spread, -spread));
    canvas.restore();
  }

  void _edge(Canvas canvas, RRect rrect, Color color, Offset shift) {
    final outer = Path()
      ..addRect(rrect.outerRect.inflate(blur * 4 + spread * 2));
    final inner = Path()..addRRect(rrect.shift(shift));
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, inner),
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
  }

  @override
  bool shouldRepaint(_InsetPainter old) {
    return old.radius != radius ||
        old.fill != fill ||
        old.light != light ||
        old.dark != dark ||
        old.spread != spread ||
        old.blur != blur;
  }
}

/// A well for text input: an inset surface sized to its field.
class SoftField extends StatelessWidget {
  const SoftField({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(
      horizontal: SoftSpace.lg,
      vertical: SoftSpace.md,
    ),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      depth: SoftDepth.inset,
      radius: SoftShape.insetRadius,
      padding: padding,
      child: child,
    );
  }
}
