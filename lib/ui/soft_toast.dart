import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../asr/model_downloader.dart';
import 'soft_buttons.dart';
import 'soft_icons.dart';
import 'soft_surface.dart';
import 'soft_theme.dart';

/// App-wide overlay for slow work and idle notices.
///
/// Floats above the thumb-zone bar instead of inserting a strip that shoves
/// the page down. One host in `LectureApp`, so every route gets it.
class SoftToastLayer extends StatelessWidget {
  const SoftToastLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LectureAppState>();
    final working = state.busy || state.downloadProgress != null;
    final message = state.statusMessage;
    final showNotice = !working && message != null && message.trim().isNotEmpty;

    // One height on every screen, clearing the tallest case (a screen with an
    // action bar) with a gutter to spare. Toasts that move around between
    // routes read as a different thing each time.
    final lift =
        SoftActionBar.height +
        SoftSpace.lg +
        MediaQuery.paddingOf(context).bottom +
        MediaQuery.viewInsetsOf(context).bottom;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(SoftSpace.lg, 0, SoftSpace.lg, lift),
        child: SoftToast(
          visible: working || showNotice,
          message: message ?? 'Arbetar…',
          progress: state.downloadProgress,
          working: working,
          sticky: state.statusIsError,
          onDismiss: showNotice ? state.clearStatus : null,
        ),
      ),
    );
  }
}

class SoftToast extends StatefulWidget {
  const SoftToast({
    super.key,
    required this.visible,
    required this.message,
    required this.working,
    this.sticky = false,
    this.progress,
    this.onDismiss,
  });

  final bool visible;
  final String message;
  final bool working;

  /// A failure. It waits to be read instead of clearing itself.
  final bool sticky;
  final DownloadProgress? progress;
  final VoidCallback? onDismiss;

  @override
  State<SoftToast> createState() => _SoftToastState();
}

class _SoftToastState extends State<SoftToast>
    with SingleTickerProviderStateMixin {
  /// How long a confirmation stays before it clears itself. Work messages and
  /// errors are not on a clock — those stay until the work ends or the
  /// teacher dismisses them.
  static const _noticeLife = Duration(seconds: 4);

  Timer? _life;
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;

  var _message = '';
  DownloadProgress? _progress;
  var _working = false;
  VoidCallback? _onDismiss;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: SoftMotion.enter,
      reverseDuration: SoftMotion.exit,
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: SoftMotion.easeOut,
      reverseCurve: SoftMotion.easeOut,
    );
    _opacity = curve;
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(curve);
    _scale = Tween<double>(begin: 0.96, end: 1).animate(curve);
    _capture();
    if (widget.visible) {
      _controller.value = 1;
      _restartLife();
    }
  }

  @override
  void didUpdateWidget(SoftToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible) {
      final changed = widget.message != oldWidget.message;
      _capture();
      _controller.forward();
      if (changed || !oldWidget.visible) {
        _restartLife();
      }
    } else if (oldWidget.visible) {
      _life?.cancel();
      _controller.reverse();
    }
  }

  /// Only a plain confirmation is on a clock. Work has no known end, and a
  /// failure stays until the teacher has seen it.
  void _restartLife() {
    _life?.cancel();
    final dismiss = widget.onDismiss;
    if (widget.working || widget.sticky || dismiss == null) {
      return;
    }
    _life = Timer(_noticeLife, () {
      if (mounted && widget.visible && !widget.working) {
        dismiss();
      }
    });
  }

  void _capture() {
    _message = widget.message;
    _progress = widget.progress;
    _working = widget.working;
    _onDismiss = widget.onDismiss;
  }

  @override
  void dispose() {
    _life?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final gone =
            !widget.visible &&
            (_controller.isDismissed || _controller.value == 0);
        if (gone) {
          return const SizedBox.shrink();
        }
        final plate = child!;
        if (MediaQuery.disableAnimationsOf(context)) {
          return Opacity(opacity: _opacity.value, child: plate);
        }
        return Opacity(
          opacity: _opacity.value,
          child: SlideTransition(
            position: _slide,
            child: Transform.scale(
              scale: _scale.value,
              alignment: Alignment.bottomCenter,
              child: plate,
            ),
          ),
        );
      },
      child: _Plate(
        message: widget.visible ? widget.message : _message,
        progress: widget.visible ? widget.progress : _progress,
        working: widget.visible ? widget.working : _working,
        onDismiss: widget.visible ? widget.onDismiss : _onDismiss,
      ),
    );
  }
}

class _Plate extends StatelessWidget {
  const _Plate({
    required this.message,
    required this.working,
    this.progress,
    this.onDismiss,
  });

  final String message;
  final bool working;
  final DownloadProgress? progress;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = SoftPalette.of(context);
    final fraction = progress?.fraction;
    final detail = progress == null
        ? null
        : [
            progress!.label,
            if (progress!.total > 0)
              '${_mb(progress!.received)} / ${_mb(progress!.total)} MB',
          ].join(' · ');

    final body = IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message, style: theme.textTheme.titleMedium),
          if (detail != null) ...[
            const SizedBox(height: SoftSpace.xs),
            Text(detail, style: theme.textTheme.bodySmall),
          ],
          if (working) ...[
            const SizedBox(height: SoftSpace.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 5,
                backgroundColor: p.well,
              ),
            ),
          ],
        ],
      ),
    );

    final plate = SoftSurface(
      depth: SoftDepth.floating,
      radius: SoftShape.controlRadius,
      padding: const EdgeInsets.symmetric(
        horizontal: SoftSpace.xl,
        vertical: SoftSpace.lg,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (working) ...[
            Padding(
              // Optical: line the spinner up with the message's cap height.
              padding: const EdgeInsets.only(top: SoftSpace.xs),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: fraction,
                ),
              ),
            ),
            const SizedBox(width: SoftSpace.md),
          ],
          Flexible(child: body),
          if (onDismiss != null) ...[
            const SizedBox(width: SoftSpace.lg),
            Icon(SoftIcons.cancel, size: 18, color: p.muted),
          ],
        ],
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Semantics(
        container: true,
        liveRegion: true,
        label: message,
        button: onDismiss != null,
        child: onDismiss == null
            ? plate
            : GestureDetector(
                key: const Key('toast-dismiss'),
                onTap: onDismiss,
                behavior: HitTestBehavior.opaque,
                child: plate,
              ),
      ),
    );
  }

  static String _mb(int bytes) => (bytes / 1000000).toStringAsFixed(0);
}
