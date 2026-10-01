import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_state.dart';
import '../../data/lecture_session.dart';
import '../../summarize/newsletter.dart';
import '../../ui/soft_buttons.dart';
import '../../ui/soft_dates.dart';
import '../../ui/soft_icons.dart';
import '../../ui/soft_theme.dart';
import '../../ui/soft_widgets.dart';

class SessionPage extends StatefulWidget {
  const SessionPage({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  var _askedForBrief = false;
  LectureSession? _session;

  /// The transcript and the brief live in the session's own file, not in the
  /// manifest the home screen reads, so opening a lecture costs one file read.
  /// Until it lands the page has nothing to show and, importantly, nothing that
  /// looks like a lecture ready for a brief -- asking for one against an
  /// unloaded session would start work on an empty transcript and never fire
  /// again, because the guard sets `_askedForBrief` either way.
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final state = context.read<LectureAppState>();
    // A failed load leaves `_session` null, which is what the page below
    // already reports for a lecture it cannot find.
    try {
      _session = await state.loadSession(widget.sessionId);
    } on Object {
      _session = null;
    }
    if (mounted) {
      setState(() {});
    }
  }

  String _briefText(LectureSession session) {
    final when =
        '${lectureDateLine(session.startedAt)}, '
        '${lectureClock(session.startedAt)}';
    final name = session.autoTitle;
    final body = session.summary?.toMarkdown() ?? 'Ingen sammanfattning ännu.';
    if (name == null) {
      return '$when\n\n$body';
    }
    return '$name\n$when\n\n$body';
  }

  Future<void> _copyBrief(LectureAppState state, LectureSession session) async {
    await Clipboard.setData(ClipboardData(text: _briefText(session)));
    if (mounted) {
      state.notice('Kopierat. Klistra in i skolplattformen.');
    }
  }

  /// Linux has no share sheet: `share_plus` opens a `mailto:` link there and
  /// throws when the desktop has no mail handler. Left unawaited that became an
  /// unhandled async error and the button looked broken. Kopiera is the way out.
  Future<void> _shareBrief(
    LectureAppState state,
    LectureSession session,
  ) async {
    final summary = session.summary;
    if (summary == null) {
      return;
    }
    try {
      await SharePlus.instance.share(ShareParams(text: summary.toMarkdown()));
    } catch (_) {
      if (mounted) {
        state.notice('Kunde inte dela. Använd Kopiera i stället.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LectureAppState>();
    final session = _session;
    if (session == null) {
      return SoftPage(
        title: 'Föreläsning',
        leading: const SoftBackButton(),
        child: Center(
          child: Text(
            'Passet saknas.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    if (!_askedForBrief &&
        session.summary == null &&
        session.displayTranscript.trim().isNotEmpty &&
        !state.busy &&
        session.error == null) {
      _askedForBrief = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        state.summarizeSession(session).ignore();
      });
    }

    final wide = MediaQuery.sizeOf(context).width >= 900;
    final name = session.autoTitle;
    final date = lectureDateLine(session.startedAt);
    final clock = lectureClock(session.startedAt);

    final brief = _BriefPane(
      session: session,
      actions: _briefActions(state, session),
      briefPhase: state.briefPhase,
      briefDone: state.briefDone,
      briefTotal: state.briefTotal,
      footer: _deleteControl(state, session),
    );
    final transcript = _TranscriptPane(session: session);

    return SoftPage(
      title: name ?? date,
      subtitle: Text(name == null ? clock : '$date · $clock'),
      leading: const SoftBackButton(),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      SoftSpace.gutter,
                      SoftSpace.xl,
                      SoftSpace.md,
                      SoftSpace.huge,
                    ),
                    child: brief,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      SoftSpace.md,
                      SoftSpace.xl,
                      SoftSpace.gutter,
                      SoftSpace.huge,
                    ),
                    child: transcript,
                  ),
                ),
              ],
            )
          : ListView(
              padding: softBodyPadding,
              children: [
                brief,
                const SizedBox(height: SoftSpace.xl),
                transcript,
              ],
            ),
    );
  }

  /// What you do with the brief. Kopiera and Dela are peers — same size, same
  /// row — because they are the same job with two destinations. Before there
  /// is a brief, the same slot holds the one action that makes one.
  Widget _briefActions(LectureAppState state, LectureSession session) {
    // While a brief runs, stopping it is the only action worth offering: the
    // card is a placeholder, so there is nothing to copy yet, and the wait can
    // be minutes on a phone. A screen whose whole job is one action says one.
    if (state.briefRunning) {
      return SoftButton.quiet(
        label: 'Avbryt underlag',
        icon: SoftIcons.cancel,
        onPressed: state.cancelBrief,
      );
    }
    if (session.summary == null) {
      return SoftButton.primary(
        label: state.busy ? 'Skriver underlag…' : 'Skriv underlag',
        icon: SoftIcons.brief,
        onPressed: state.busy
            ? null
            : () async {
                try {
                  await state.summarizeSession(session);
                } catch (_) {}
              },
      );
    }
    return Wrap(
      spacing: SoftSpace.md,
      runSpacing: SoftSpace.md,
      children: [
        SoftButton.primary(
          label: 'Kopiera',
          icon: SoftIcons.copy,
          onPressed: state.busy ? null : () => _copyBrief(state, session),
        ),
        SoftButton.quiet(
          label: 'Dela',
          icon: SoftIcons.share,
          onPressed: state.busy ? null : () => _shareBrief(state, session),
        ),
      ],
    );
  }

  Widget _deleteControl(LectureAppState state, LectureSession session) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SoftButton.danger(
        label: 'Ta bort',
        icon: SoftIcons.delete,
        onPressed: state.busy
            ? null
            : () => _confirmDelete(context, state, session),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    LectureAppState state,
    LectureSession session,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Ta bort lektionen'),
          content: const Text(
            'Underlaget och transkriptionen raderas från enheten.',
          ),
          actionsPadding: const EdgeInsets.fromLTRB(
            SoftSpace.xl,
            0,
            SoftSpace.xl,
            SoftSpace.xl,
          ),
          actions: [
            SoftButton.quiet(
              label: 'Avbryt',
              icon: SoftIcons.cancel,
              onPressed: () => Navigator.pop(context, false),
            ),
            SoftButton.danger(
              label: 'Ta bort',
              icon: SoftIcons.delete,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        );
      },
    );
    if (ok == true && context.mounted) {
      await state.deleteSession(session);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}

