import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/lecture_session.dart';
import '../../data/session_entry.dart';
import '../../ui/soft_buttons.dart';
import '../../ui/soft_dates.dart';
import '../../ui/soft_icons.dart';
import '../../ui/soft_theme.dart';
import '../../ui/soft_widgets.dart';
import '../record/record_page.dart';
import '../sessions/session_page.dart';
import '../settings/settings_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LectureAppState>();

    return SoftPage(
      title: 'Föreläsningar',
      subtitle: const Text('Spela in. Kopiera underlaget efteråt.'),
      trailing: SoftIconButton(
        tooltip: 'Inställningar',
        icon: SoftIcons.settings,
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
        },
      ),
      action: SoftActionBar(
        label: state.busy ? 'Förbereder…' : 'Spela in',
        icon: SoftIcons.mic,
        onPressed: state.busy ? null : () => _record(context),
      ),
      child: state.sessions.isEmpty
          ? const _EmptyLectures()
          : ListView.separated(
              padding: softBodyPadding,
              itemCount: state.sessions.length,
              separatorBuilder: (_, _) => const SizedBox(height: SoftSpace.md),
              itemBuilder: (context, index) {
                return _LectureCard(entry: state.sessions[index]);
              },
            ),
    );
  }

  Future<void> _record(BuildContext context) async {
    final session = await Navigator.of(context).push<LectureSession?>(
      MaterialPageRoute(builder: (_) => const RecordPage()),
    );
    if (session != null && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SessionPage(sessionId: session.id),
        ),
      );
    }
  }
}

class _EmptyLectures extends StatelessWidget {
  const _EmptyLectures();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: softBodyPadding,
      child: SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ingen lektion inspelad än',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: SoftSpace.sm),
            Text(
              'Starta en inspelning — telefonen lyssnar lokalt medan du '
              'undervisar.',
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _LectureCard extends StatelessWidget {
  const _LectureCard({required this.entry});

  final SessionEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = SoftPalette.of(context);
    // The preview is cut from the summary, or from the transcript when there
    // is no brief yet, when the row was written -- see [SessionEntry]. Keeping
    // that here instead would mean reading every lecture's full text to draw
    // the list.
    final subtitle = entry.preview.trim().isEmpty
        ? _statusLabel(entry.status)
        : entry.preview;
    final name = entry.cachedTitle;
    final date = lectureDateLine(entry.startedAt);
    final clock = lectureClock(entry.startedAt);

    return SoftCard(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SessionPage(sessionId: entry.id),
          ),
        );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name ?? date, style: theme.textTheme.titleMedium),
                const SizedBox(height: SoftSpace.xs),
                Text(
                  name == null ? clock : '$date · $clock',
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(height: SoftSpace.md),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: SoftSpace.md),
          Padding(
            padding: const EdgeInsets.only(top: SoftSpace.xs),
            child: Icon(SoftIcons.chevronRight, size: 20, color: p.muted),
          ),
        ],
      ),
    );
  }

  /// Only reached when [SessionEntry.preview] is empty, which means neither
  /// the brief nor the transcript had text to preview -- so a ready lecture
  /// here is one with nothing to write a brief from yet.
  String _statusLabel(SessionStatus status) {
    return switch (status) {
      SessionStatus.recording => 'Spelar in',
      SessionStatus.transcribing => 'Transkriberar',
      SessionStatus.summarizing => 'Skriver underlag',
      SessionStatus.ready => 'Redo att skriva underlag',
      SessionStatus.interrupted => 'Avbruten',
    };
  }
}
