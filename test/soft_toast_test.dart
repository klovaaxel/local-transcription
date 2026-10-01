import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/app_state.dart';
import 'package:lecture_local/asr/model_downloader.dart';
import 'package:lecture_local/main.dart';
import 'package:lecture_local/ui/soft_theme.dart';
import 'package:provider/provider.dart';

Widget _app(LectureAppState state) {
  return ChangeNotifierProvider.value(value: state, child: const LectureApp());
}

void main() {
  testWidgets('work toast floats above the action bar', (tester) async {
    final state = LectureAppState();
    await tester.pumpWidget(_app(state));

    state.busy = true;
    state.statusMessage = 'Transkriberar…';
    state.notifyListeners();
    await tester.pump();
    await tester.pump(SoftMotion.enter);

    expect(find.text('Föreläsningar'), findsOneWidget);
    expect(find.text('Transkriberar…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('download toast shows size detail', (tester) async {
    final state = LectureAppState();
    await tester.pumpWidget(_app(state));

    state.busy = true;
    state.statusMessage = 'Laddar ner talmodell…';
    state.downloadProgress = const DownloadProgress(
      label: 'encoder.onnx',
      received: 120000000,
      total: 376000000,
    );
    state.notifyListeners();
    await tester.pump();
    await tester.pump(SoftMotion.enter);

    expect(find.text('Laddar ner talmodell…'), findsOneWidget);
    expect(find.text('encoder.onnx · 120 / 376 MB'), findsOneWidget);
  });

  testWidgets('idle notice dismisses', (tester) async {
    final state = LectureAppState();
    await tester.pumpWidget(_app(state));

    state.statusMessage = 'Inspelning sparad.';
    state.notifyListeners();
    await tester.pump();
    await tester.pump(SoftMotion.enter);

    expect(find.text('Inspelning sparad.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('toast-dismiss')));
    await tester.pumpAndSettle();

    expect(state.statusMessage, isNull);
    expect(find.text('Inspelning sparad.'), findsNothing);
  });

  testWidgets('idle home shows no toast', (tester) async {
    final state = LectureAppState();
    await tester.pumpWidget(_app(state));
    await tester.pump();

    expect(find.text('OK'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a notice clears itself without being tapped', (tester) async {
    final state = LectureAppState();
    await tester.pumpWidget(_app(state));

    state.notice('Kopierat. Klistra in i skolplattformen.');
    await tester.pump();
    await tester.pump(SoftMotion.enter);
    expect(
      find.text('Kopierat. Klistra in i skolplattformen.'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(state.statusMessage, isNull);
    expect(find.text('Kopierat. Klistra in i skolplattformen.'), findsNothing);
  });

  testWidgets('work is not on a clock', (tester) async {
    final state = LectureAppState();
    await tester.pumpWidget(_app(state));

    state.busy = true;
    state.statusMessage = 'Skriver underlag…';
    state.notifyListeners();
    await tester.pump();
    await tester.pump(SoftMotion.enter);

    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Skriver underlag…'), findsOneWidget);

    state.busy = false;
    state.clearStatus();
    await tester.pumpAndSettle();
  });

  testWidgets('a hold waits for its condition, not for a clock', (
    tester,
  ) async {
    final state = LectureAppState();
    await tester.pumpWidget(_app(state));

    state.hold(LectureAppState.micSilenceNotice);
    await tester.pump();
    await tester.pump(SoftMotion.enter);
    expect(find.text(LectureAppState.micSilenceNotice), findsOneWidget);

    // Well past the four seconds a confirmation lives for. The microphone is
    // still silent, so the warning must still be up.
    await tester.pump(const Duration(seconds: 30));
    expect(find.text(LectureAppState.micSilenceNotice), findsOneWidget);
    expect(state.statusIsHold, isTrue);

    state.clearHold();
    await tester.pumpAndSettle();
    expect(find.text(LectureAppState.micSilenceNotice), findsNothing);
  });

  testWidgets('a hold says so to a screen reader', (tester) async {
    final state = LectureAppState();
    await tester.pumpWidget(_app(state));

    state.hold(LectureAppState.micSilenceNotice);
    await tester.pump();
    await tester.pump(SoftMotion.enter);

    // Matched on a fragment: bySemanticsLabel compares against the node's own
    // label, and the text is split across a label and its child.
    expect(
      find.bySemanticsLabel(RegExp('Fortfarande pågående')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        RegExp('${LectureAppState.micSilenceNotice} Fortfarande pågående'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a confirmation is not announced as ongoing', (tester) async {
    final state = LectureAppState();
    await tester.pumpWidget(_app(state));

    // A hold, then a confirmation, must not leave the ongoing wording behind:
    // the flag lives with the message, not on the toast.
    state.hold(LectureAppState.micSilenceNotice);
    await tester.pump();
    await tester.pump(SoftMotion.enter);

    state.notice(LectureAppState.micHeardAgainNotice);
    await tester.pump();
    await tester.pump(SoftMotion.enter);

    expect(
      find.bySemanticsLabel(RegExp(LectureAppState.micHeardAgainNotice)),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Fortfarande pågående')),
      findsNothing,
    );
  });

  testWidgets('a hold can be dismissed but comes straight back', (tester) async {
    final state = LectureAppState();
    await tester.pumpWidget(_app(state));

    state.hold(LectureAppState.micSilenceNotice);
    await tester.pump();
    await tester.pump(SoftMotion.enter);

    await tester.tap(find.byKey(const Key('toast-dismiss')));
    await tester.pumpAndSettle();
    expect(find.text(LectureAppState.micSilenceNotice), findsNothing);

    // The microphone is still silent, so the caller's next check raises it
    // again. A warning that could be waved away would be waved away always.
    // Two chunks, because the run starts at the first quiet one.
    final now = DateTime(2030, 1, 1);
    state.trackSilence(level: 0, now: now);
    state.trackSilence(level: 0, now: now.add(const Duration(seconds: 6)));
    await tester.pump();
    await tester.pump(SoftMotion.enter);
    expect(find.text(LectureAppState.micSilenceNotice), findsOneWidget);
  });

  testWidgets('a failure waits to be read', (tester) async {
    final state = LectureAppState();
    await tester.pumpWidget(_app(state));

    state.statusMessage = 'Kunde inte ladda ner talmodellen.';
    state.statusIsError = true;
    state.notifyListeners();
    await tester.pump();
    await tester.pump(SoftMotion.enter);

    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Kunde inte ladda ner talmodellen.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('toast-dismiss')));
    await tester.pumpAndSettle();
    expect(state.statusMessage, isNull);
  });
}
