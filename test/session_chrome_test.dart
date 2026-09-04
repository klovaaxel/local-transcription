import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/app_state.dart';
import 'package:lecture_local/data/lecture_session.dart';
import 'package:lecture_local/data/session_store.dart';
import 'package:lecture_local/features/sessions/session_page.dart';
import 'package:lecture_local/features/settings/settings_page.dart';
import 'package:lecture_local/models/model_catalog.dart';
import 'package:lecture_local/summarize/newsletter.dart';
import 'package:lecture_local/ui/soft_buttons.dart';
import 'package:lecture_local/ui/soft_theme.dart';
import 'package:provider/provider.dart';

class MemorySessionStore extends SessionStore {
  MemorySessionStore(this.items);

  List<LectureSession> items;

  @override
  Future<List<LectureSession>> list() async => List.of(items);

  @override
  Future<void> upsert(LectureSession session) async {
    final i = items.indexWhere((s) => s.id == session.id);
    if (i >= 0) {
      items[i] = session;
    } else {
      items.add(session);
    }
  }

  @override
  Future<void> delete(String id) async {
    items.removeWhere((s) => s.id == id);
  }
}

LectureSession _readySession() {
  return LectureSession(
    id: 's1',
    startedAt: DateTime(2026, 9, 1, 10),
      transcript: 'Vi gick igenom unionsupplösningen.',
    summary: const NewsletterSummary(
      discussed: 'Unionsupplösningen 1905.',
      decided: 'Prov på fredag.',
      absentees: 'Läs kapitel 4.',
    ),
  );
}

Widget _app({
  required LectureAppState state,
  required Widget home,
}) {
  return ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(
      locale: const Locale('sv'),
      theme: lectureTheme(brightness: Brightness.light),
      home: home,
    ),
  );
}

/// Right edge of the leading slot. Anything centred past the first third of
/// the window has stopped reading as leading chrome.
double _leadingSlot(WidgetTester tester) {
  return tester.view.physicalSize.width / tester.view.devicePixelRatio / 3;
}

void main() {
  testWidgets('session leading slot is back, not delete', (tester) async {
    final session = _readySession();
    final state = LectureAppState(store: MemorySessionStore([session]));
    state.sessions = [session];

    await tester.pumpWidget(
      _app(state: state, home: SessionPage(sessionId: session.id)),
    );
    await tester.pump();

    final back = tester.getCenter(find.byType(SoftBackButton));
    final delete = tester.getCenter(find.text('Ta bort'));
    expect(back.dx, lessThan(_leadingSlot(tester)));
    expect(delete.dy, greaterThan(back.dy + 80));
    expect(find.text('Kopiera'), findsOneWidget);
    expect(find.text('Dela'), findsOneWidget);
  });

  testWidgets('settings leading slot is back', (tester) async {
    final state = LectureAppState(store: MemorySessionStore([]));
    await tester.pumpWidget(
      _app(state: state, home: const SettingsPage()),
    );
    await tester.pump();

    expect(find.byType(SoftBackButton), findsOneWidget);
    expect(
      tester.getCenter(find.byType(SoftBackButton)).dx,
      lessThan(_leadingSlot(tester)),
    );
  });

  testWidgets('settings offers the 7B brief model', (tester) async {
    final state = LectureAppState(store: MemorySessionStore([]));
    await tester.pumpWidget(
      _app(state: state, home: const SettingsPage()),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Qwen 7B (dator, ~4,7 GB)'),
      120,
    );
    expect(find.text('Qwen 1.5B (telefon, ~1,1 GB)'), findsOneWidget);
    expect(find.text('Qwen 7B (dator, ~4,7 GB)'), findsOneWidget);
  });

  testWidgets('settings hides the provider card until cloud is picked',
      (tester) async {
    final state = LectureAppState(store: MemorySessionStore([]));
    await tester.pumpWidget(
      _app(state: state, home: const SettingsPage()),
    );
    await tester.pump();

    expect(find.text('Leverantör'), findsNothing);
    expect(find.text('API-nyckel'), findsNothing);
  });

  testWidgets('cloud transcription reveals the Berget fields', (tester) async {
    final state = LectureAppState(store: MemorySessionStore([]));
    state.settings.transcriber = TranscriberKind.cloud;
    await tester.pumpWidget(
      _app(state: state, home: const SettingsPage()),
    );
    await tester.pump();

    await tester.scrollUntilVisible(find.text('Leverantör'), 120);
    expect(find.text('Berget AI (Sverige)'), findsOneWidget);
    expect(find.text('API-adress'), findsOneWidget);
    expect(find.text('API-nyckel'), findsOneWidget);
    expect(find.text('Talmodell'), findsOneWidget);
    // Only the brief runs locally, so no chat model field is offered.
    expect(find.text('Språkmodell'), findsNothing);
  });

  testWidgets('copy is a peer of share and reports through the app toast', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final session = _readySession();
    final state = LectureAppState(store: MemorySessionStore([session]));
    state.sessions = [session];

    await tester.pumpWidget(
      _app(state: state, home: SessionPage(sessionId: session.id)),
    );
    await tester.pump();

    // Same row, so the same rank: the brief goes to two destinations.
    final copy = tester.getCenter(find.text('Kopiera'));
    final share = tester.getCenter(find.text('Dela'));
    expect(copy.dy, share.dy);
    expect(copy.dx, lessThan(share.dx));

    await tester.tap(find.text('Kopiera'));
    await tester.pump();

    expect(copied.single, contains('Unionsupplösningen 1905.'));
    expect(state.statusMessage, 'Kopierat. Klistra in i skolplattformen.');
    expect(state.statusIsError, isFalse);
    expect(find.byType(SnackBar), findsNothing);
  });
}
