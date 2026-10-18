import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/school.dart';
import '../data/school_repository.dart';
import '../data/school_settings_repository.dart';
import '../data/models.dart';
import '../widgets/app_card.dart';
import '../widgets/feedback.dart';
import '../widgets/form_sheet.dart';
import '../widgets/help.dart';
import '../widgets/school_avatar.dart';
import '../widgets/state_views.dart';
import 'grading_scale_screen.dart';

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// The administrator's school profile: logo, details, how scores are split, who approves.
/// Pops with the updated [School] when something changed, so the rest of the app refreshes.
class SchoolSettingsScreen extends StatefulWidget {
  const SchoolSettingsScreen({super.key, required this.school});

  final School school;

  @override
  State<SchoolSettingsScreen> createState() => _SchoolSettingsScreenState();
}

class _SchoolSettingsScreenState extends State<SchoolSettingsScreen> {
  late School _school = widget.school;
  Map<String, dynamic> _profile = const {};
  double _ca = 40;
  double _exam = 60;
  bool _separate = false;
  bool _loading = true;
  bool _uploading = false;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = SchoolSettingsRepository.instance;
      final profile = await repo.loadProfile(_school.id);
      final scoring = await repo.loadScoring(_school.id);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _ca = scoring.ca;
        _exam = scoring.exam;
        _separate = scoring.separateApprover;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  String? _s(String key) {
    final v = (_profile[key] as String?)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  School _rebuild() => School(
        id: _school.id,
        code: _school.code,
        name: _s('name') ?? _school.name,
        motto: _s('motto'),
        description: _s('description'),
        logoPath: _s('logo_path'),
        website: _s('website'),
        city: _s('city'),
        state: _s('state'),
        country: _s('country') ?? _school.country,
      );

  Future<void> _afterChange() async {
    _school = _rebuild();
    _changed = true;
    await SchoolRepository.instance.saveSchool(_school);
  }

  Future<void> _editProfile() async {
    final ok = await showFormSheet(
      context,
      title: 'School profile',
      subtitle: 'This is what parents and students see when they find your school.',
      submitLabel: 'Save',
      fields: [
        FieldSpec('name', 'School name', required: true, initial: _s('name')),
        FieldSpec('motto', 'Motto', initial: _s('motto')),
        FieldSpec('description', 'About the school', kind: FieldKind.multiline, initial: _s('description')),
        FieldSpec('website', 'Website', initial: _s('website'), hint: 'https://', keyboard: TextInputType.url),
        FieldSpec('email', 'Contact email', initial: _s('contact_email'), keyboard: TextInputType.emailAddress),
        FieldSpec('phone', 'Contact phone', initial: _s('contact_phone'), keyboard: TextInputType.phone),
        FieldSpec('address', 'Address', initial: _s('address')),
        FieldSpec('city', 'City', initial: _s('city')),
        FieldSpec('state', 'State', initial: _s('state')),
      ],
      onSubmit: (v) async {
        if (v['name']!.length < 2) throw FormError('The school name is too short.');
        if (v['email']!.isNotEmpty && !_emailRe.hasMatch(v['email']!)) {
          throw FormError('Please enter a valid email address.');
        }
        if (v['website']!.isNotEmpty && !v['website']!.startsWith(RegExp(r'https?://'))) {
          throw FormError('The website must start with http:// or https://');
        }
        String? n(String k) => v[k]!.isEmpty ? null : v[k];
        final values = {
          'name': v['name'],
          'motto': n('motto'),
          'description': n('description'),
          'website': n('website'),
          'contact_email': n('email'),
          'contact_phone': n('phone'),
          'address': n('address'),
          'city': n('city'),
          'state': n('state'),
        };
        try {
          await SchoolSettingsRepository.instance.saveProfile(_school.id, values);
        } catch (e) {
          throw FormError(friendlyError(e));
        }
        _profile = {..._profile, ...values};
      },
    );
    if (ok == true) {
      await _afterChange();
      if (mounted) {
        setState(() {});
        notify(context, 'School profile saved.');
      }
    }
  }

  Future<void> _changeLogo() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600, maxHeight: 600, imageQuality: 85);
      if (file == null) return;
      setState(() => _uploading = true);
      final bytes = await file.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        throw Exception('That picture is too big. Choose a smaller one (under 2 MB).');
      }
      final ext = file.name.contains('.') ? file.name.split('.').last : 'jpg';
      final path = await SchoolSettingsRepository.instance.uploadLogo(_school.id, bytes, ext, _s('logo_path'));
      _profile = {..._profile, 'logo_path': path};
      await _afterChange();
      if (mounted) notify(context, 'Logo updated.');
    } catch (e) {
      if (mounted) notify(context, e is Exception && e.toString().startsWith('Exception: That') ? e.toString().substring(11) : friendlyError(e), error: true);
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _editScoring() async {
    final ok = await showFormSheet(
      context,
      title: 'How scores are split',
      subtitle: 'Test (CA) plus Exam always makes 100.',
      submitLabel: 'Save',
      fields: [
        FieldSpec('ca', 'Test (CA) is out of', required: true, initial: fmt(_ca), keyboard: TextInputType.number),
      ],
      onSubmit: (v) async {
        final ca = double.tryParse(v['ca']!.replaceAll(',', '.'));
        if (ca == null || ca < 0 || ca > 100) throw FormError('Enter a number from 0 to 100.');
        final exam = 100 - ca;
        if (ca != _ca) {
          final proceed = await confirmDialog(context,
              title: 'Change the split?',
              message: 'Test (CA) out of ${fmt(ca)} and Exam out of ${fmt(exam)}. '
                  'Scores already saved are not changed, so it is best to do this between terms.',
              action: 'Change');
          if (!proceed) throw FormError('Nothing was changed.');
        }
        try {
          await SchoolSettingsRepository.instance.saveScoring(_school.id, ca, exam);
        } catch (e) {
          throw FormError(friendlyError(e));
        }
        _ca = ca;
        _exam = exam;
      },
    );
    if (ok == true && mounted) {
      setState(() {});
      notify(context, 'Saved.');
    }
  }

  Future<void> _toggleSeparate(bool v) async {
    try {
      await SchoolSettingsRepository.instance.setSeparateApprover(_school.id, v);
      if (mounted) setState(() => _separate = v);
    } catch (e) {
      if (mounted) notify(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget detail(IconData icon, String label, String? value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(value ?? 'Not set',
                  style: theme.textTheme.bodyMedium?.copyWith(color: value == null ? cs.onSurfaceVariant : null)),
            ),
          ]),
        );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed ? _school : null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('School profile & settings'),
          actions: const [
            HelpButton(
              title: 'School profile & settings',
              steps: [
                'Change your logo and the details parents see.',
                'Choose how marks are split between the test (CA) and the exam.',
                'Open "Grading scale" to set which score gets which grade.',
                'Changing the split or the grading scale does not change results already saved. Do it between terms.',
              ],
            ),
          ],
        ),
        body: _loading
            ? const LoadingView()
            : _error != null
                ? MessageView(icon: Icons.cloud_off_outlined, title: 'Could not load', message: _error!, onRetry: _load)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      AppCard(
                        child: Row(children: [
                          SchoolAvatar(school: _school, size: 72),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_school.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                              Text('School ID: ${_school.code}',
                                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                                onPressed: _uploading ? null : _changeLogo,
                                icon: _uploading
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.image_outlined, size: 18),
                                label: Text(_uploading ? 'Uploading...' : 'Change logo'),
                              ),
                            ]),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 4),
                      const SectionTitle('School details'),
                      AppCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          detail(Icons.format_quote, 'Motto', _s('motto')),
                          detail(Icons.info_outline, 'About', _s('description')),
                          detail(Icons.language, 'Website', _s('website')),
                          detail(Icons.email_outlined, 'Email', _s('contact_email')),
                          detail(Icons.phone_outlined, 'Phone', _s('contact_phone')),
                          detail(Icons.place_outlined, 'Address', [_s('address'), _s('city'), _s('state')].whereType<String>().join(', ').isEmpty
                              ? null
                              : [_s('address'), _s('city'), _s('state')].whereType<String>().join(', ')),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                              onPressed: _editProfile,
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('Edit details'),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      const SectionTitle('Results'),
                      AppCard(
                        onTap: _editScoring,
                        child: Row(children: [
                          Icon(Icons.pie_chart_outline, color: cs.primary),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('How scores are split', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                              Text('Test (CA) out of ${fmt(_ca)}  ·  Exam out of ${fmt(_exam)}',
                                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                            ]),
                          ),
                          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                        ]),
                      ),
                      const SizedBox(height: 10),
                      AppCard(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => GradingScaleScreen(school: _school)),
                        ),
                        child: Row(children: [
                          Icon(Icons.grade_outlined, color: cs.primary),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Grading scale', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                              Text('Which score gets which grade',
                                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                            ]),
                          ),
                          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                        ]),
                      ),
                      const SizedBox(height: 10),
                      AppCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('A different person must approve'),
                          subtitle: const Text('The administrator who approves results cannot be the one who sent them.'),
                          value: _separate,
                          onChanged: _toggleSeparate,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const HintBanner(
                        text: 'The School ID cannot be changed here. Contact MySchool if it must change.',
                      ),
                    ],
                  ),
      ),
    );
  }
}
