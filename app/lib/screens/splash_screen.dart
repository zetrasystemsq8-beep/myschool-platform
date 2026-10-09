import 'package:flutter/material.dart';

import '../data/school_repository.dart';
import '../theme/app_theme.dart';
import 'school_home_screen.dart';
import 'school_search_screen.dart';

/// Shows the brand briefly, then goes straight to the school the user chose last time
/// (or to school search on first launch).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final started = DateTime.now();
    final saved = await SchoolRepository.instance.savedSchool();
    final elapsed = DateTime.now().difference(started);
    const minimum = Duration(milliseconds: 1100);
    if (elapsed < minimum) await Future<void>.delayed(minimum - elapsed);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => saved == null
          ? const SchoolSearchScreen()
          : SchoolHomeScreen(school: saved),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.green,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppTheme.gold, width: 2),
              ),
              child: const Icon(Icons.school_rounded,
                  size: 52, color: AppTheme.gold),
            ),
            const SizedBox(height: 24),
            const Text('MySchool',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Text('Your school, in your pocket',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8), fontSize: 15)),
            const SizedBox(height: 40),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: AppTheme.gold),
            ),
          ],
        ),
      ),
    );
  }
}
