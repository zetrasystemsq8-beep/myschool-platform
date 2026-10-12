import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../data/school_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_header.dart';
import 'portal_shell.dart';
import 'school_home_screen.dart';
import 'school_search_screen.dart';

/// Brief brand moment, then straight to the school the user chose last time (or to search).
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
    Widget next = saved == null
        ? const SchoolSearchScreen()
        : SchoolHomeScreen(school: saved);
    // Already signed in? Go straight into the portal.
    if (saved != null && AuthRepository.instance.hasSession) {
      try {
        final member = await AuthRepository.instance.membershipFor(saved.id);
        if (member != null && member.isActive) {
          next = PortalShell(school: saved, member: member);
        }
      } catch (_) {
        // Offline: fall back to the school page.
      }
    }
    final elapsed = DateTime.now().difference(started);
    const minimum = Duration(milliseconds: 1400);
    if (elapsed < minimum) await Future<void>.delayed(minimum - elapsed);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, __, ___) => next,
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: AppTheme.green,
      body: BrandHeader(
        radius: 0,
        illustration: true,
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: h,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: AppTheme.gold, width: 2.5),
              ),
              child: const Icon(Icons.school_rounded, size: 56, color: AppTheme.gold),
            ),
            const SizedBox(height: 26),
            const Text('MySchool',
                style: TextStyle(
                    color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
            const SizedBox(height: 8),
            Text('Your school, in your pocket',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 16)),
            const SizedBox(height: 48),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 3, color: AppTheme.gold),
            ),
          ]),
        ),
      ),
    );
  }
}
