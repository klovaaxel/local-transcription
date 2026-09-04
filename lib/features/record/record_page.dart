import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../ui/soft_buttons.dart';
import '../../ui/soft_dates.dart';
import '../../ui/soft_icons.dart';
import '../../ui/soft_theme.dart';
import '../../ui/soft_widgets.dart';

class RecordPage extends StatefulWidget {
  const RecordPage({super.key});

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  var _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _begin();
    });
  }

  Future<void> _begin() async {
    if (_started || !mounted) {
      return;
    }
    final state = context.read<LectureAppState>();
    if (state.active != null) {
      return;
    }
    _started = true;
    try {
      await state.startRecording();
    } catch (_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<LectureAppState>();
    final captions = state.active?.liveCaptions ?? '';
    final listening = state.active != null && !state.busy;
    final live = state.settings.liveCaptionsEnabled;

    return PopScope(
      canPop: false,
      child: SoftPage(
        title: elapsedLine(state.recordElapsed),
        subtitle: Text(
          listening
              ? (live ? 'Lyssnar lokalt' : 'Spelar in lokalt')
              : (state.statusMessage ?? 'Förbereder…'),
        ),
        action: SoftActionBar(
          label: state.busy ? (state.statusMessage ?? 'Väntar…') : 'Stoppa',
          icon: SoftIcons.stop,
          onPressed: state.busy || state.active == null
              ? null
              : () async {
                  try {
                    final session = await state.stopRecording();
                    if (context.mounted) {
                      Navigator.of(context).pop(session);
                    }
                  } catch (_) {}
                },
        ),
        child: ListView(
          padding: softBodyPadding,
          children: [
            HearingMeter(level: state.inputLevel, listening: listening),
            const SizedBox(height: SoftSpace.xl),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    live ? 'Live-text' : 'Text efter lektionen',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: SoftSpace.sm),
                  Text(
                    _bodyText(live: live, captions: captions),
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cloud transcription runs on the finished file, so there is nothing to
  /// show while the lecture is still going.
  static String _bodyText({required bool live, required String captions}) {
    if (!live) {
      return 'Molnet transkriberar efter lektionen. Staplarna ovan rör sig '
          'när mikrofonen hör dig.';
    }
    if (captions.isEmpty) {
      return 'Texten dyker upp när något sagts. Staplarna ovan rör sig när '
          'mikrofonen hör dig.';
    }
    return captions;
  }
}
