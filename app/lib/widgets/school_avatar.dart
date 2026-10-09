import 'package:flutter/material.dart';

import '../data/school.dart';
import '../data/school_repository.dart';

/// School logo, or green initials when there is no logo (or it fails to load).
class SchoolAvatar extends StatelessWidget {
  const SchoolAvatar({super.key, required this.school, this.size = 56});

  final School school;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(size * 0.28);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: cs.primary, borderRadius: radius),
      child: Text(
        school.initials,
        style: TextStyle(
          color: cs.onPrimary,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.36,
        ),
      ),
    );

    final url = SchoolRepository.instance.logoUrl(school.logoPath);
    if (url == null) return fallback;
    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
