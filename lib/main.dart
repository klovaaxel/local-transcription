import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'features/home/home_page.dart';
import 'ui/soft_theme.dart';
import 'ui/soft_toast.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = LectureAppState();
  await state.init();
  runApp(ChangeNotifierProvider.value(value: state, child: const LectureApp()));
}

class LectureApp extends StatelessWidget {
  const LectureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Föreläsning',
      locale: const Locale('sv'),
      theme: lectureTheme(brightness: Brightness.light),
      darkTheme: lectureTheme(brightness: Brightness.dark),
      builder: (context, child) {
        return Stack(
          clipBehavior: Clip.none,
          children: [?child, const SoftToastLayer()],
        );
      },
      home: const HomePage(),
    );
  }
}
