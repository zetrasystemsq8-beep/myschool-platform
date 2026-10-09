/// Public profile of a school (only fields the backend intentionally exposes).
class School {
  const School({
    required this.id,
    required this.code,
    required this.name,
    this.motto,
    this.description,
    this.logoPath,
    this.website,
    this.city,
    this.state,
    this.country,
  });

  final String id;
  final String code; // the public "School ID"
  final String name;
  final String? motto;
  final String? description;
  final String? logoPath;
  final String? website;
  final String? city;
  final String? state;
  final String? country;

  factory School.fromMap(Map<String, dynamic> m) => School(
        id: m['id'] as String,
        code: m['school_code'] as String,
        name: m['name'] as String,
        motto: m['motto'] as String?,
        description: m['description'] as String?,
        logoPath: m['logo_path'] as String?,
        website: m['website'] as String?,
        city: m['city'] as String?,
        state: m['state'] as String?,
        country: m['country'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'school_code': code,
        'name': name,
        'motto': motto,
        'description': description,
        'logo_path': logoPath,
        'website': website,
        'city': city,
        'state': state,
        'country': country,
      };

  String get location => [city, state]
      .whereType<String>()
      .where((e) => e.trim().isNotEmpty)
      .join(', ');

  String get initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final letters = words.take(2).map((w) => w[0].toUpperCase()).join();
    return letters.isEmpty ? '?' : letters;
  }
}
