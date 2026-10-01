// TEMPORARY baseline harness -- deleted once the manifest change is verified.
//
// Renders the home screen exactly as it looked BEFORE `SessionEntry` took over
// the card: the card widget below is the pre-change `_LectureCard` copied
// verbatim out of lib/features/home/home_page.dart, inside the same `SoftPage`
// chrome the page has always used, with the fixtures from
// test/preview/screens_preview.dart. Run it before and after the change and
// the two PNGs must be byte-identical.
//
//   flutter test test/preview/home_baseline.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/data/lecture_session.dart';
import 'package:lecture_local/summarize/newsletter.dart';
import 'package:lecture_local/ui/soft_buttons.dart';
import 'package:lecture_local/ui/soft_dates.dart';
import 'package:lecture_local/ui/soft_icons.dart';
import 'package:lecture_local/ui/soft_theme.dart';
import 'package:lecture_local/ui/soft_widgets.dart';

final outDir = Directory('build/preview')..createSync(recursive: true);

LectureSession _ready() => LectureSession(
  id: 's1',
  startedAt: DateTime(2026, 9, 1, 10, 15),
  transcript:
      'Idag gick vi igenom unionsupplösningen 1905 och varför Norge lämnade '
      'unionen. Vi tittade också på Karlstadskonventionen.',
  summary: NewsletterSummary.legacy(
    discussed:
        'Unionsupplösningen 1905: bakgrunden, konsulatfrågan och '
        'Karlstadskonventionen. Vi läste källtexten på sidan 118.',
    decided:
        'Prov på fredag den 12 september. Inlämning av källkritikuppgiften '
        'på torsdag.',
    absentees:
        'Läs kapitel 4 och gör uppgift 3–5. Hör av dig om du behöver '
        'källtexten digitalt.',
  ),
);

LectureSession _fresh() => LectureSession(
  id: 's2',
  startedAt: DateTime(2026, 8, 28, 13, 30),
  transcript: 'Repetition inför provet, genomgång av kapitel 3.',
);

/// The pre-change home list, verbatim.
class _BaselineHome extends StatelessWidget {
  const _BaselineHome(this.sessions);

  final List<LectureSession> sessions;

  @override
  Widget build(BuildContext context) {
    return SoftPage(
      title: 'Föreläsningar',
      subtitle: const Text('Spela in. Kopiera underlaget efteråt.'),
      trailing: SoftIconButton(
        tooltip: 'Inställningar',
        icon: SoftIcons.settings,
        onPressed: () {},
      ),
      action: SoftActionBar(
        label: 'Spela in',
        icon: SoftIcons.mic,
        onPressed: () {},
      ),
      child: ListView.separated(
        padding: softBodyPadding,
        itemCount: sessions.length,
        separatorBuilder: (_, _) => const SizedBox(height: SoftSpace.md),
        itemBuilder: (context, index) => _BaselineCard(session: sessions[index]),
      ),
    );
  }
}

/// Verbatim copy of the pre-change `_LectureCard`.
class _BaselineCard extends StatelessWidget {
  const _BaselineCard({required this.session});

  final LectureSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = SoftPalette.of(context);
    final preview = session.summary?.discussed ?? session.displayTranscript;
    final subtitle = preview.trim().isEmpty
        ? _statusLabel(session)
        : (preview.length > 110 ? '${preview.substring(0, 110)}…' : preview);
    final name = session.autoTitle;
    final date = lectureDateLine(session.startedAt);
    final clock = lectureClock(session.startedAt);

    return SoftCard(
      onTap: () {},
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

  String _statusLabel(LectureSession session) {
    return switch (session.status) {
      SessionStatus.recording => 'Spelar in',
      SessionStatus.transcribing => 'Transkriberar',
      SessionStatus.summarizing => 'Skriver underlag',
      SessionStatus.ready =>
        session.summary == null
            ? 'Redo att skriva underlag'
            : NewsletterSummary.discussedHeading,
      // A frozen copy of the card as it read before interrupted lectures
      // existed, kept so this file can still render as a baseline. Nothing
      // writes `interrupted` into a session here, so the arm is unreachable.
      SessionStatus.interrupted => 'Redo att skriva underlag',
    };
  }
}

Future<void> _shoot(
  WidgetTester tester,
  String name,
  Brightness brightness,
  Widget home,
) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(390, 844) * 2;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  final base = lectureTheme(brightness: brightness);
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('sv'),
        theme: base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'PreviewSans'),
        ),
        home: home,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    return image.toByteData(format: ui.ImageByteFormat.png);
  });
  File('${outDir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (call) async => null,
        );

    final loader = FontLoader('PreviewSans');
    for (final path in [
      r'C:\Windows\Fonts\segoeui.ttf',
      r'C:\Windows\Fonts\seguisb.ttf',
      r'C:\Windows\Fonts\segoeuib.ttf',
    ]) {
      final file = File(path);
      if (file.existsSync()) {
        loader.addFont(
          Future.value(ByteData.view(file.readAsBytesSync().buffer)),
        );
      }
    }
    await loader.load();
  });

  testWidgets('baseline home light', (tester) async {
    await _shoot(
      tester,
      'baseline-home-light',
      Brightness.light,
      _BaselineHome([_ready(), _fresh()]),
    );
  });

  testWidgets('baseline home dark', (tester) async {
    await _shoot(
      tester,
      'baseline-home-dark',
      Brightness.dark,
      _BaselineHome([_ready(), _fresh()]),
    );
  });
}