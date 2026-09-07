import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/app_state.dart';
import 'package:lecture_local/main.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('home shows empty state and record action', (tester) async {
    final state = LectureAppState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: state, child: const LectureApp()),
    );
    expect(find.text('Föreläsningar'), findsOneWidget);
    expect(find.text('Spela in'), findsOneWidget);
  });
}
