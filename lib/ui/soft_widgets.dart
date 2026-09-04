import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'soft_surface.dart';
import 'soft_theme.dart';

/// Padding for every scrollable body in the app. The top gap leaves room for
/// the first card's highlight, which would otherwise be clipped by the
/// scrollable's own bounds; the bottom clears the action bar.
const softBodyPadding = EdgeInsets.fromLTRB(
  SoftSpace.gutter,
  SoftSpace.xl,
  SoftSpace.gutter,
  SoftSpace.huge,
);

/// Every screen in the app is a [SoftPage]. Same safe area, same nav row,
/// same title block, same thumb-zone slot — so nothing has to be re-learned
/// between recording and copying.
class SoftPage extends StatelessWidget {
  const SoftPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.leading,
    this.trailing,
    this.action,
  });

  /// Big line at the top: the screen's name, or the lecture's date.
  final String title;

  /// One quiet line under the title. A widget so a screen can make it
  /// editable (the optional lecture name).
  final Widget? subtitle;

  final Widget? leading;
  final Widget? trailing;

  /// Body. Usually a scrollable; it is centred to a readable measure.
  final Widget child;

  /// The one primary action, pinned above the home indicator.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = SoftPalette.of(context);
    final hasNav = leading != null || trailing != null;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: theme.brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: p.base,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: MediaQuery.paddingOf(context).top + SoftSpace.xl),
            _measure(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SoftSpace.gutter,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasNav)
                      Padding(
                        padding: const EdgeInsets.only(bottom: SoftSpace.lg),
                        child: Row(
                          children: [
                            ?leading,
                            const Spacer(),
                            ?trailing,
                          ],
                        ),
                      ),
                    Text(title, style: theme.textTheme.displaySmall),
                    if (subtitle != null) ...[
                      const SizedBox(height: SoftSpace.sm),
                      DefaultTextStyle(
                        style: theme.textTheme.bodyMedium!.copyWith(
                          color: p.muted,
                        ),
                        child: subtitle!,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: SoftSpace.md),
            Expanded(child: _measure(child: child)),
            ?action,
          ],
        ),
      ),
    );
  }

  Widget _measure({required Widget child}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = lectureContentWidth(constraints.maxWidth);
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: width, child: child),
        );
      },
    );
  }
}

/// A raised surface with the app's standard padding. Lists, sections and the
/// brief are all built from this one card — there is no second card style.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(SoftSpace.xl),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return SoftSurface(padding: padding, child: child);
    }
    return SoftSurface(
      child: Material(
        type: MaterialType.transparency,
        borderRadius: SoftShape.surfaceRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: SoftShape.surfaceRadius,
          hoverColor: SoftPalette.of(context).ink.withValues(alpha: 0.04),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A titled group: quiet label outside, content inside one [SoftCard].
class SoftSection extends StatelessWidget {
  const SoftSection({
    super.key,
    required this.label,
    required this.child,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: SoftSpace.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: SoftSpace.xs),
                Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        const SizedBox(height: SoftSpace.md),
        SoftCard(child: child),
      ],
    );
  }
}

/// One of the three parts of the brief. They stack inside a single card so
/// the teacher reads a letter, not three widgets.
class BriefBlock extends StatelessWidget {
  const BriefBlock({
    super.key,
    required this.heading,
    required this.body,
    this.last = false,
  });

  final String heading;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = SoftPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: theme.textTheme.titleSmall),
        const SizedBox(height: SoftSpace.sm),
        SelectableText(body, style: theme.textTheme.bodyLarge),
        if (!last) ...[
          const SizedBox(height: SoftSpace.xl),
          Divider(height: 1, thickness: 1, color: p.hairline),
          const SizedBox(height: SoftSpace.xl),
        ],
      ],
    );
  }
}

/// Live input level while recording: bars sunk into a well, so the teacher
/// can tell at a glance from across the room that the phone still hears them.
class HearingMeter extends StatelessWidget {
  const HearingMeter({super.key, required this.level, this.listening = true});

  final double level;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = SoftPalette.of(context);
    final status = listening
        ? (level > 0.08 ? 'Hör dig' : 'Väntar på röst…')
        : 'Inte igång';

    return SoftSurface(
      depth: SoftDepth.inset,
      radius: SoftShape.surfaceRadius,
      padding: const EdgeInsets.all(SoftSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(status, style: theme.textTheme.titleMedium)),
              Text(
                listening ? 'Lokalt' : '—',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: SoftSpace.lg),
          SizedBox(
            height: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < 16; i++) ...[
                  if (i > 0) const SizedBox(width: SoftSpace.xs),
                  Expanded(
                    child: _Bar(
                      active: listening && level > (i + 1) / 18,
                      accent: p.accent,
                      track: p.muted.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.active, required this.accent, required this.track});

  final bool active;
  final Color accent;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      height: active ? 44 : 8,
      decoration: BoxDecoration(
        color: active ? accent : track,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
