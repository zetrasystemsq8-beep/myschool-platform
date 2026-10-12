import 'package:flutter/material.dart';

import '../widgets/brand_header.dart';

import '../data/auth_repository.dart';
import '../data/school_repository.dart';
import '../data/setup_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/async_list.dart';
import '../widgets/feedback.dart';
import '../widgets/form_sheet.dart';
import '../widgets/state_views.dart';

final _codeRe = RegExp(r'^[A-Z0-9][A-Z0-9-]{2,19}$');
final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// For the MySchool team: sign in, create schools, switch them on/off, add each school's
/// first administrator. Not linked to any single school.
class PlatformAdminScreen extends StatefulWidget {
  const PlatformAdminScreen({super.key});

  @override
  State<PlatformAdminScreen> createState() => _PlatformAdminScreenState();
}

class _PlatformAdminScreenState extends State<PlatformAdminScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _checking = true;
  bool _isAdmin = false;
  bool _signingIn = false;
  bool _hide = true;
  String? _error;
  int _listKey = 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final auth = AuthRepository.instance;
    if (!auth.hasSession) {
      setState(() {
        _checking = false;
        _isAdmin = false;
      });
      return;
    }
    try {
      final ok = await SetupRepository.instance.isPlatformAdmin(auth.userId!);
      if (!ok) await auth.signOut();
      if (!mounted) return;
      setState(() {
        _isAdmin = ok;
        _checking = false;
        _error = ok ? null : 'This account is not a platform administrator.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = friendlyError(e);
      });
    }
  }

  Future<void> _signIn() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Please enter your email and password.');
      return;
    }
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      await AuthRepository.instance.signInWithEmail(_email.text, _password.text);
      await _check();
    } catch (e) {
      if (mounted) setState(() => _error = authError(e));
    }
    if (mounted) setState(() => _signingIn = false);
  }

  Future<void> _signOut() async {
    await AuthRepository.instance.signOut();
    if (!mounted) return;
    setState(() {
      _isAdmin = false;
      _password.clear();
    });
  }

  Future<bool?> _newSchool() {
    return showFormSheet(
      context,
      title: 'New school',
      subtitle: 'The School ID is what students and parents use to find the school.',
      submitLabel: 'Create school',
      fields: const [
        FieldSpec('code', 'School ID', required: true, hint: 'CHR-ADO'),
        FieldSpec('name', 'School name', required: true),
        FieldSpec('motto', 'Motto (optional)'),
        FieldSpec('city', 'City (optional)'),
        FieldSpec('state', 'State (optional)'),
      ],
      onSubmit: (v) async {
        final code = v['code']!.toUpperCase();
        if (!_codeRe.hasMatch(code)) {
          throw FormError('School ID: 3-20 capital letters, digits or hyphens (e.g. CHR-ADO).');
        }
        try {
          await SetupRepository.instance.createSchool(
            code: code,
            name: v['name']!,
            motto: v['motto']!.isEmpty ? null : v['motto'],
            city: v['city']!.isEmpty ? null : v['city'],
            state: v['state']!.isEmpty ? null : v['state'],
          );
        } catch (e) {
          throw FormError(e.toString().contains('23505') ? 'That School ID is already taken.' : friendlyError(e));
        }
      },
    ).then((ok) {
      if (ok == true && mounted) notify(context, 'School created. Now add its administrator.');
      return ok;
    });
  }

  Future<void> _addAdmin(SchoolRow s) async {
    final ok = await showFormSheet(
      context,
      title: 'Add school administrator',
      subtitle: s.name,
      submitLabel: 'Create administrator',
      fields: const [
        FieldSpec('name', 'Full name', required: true),
        FieldSpec('email', 'Email', required: true, keyboard: TextInputType.emailAddress),
        FieldSpec('password', 'Password (at least 10 characters)', kind: FieldKind.password, required: true),
      ],
      onSubmit: (v) async {
        if (!_emailRe.hasMatch(v['email']!)) throw FormError('Please enter a valid email address.');
        if (v['password']!.length < 10) throw FormError('The password must be at least 10 characters.');
        try {
          await SetupRepository.instance.provision({
            'action': 'create',
            'school_id': s.id,
            'role': 'school_admin',
            'full_name': v['name'],
            'email': v['email'],
            'password': v['password'],
          });
        } catch (e) {
          throw FormError(provisionError(e));
        }
      },
    );
    if (ok == true && mounted) notify(context, 'Administrator created.');
  }

  Future<void> _toggle(SchoolRow s, {bool? active, bool? listed}) async {
    try {
      await SetupRepository.instance.setSchoolStatus(
        s.id,
        active: active ?? s.isActive,
        listed: listed ?? s.isListed,
      );
      if (mounted) setState(() => _listKey++);
    } catch (e) {
      if (mounted) notify(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checking && !_isAdmin) return _loginScaffold();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform administrator'),
        actions: [
          if (_isAdmin)
            IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: _signOut),
        ],
      ),
      body: _checking ? const LoadingView() : _schools(),
    );
  }

  Widget _loginScaffold() {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      body: Column(children: [
        BrandHeader(
          padding: EdgeInsets.fromLTRB(8, top + 4, 8, 28),
          child: Column(children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.maybePop(context),
              ),
            ),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppTheme.gold, width: 2),
              ),
              child: const Icon(Icons.admin_panel_settings_outlined, color: AppTheme.gold, size: 36),
            ),
            const SizedBox(height: 14),
            const Text('Platform administrator',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('MySchool team only',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            children: [
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                    labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: _hide,
                onSubmitted: (_) => _signIn(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _hide = !_hide),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
                  child: Text(_error!, style: TextStyle(color: cs.onErrorContainer)),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _signingIn ? null : _signIn,
                child: _signingIn
                    ? const SizedBox(
                        width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('Sign in'),
              ),
              const SizedBox(height: 16),
              Text('Create schools, switch them on or off and add each school\'s first administrator.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _schools() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AsyncList<SchoolRow>(
      key: ValueKey(_listKey),
      load: () => SetupRepository.instance.allSchools(),
      emptyIcon: Icons.apartment_outlined,
      emptyTitle: 'No schools yet',
      emptyMessage: 'Create the first school, then add its administrator.',
      addLabel: 'New school',
      onAdd: _newSchool,
      itemBuilder: (ctx, s, reload) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(s.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'admin':
                    _addAdmin(s);
                  case 'active':
                    _toggle(s, active: !s.isActive);
                  case 'listed':
                    _toggle(s, listed: !s.isListed);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'admin', child: Text('Add school administrator')),
                PopupMenuItem(value: 'active', child: Text(s.isActive ? 'Deactivate school' : 'Activate school')),
                PopupMenuItem(value: 'listed', child: Text(s.isListed ? 'Hide from search' : 'Show in search')),
              ],
            ),
          ]),
          Text([s.code, if ((s.city ?? '').isNotEmpty) s.city!, if ((s.state ?? '').isNotEmpty) s.state!].join('  ·  '),
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            StatusPill(label: s.isActive ? 'Active' : 'Inactive', color: s.isActive ? AppTheme.green : cs.error),
            StatusPill(label: s.isListed ? 'In search' : 'Hidden', color: s.isListed ? AppTheme.gold : Colors.grey),
          ]),
        ]),
      ),
    );
  }
}
