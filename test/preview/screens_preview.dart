// Design preview harness. Renders every screen to a PNG under build/preview
// so the look can be reviewed without launching the app:
//
//   flutter test test/preview/screens_preview.dart
//
// The filename does not end in _test.dart, so `flutter test` skips it unless
// you name it explicitly. Text is drawn with a system font because the test
// renderer has none; icon glyphs still come out as empty boxes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/app_state.dart';
import 'package:lecture_local/data/lecture_session.dart';
import 'package:lecture_local/data/session_store.dart';
import 'package:lecture_local/features/home/home_page.dart';
import 'package:lecture_local/features/record/record_page.dart';
import 'package:lecture_local/features/sessions/session_page.dart';
import 'package:lecture_local/features/settings/settings_page.dart';
import 'package:lecture_local/summarize/newsletter.dart';
import 'package:lecture_local/asr/model_downloader.dart';
import 'package:lecture_local/ui/soft_theme.dart';
import 'package:lecture_local/ui/soft_toast.dart';
import 'package:provider/provider.dart';

final outDir = Directory('build/preview')..createSync(recursive: true);

class MemoryStore extends SessionStore {
  MemoryStore(this.items);
  List<LectureSession> items;
  @override
  Future<List<LectureSession>> list() async => List.of(items);
  @override
  Future<void> upsert(LectureSession session) async {}
  @override
  Future<void> delete(String id) async {}
}

LectureSession _ready() => LectureSession(
  id: 's1',
  startedAt: DateTime(2026, 9, 1, 10, 15),
  transcript:
      'Idag gick vi igenom unionsupplösningen 1905 och varför Norge lämnade '
      'unionen. Vi tittade också på Karlstadskonventionen.',
  summary: const NewsletterSummary(
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

Future<void> _shoot(
  WidgetTester tester,
  String name,
  Brightness brightness,
  Widget home, {
  required LectureAppState state,
  Size size = const Size(390, 844),
  bool withToast = false,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  final base = lectureTheme(brightness: brightness);
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('sv'),
          theme: base.copyWith(
            textTheme: base.textTheme.apply(fontFamily: 'PreviewSans'),
          ),
          builder: withToast
              ? (context, child) => Stack(
                  clipBehavior: Clip.none,
                  children: [?child, const SoftToastLayer()],
                )
              : null,
          home: home,
        ),
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
  File('${outDir.path}/$name.png')
      .writeAsBytesSync(bytes!.buffer.asUint8List());
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

  testWidgets('home light', (tester) async {
    final state = LectureAppState(store: MemoryStore([]));
    state.sessions = [_ready(), _fresh()];
    await _shoot(
      tester,
      'home-light',
      Brightness.light,
      const HomePage(),
      state: state,
    );
  });

  testWidgets('home dark', (tester) async {
    final state = LectureAppState(store: MemoryStore([]));
    state.sessions = [_ready(), _fresh()];
    await _shoot(
      tester,
      'home-dark',
      Brightness.dark,
      const HomePage(),
      state: state,
    );
  });

  testWidgets('home empty', (tester) async {
    final state = LectureAppState(store: MemoryStore([]));
    await _shoot(
      tester,
      'home-empty',
      Brightness.light,
      const HomePage(),
      state: state,
    );
  });

  testWidgets('session light', (tester) async {
    final session = _ready();
    final state = LectureAppState(store: MemoryStore([session]));
    state.sessions = [session];
    await _shoot(
      tester,
      'session-light',
      Brightness.light,
      SessionPage(sessionId: session.id),
      state: state,
    );
  });

  testWidgets('session dark', (tester) async {
    final session = _ready();
    final state = LectureAppState(store: MemoryStore([session]));
    state.sessions = [session];
    await _shoot(
      tester,
      'session-dark',
      Brightness.dark,
      SessionPage(sessionId: session.id),
      state: state,
    );
  });

  testWidgets('session wide', (tester) async {
    final session = _ready();
    final state = LectureAppState(store: MemoryStore([session]));
    state.sessions = [session];
    await _shoot(
      tester,
      'session-wide',
      Brightness.light,
      SessionPage(sessionId: session.id),
      state: state,
      size: const Size(1280, 860),
    );
  });

  testWidgets('settings light', (tester) async {
    final state = LectureAppState(store: MemoryStore([]));
    await _shoot(
      tester,
      'settings-light',
      Brightness.light,
      const SettingsPage(),
      state: state,
    );
  });

  testWidgets('record light', (tester) async {
    final state = LectureAppState(store: MemoryStore([]));
    state.active = LectureSession(
      id: 'live',
      startedAt: DateTime(2026, 9, 1, 10, 15),
      liveCaptions:
          'Så unionsupplösningen sker alltså 1905, och det ni ska komma ihåg '
          'är konsulatfrågan. Vi tar Karlstadskonventionen på fredag.',
      status: SessionStatus.recording,
    );
    state.recordElapsed = const Duration(minutes: 12, seconds: 4);
    state.inputLevel = 0.62;
    await _shoot(
      tester,
      'record-light',
      Brightness.light,
      const RecordPage(),
      state: state,
    );
  });

  testWidgets('toast working', (tester) async {
    final state = LectureAppState(store: MemoryStore([]));
    state.sessions = [_ready()];
    state.busy = true;
    state.statusMessage = 'Skriver underlag…';
    await _shoot(
      tester,
      'toast-working',
      Brightness.light,
      const HomePage(),
      state: state,
      withToast: true,
    );
  });

  testWidgets('toast download', (tester) async {
    final state = LectureAppState(store: MemoryStore([]));
    state.sessions = [_ready()];
    state.busy = true;
    state.statusMessage = 'Laddar ner talmodell…';
    state.downloadProgress = const DownloadProgress(
      label: 'kb-whisper-small-encoder.int8.onnx',
      received: 120000000,
      total: 376000000,
    );
    await _shoot(
      tester,
      'toast-download',
      Brightness.light,
      const HomePage(),
      state: state,
      withToast: true,
    );
  });

  testWidgets('toast notice', (tester) async {
    final state = LectureAppState(store: MemoryStore([]));
    state.sessions = [_ready()];
    state.statusMessage = 'Inspelning sparad.';
    await _shoot(
      tester,
      'toast-notice',
      Brightness.light,
      const HomePage(),
      state: state,
      withToast: true,
    );
  });

  testWidgets('toast notice dark', (tester) async {
    final state = LectureAppState(store: MemoryStore([]));
    state.sessions = [_ready()];
    state.statusMessage = 'Inspelning sparad.';
    await _shoot(
      tester,
      'toast-notice-dark',
      Brightness.dark,
      const HomePage(),
      state: state,
      withToast: true,
    );
  });
}