class _BriefPane extends StatelessWidget {
  const _BriefPane({
    required this.session,
    required this.actions,
    required this.briefPhase,
    required this.briefDone,
    required this.briefTotal,
    this.footer,
  });

  final LectureSession session;
  final Widget actions;
  final Widget? footer;

  /// What the brief is doing, if one is running. Non-null replaces the
  /// placeholder text with something that actually moves.
  final String? briefPhase;
  final int briefDone;
  final int briefTotal;

  /// Says which of the slow phases this is, in the teacher's terms. The wait
  /// is mostly a multi-gigabyte download the first time and a decode the
  /// others, and "Skriver underlag…" covers both equally badly.
  String get _phaseLine {
    switch (briefPhase) {
      case 'startar':
        return 'Startar…';
      case 'hämtar modell':
        return 'Hämtar modellen. Det kan ta en stund första gången.';
      case 'mäter hastighet':
        return 'Mäter modellens hastighet…';
      case 'laddar modell':
        return 'Laddar modellen…';
      default:
        // The decode. A one-chunk brief reports 1/1, which is not progress,
        // so fall back to the plain line rather than a frozen counter.
        return briefTotal > 1
            ? 'Skriver underlag ($briefDone av $briefTotal)…'
            : 'Skriver underlag…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = SoftPalette.of(context);
    final summary = session.summary;
    final pending = briefPhase != null
        ? _phaseLine
        : 'Underlaget skrivs när transkriptionen är klar.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (session.error != null) ...[
          SoftCard(
            child: Text(
              session.error!,
              style: theme.textTheme.bodyMedium?.copyWith(color: p.danger),
            ),
          ),
          const SizedBox(height: SoftSpace.md),
        ],
        if (session.status == SessionStatus.interrupted) ...[
          SoftCard(
            child: Text(
              // Not an error: the audio and whatever was said before the app
              // died are still here. What never finished is the work behind it,
              // and which work is decided by what survived.
              session.audioPath == null && session.displayTranscript.isEmpty
                  ? 'Inspelningen avbröts och inget ljud sparades.'
                  : 'Inspelningen avbröts. Det som sagdes finns kvar nedan.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: SoftSpace.md),
        ],
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (summary != null && summary.sections.isNotEmpty)
                for (var i = 0; i < summary.sections.length; i++)
                  BriefBlock(
                    heading: summary.sections[i].heading,
                    body: summary.sections[i].body,
                    last: i == summary.sections.length - 1,
                  )
              else
                for (
                  var i = 0;
                  i < NewsletterSummary.defaultHeadings.length;
                  i++
                )
                  BriefBlock(
                    heading: NewsletterSummary.defaultHeadings[i],
                    body: pending,
                    last: i == NewsletterSummary.defaultHeadings.length - 1,
                  ),
            ],
          ),
        ),
        const SizedBox(height: SoftSpace.lg),
        Align(alignment: Alignment.centerLeft, child: actions),
        if (footer != null) ...[
          const SizedBox(height: SoftSpace.huge),
          footer!,
        ],
      ],
    );
  }
}

/// The transcript is a check on the brief, not something to edit. It is read
/// only — selectable so a line can be copied, never typed over. The one thing
/// that can change it is running the speech model again.
class _TranscriptPane extends StatelessWidget {
  const _TranscriptPane({required this.session});

  final LectureSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = SoftPalette.of(context);
    final state = context.watch<LectureAppState>();
    final text = session.displayTranscript.trim();

    return SoftSection(
      label: 'Transkription',
      subtitle: 'En kontroll av underlaget. Den här texten publiceras inte.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (text.isEmpty)
            Text(
              'Ingen text ännu.',
              style: theme.textTheme.bodyMedium?.copyWith(color: p.muted),
            )
          else
            SelectableText(text, style: theme.textTheme.bodyMedium),
          const SizedBox(height: SoftSpace.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: SoftButton.quiet(
              label: 'Transkribera om',
              icon: SoftIcons.retranscribe,
              onPressed: state.busy || session.audioPath == null
                  ? null
                  : () async {
                      try {
                        await state.transcribeSession(session);
                      } catch (_) {}
                    },
            ),
          ),
        ],
      ),
    );
  }
}
