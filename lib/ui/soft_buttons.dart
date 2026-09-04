import 'package:flutter/material.dart';

import 'soft_icons.dart';
import 'soft_theme.dart';

/// The app has exactly one button.
///
/// [SoftButtonRole] changes what it means, never how it is built: same
/// height, same radius, same press. Rank comes from the fill, not from a
/// different component.
///
/// * [primary] — the single most important action on the screen.
/// * [quiet] — everything else.
/// * [danger] — destructive, and never placed beside a primary.
enum SoftButtonRole { primary, quiet, danger }

class SoftButton extends StatelessWidget {
  const SoftButton.primary({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.expand = false,
  }) : role = SoftButtonRole.primary;

  const SoftButton.quiet({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.expand = false,
  }) : role = SoftButtonRole.quiet;

  const SoftButton.danger({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.expand = false,
  }) : role = SoftButtonRole.danger;

  final SoftButtonRole role;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  /// Fills the available width. Layout only — the look does not change.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = SoftPalette.of(context);
    final enabled = onPressed != null;

    final content = enabled
        ? switch (role) {
            SoftButtonRole.primary => p.onAccent,
            SoftButtonRole.quiet => p.ink,
            SoftButtonRole.danger => p.danger,
          }
        : p.muted;

    return _Moulded(
      onPressed: onPressed,
      semanticLabel: label,
      radius: SoftShape.controlRadius,
      fill: role == SoftButtonRole.primary && enabled ? p.accent : null,
      minHeight: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SoftSpace.xl),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: content),
            const SizedBox(width: SoftSpace.md),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(color: content),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon-only control for a toolbar slot. Same surface, square target.
class SoftIconButton extends StatelessWidget {
  const SoftIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = SoftPalette.of(context);
    final button = _Moulded(
      onPressed: onPressed,
      semanticLabel: tooltip,
      radius: SoftShape.controlRadius,
      minHeight: 48,
      minWidth: 48,
      child: Icon(icon, size: 20, color: onPressed == null ? p.muted : p.ink),
    );

    // The hover label needs an Overlay, and this button is also used in the
    // app-wide toast, which is mounted beside the Navigator rather than in it.
    // The accessible name comes from _Moulded either way.
    if (Overlay.maybeOf(context) == null) {
      return button;
    }
    return Tooltip(message: tooltip, excludeFromSemantics: true, child: button);
  }
}

/// Leading navigation. A preset of [SoftButton.quiet], not another button.
class SoftBackButton extends StatelessWidget {
  const SoftBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SoftButton.quiet(
      label: 'Tillbaka',
      icon: SoftIcons.back,
      onPressed: () => Navigator.of(context).maybePop(),
    );
  }
}

/// The thumb-zone slot: one primary action, pinned above the home indicator.
///
/// A layout, not a button variant — it hosts a plain [SoftButton.primary].
class SoftActionBar extends StatelessWidget {
  const SoftActionBar({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  /// Height above the bottom inset. The toast reads this to clear the bar.
  static const height = 52.0 + SoftSpace.lg * 2;

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = SoftPalette.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.base,
        boxShadow: [
          // Just enough to lift the bar off scrolling content. A hairline or
          // a hard shadow would read as a seam in a moulded surface.
          BoxShadow(
            color: p.shadowDark.withValues(alpha: p.shadowDark.a * 0.4),
            offset: const Offset(0, -4),
            blurRadius: 24,
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          SoftSpace.gutter,
          SoftSpace.lg,
          SoftSpace.gutter,
          SoftSpace.lg + bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SoftButton.primary(
              label: label,
              icon: icon,
              onPressed: onPressed,
              expand: true,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared press physics: the surface flattens into the page and its lit edge
/// flips, the way a real moulded key does when you push it.
class _Moulded extends StatefulWidget {
  const _Moulded({
    required this.child,
    required this.onPressed,
    required this.semanticLabel,
    required this.radius,
    this.fill,
    this.minHeight = 48,
    this.minWidth = 0,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final BorderRadius radius;
  final Color? fill;
  final double minHeight;
  final double minWidth;

  @override
  State<_Moulded> createState() => _MouldedState();
}

class _MouldedState extends State<_Moulded>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: SoftMotion.press,
    reverseDuration: SoftMotion.press,
  );

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _setPressed(bool pressed) {
    if (!mounted) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _press.value = pressed ? 1 : 0;
      return;
    }
    if (pressed) {
      _press.forward();
    } else {
      _press.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = SoftPalette.of(context);
    final enabled = widget.onPressed != null;

    return AnimatedBuilder(
      animation: _press,
      builder: (context, child) {
        final t = enabled ? _press.value : 0.0;
        final lift = enabled ? 1 - t : 0.0;
        final face = widget.fill == null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(p.faceHigh, p.faceLow, t)!,
                  Color.lerp(p.faceLow, p.faceHigh, t)!,
                ],
              )
            : null;

        return Transform.scale(
          scale: 1 - 0.015 * t,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.fill,
              gradient: face,
              borderRadius: widget.radius,
              boxShadow: enabled
                  ? p.raisedShadow(depth: 0.15 + 0.65 * lift)
                  : null,
            ),
            child: child,
          ),
        );
      },
      child: Material(
        type: MaterialType.transparency,
        borderRadius: widget.radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onPressed,
          onHighlightChanged: _setPressed,
          borderRadius: widget.radius,
          hoverColor: p.ink.withValues(alpha: 0.04),
          focusColor: p.accent.withValues(alpha: 0.12),
          child: Semantics(
            button: true,
            enabled: enabled,
            label: widget.semanticLabel,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: widget.minHeight,
                minWidth: widget.minWidth,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
