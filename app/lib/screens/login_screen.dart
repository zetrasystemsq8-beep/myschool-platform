import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../data/school.dart';
import '../widgets/school_avatar.dart';
import 'portal_shell.dart';

class _Denied implements Exception {
  _Denied(this.message);
  final String message;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.school});

  final School school;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idCtl = TextEditingController();
  final _secretCtl = TextEditingController();
  bool _studentMode = true;
  bool _hide = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _idCtl.dispose();
    _secretCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final id = _idCtl.text.trim();
    final secret = _secretCtl.text;
    if (id.isEmpty || secret.isEmpty) {
      setState(() => _error = 'Please fill in both fields.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = AuthRepository.instance;
    try {
      if (_studentMode) {
        await auth.signInStudent(
          schoolCode: widget.school.code,
          admissionNumber: id,
          pin: secret,
        );
      } else {
        await auth.signInWithEmail(id, secret);
      }
      final member = await auth.membershipFor(widget.school.id);
      if (member == null || !member.isActive) {
        await auth.signOut();
        throw _Denied(member == null
            ? 'This account does not belong to ${widget.school.name}.'
            : 'This account is suspended. Please contact your school.');
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => PortalShell(school: widget.school, member: member),
        ),
        (route) => false,
      );
    } on _Denied catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = authError(e); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Center(child: SchoolAvatar(school: widget.school, size: 72)),
            const SizedBox(height: 14),
            Text(widget.school.name,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Sign in to continue',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Student'), icon: Icon(Icons.badge_outlined)),
                ButtonSegment(value: false, label: Text('Parent / Staff'), icon: Icon(Icons.person_outline)),
              ],
              selected: {_studentMode},
              onSelectionChanged: (s) => setState(() {
                _studentMode = s.first;
                _idCtl.clear();
                _secretCtl.clear();
                _error = null;
              }),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _idCtl,
              keyboardType: _studentMode
                  ? TextInputType.text
                  : TextInputType.emailAddress,
              textCapitalization: _studentMode
                  ? TextCapitalization.characters
                  : TextCapitalization.none,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: _studentMode ? 'Admission number' : 'Email',
                prefixIcon: Icon(_studentMode ? Icons.badge_outlined : Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _secretCtl,
              obscureText: _hide,
              autocorrect: false,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: _studentMode ? 'PIN' : 'Password',
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
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(Icons.error_outline, color: cs.onErrorContainer, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_error!,
                        style: TextStyle(color: cs.onErrorContainer)),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Sign in'),
            ),
            const SizedBox(height: 16),
            Text(
              _studentMode
                  ? 'Your admission number and PIN are given by your school.'
                  : 'Use the email and password your school created for you.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
