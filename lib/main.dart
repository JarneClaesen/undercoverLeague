import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/screens/home_screen.dart';
import 'package:undercoverleague/theme/app_theme.dart';

void main() {
  // Hot reload otherwise leaves one-shot entrance animations finished and
  // invisible while a screen is being worked on.
  if (kDebugMode) Animate.restartOnHotReload = true;
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Undercover League',
      debugShowCheckedModeBanner: false,
      theme: hextechTheme(),
      darkTheme: hextechTheme(),
      themeMode: ThemeMode.dark,
      // HextechScaffold applies the 600px width cap itself.
      home: const HomeScreen(),
    );
  }
}
