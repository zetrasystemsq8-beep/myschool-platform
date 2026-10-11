import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/app_settings.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() {
  // Anything that escapes a screen's own error handling lands here instead of crashing the app.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = FlutterError.presentError;
    ErrorWidget.builder = (details) => const _BrokenScreen();
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
    await AppSettings.load();
    runApp(const MySchoolApp());
  }, (error, stack) => debugPrint('Unhandled error: $error'));
}

class MySchoolApp extends StatelessWidget {
  const MySchoolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.themeMode,
      builder: (_, mode, __) => MaterialApp(
        title: 'MySchool',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        home: const SplashScreen(),
      ),
    );
  }
}

/// Shown in place of a widget that failed to build (instead of a grey/red error box).
class _BrokenScreen extends StatelessWidget {
  const _BrokenScreen();

  @override
  Widget build(BuildContext context) {
    return const Material(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Something went wrong on this screen.\nGo back and try again.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
