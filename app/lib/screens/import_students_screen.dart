import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/credentials_pdf.dart';
import '../data/csv_parse.dart';
import '../data/school.dart';
import '../data/school_repository.dart';
import '../data/setup_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';
import '../widgets/feedback.dart';
import '../widgets/help.dart';
import '../widgets/state_views.dart';

const _example = 'admission_number,first_name,last_name,class,parent_name,parent_email\n'
    '2026/001,Ada,Obi,JSS 1 A,Mrs Obi,mrs.obi@example.com\n'
    '2026/002,Bayo,Obi,JSS 1 A,Mrs Obi,mrs.obi@example.com\n'
    '2026/003,Chika,Eze,JSS 1 B,,\n';

final _pinRe = RegExp(r'^[A-Za-z0-9]{6,32}$');
final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

class _Row {
  _Row(this.line, this.v);

  final int line;
  final Map<String, String> v;
  final List<String> problems = [];
  bool exists = false;
  String? classId;
  String pin = '';
  String status = 'pending'; // pending | created | failed
  String message = '';

  String get name => '${v['first']} ${v['last']}'.trim();
  bool get ready => problems.isEmpty && !exists;
}

/// Add many students (and their parents) from a spreadsheet saved as CSV.
/// Missing PINs are generated and shown once, with a printable list to hand out.
class ImportStudentsScreen extends StatefulWidget {
  const ImportStudentsScreen({super.key, required this.school});

  final School school;

  @override
  State<ImportStudentsScreen> createState() => _ImportStudentsScreenState();
}

class _ImportStudentsScreenState extends State<ImportStudentsScreen> {
  final _text = TextEditingController();
  List<_Row> _rows = const [];
  String? _headerError;
  String? _sessionId;
  bool _checking = false;
  bool _running = false;
  bool _done = false;
  bool _cancel = false;
  int _progress = 0;
  final List<StudentLogin> _studentLogins = [];
  final List<ParentLogin> _parentLogins = [];
  final Map<String, String> _parentIds = {};

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _chooseFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt'], withData: true);
      final bytes = res?.files.single.bytes;
      if (bytes == null) return;
      setState(() => _text.text = utf8.decode(bytes, allowMalformed: true));
    } catch (e) {
      if (mounted) notify(context, 'Could not open that file. Try pasting the text instead.', error: true);
    }
  }

  String _norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _headerError = null;
    });
    try {
      final table = parseCsv(_text.text);
      if (table.length < 2) {
        setState(() {
          _headerError = 'Add a header line and at least one student.';
          _checking = false;
        });
        return;
      }
      String key(String h) => h.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
      final headers = table.first.map(key).toList();
      int col(List<String> names) => headers.indexWhere(names.contains);
      final cAdm = col(['admission_number', 'admission', 'admission_no', 'adm', 'adm_no']);
      final cFirst = col(['first_name', 'firstname', 'first']);
      final cLast = col(['last_name', 'lastname', 'surname', 'last']);
      final cOther = col(['other_names', 'other_name', 'middle_name', 'othernames']);
      final cClass = col(['class', 'class_name']);
      final cPin = col(['pin']);
      final cPName = col(['parent_name', 'guardian_name']);
      final cPEmail = col(['parent_email', 'guardian_email']);
      final missing = [if (cAdm < 0) 'admission_number', if (cFirst < 0) 'first_name', if (cLast < 0) 'last_name', if (cClass < 0) 'class'];
      if (missing.isNotEmpty) {
        setState(() {
          _headerError = 'Missing column${missing.length == 1 ? '' : 's'}: ${missing.join(', ')}.';
          _checking = false;
        });
        return;
      }
      if (table.length - 1 > 300) {
        setState(() {
          _headerError = 'That is more than 300 students. Please import in smaller lists.';
          _checking = false;
        });
        return;
      }

      final repo = SetupRepository.instance;
      final classes = await repo.classes(widget.school.id);
      final students = await repo.students(widget.school.id);
      _sessionId = await repo.currentSessionId(widget.school.id);
      final classByName = {for (final c in classes) _norm(c.name): c.id};
      final existing = {for (final s in students) _norm(s.admissionNumber)};
      final seen = <String>{};
      final rnd = Random.secure();

      String cell(List<String> r, int i) => (i >= 0 && i < r.length) ? r[i].trim() : '';
      final rows = <_Row>[];
      for (var i = 1; i < table.length; i++) {
        final r = table[i];
        final row = _Row(i + 1, {
          'adm': cell(r, cAdm),
          'first': cell(r, cFirst),
          'last': cell(r, cLast),
          'other': cell(r, cOther),
          'class': cell(r, cClass),
          'pin': cell(r, cPin),
          'pname': cell(r, cPName),
          'pemail': cell(r, cPEmail).toLowerCase(),
        });
        if (row.v['adm']!.isEmpty) row.problems.add('Admission number is empty');
        if (row.v['adm']!.length > 40) row.problems.add('Admission number is too long');
        if (row.v['first']!.isEmpty || row.v['last']!.isEmpty) row.problems.add('First or last name is empty');
        final cid = classByName[_norm(row.v['class']!)];
        if (cid == null) {
          row.problems.add('Class "${row.v['class']}" does not exist (add it under Classes first)');
        } else {
          row.classId = cid;
        }
        final adm = _norm(row.v['adm']!);
        if (adm.isNotEmpty) {
          if (!seen.add(adm)) row.problems.add('Appears twice in this list');
          if (existing.contains(adm)) row.exists = true;
        }
        if (row.v['pin']!.isNotEmpty && !_pinRe.hasMatch(row.v['pin']!)) {
          row.problems.add('PIN must be 6 to 32 letters or digits');
        }
        if (row.v['pemail']!.isNotEmpty && !_emailRe.hasMatch(row.v['pemail']!)) {
          row.problems.add('Parent email is not valid');
        }
        row.pin = row.v['pin']!.isNotEmpty ? row.v['pin']! : (100000 + rnd.nextInt(900000)).toString();
        rows.add(row);
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _checking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _headerError = friendlyError(e);
        _checking = false;
      });
    }
  }

  String _password() {
    const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _import() async {
    final ready = _rows.where((r) => r.ready).toList();
    if (ready.isEmpty) return;
    if (_sessionId == null) {
      notify(context, 'There is no current school year. Mark one as current first (School years & terms).', error: true);
      return;
    }
    final ok = await confirmDialog(context,
        title: 'Import ${ready.length} student${ready.length == 1 ? '' : 's'}?',
        message: 'Accounts are created now. The sign-in details are shown once at the end, so keep the screen open until then.',
        action: 'Import');
    if (!ok) return;

    setState(() {
      _running = true;
      _cancel = false;
      _progress = 0;
      _studentLogins.clear();
      _parentLogins.clear();
      _parentIds.clear();
    });
    final repo = SetupRepository.instance;
    final school = widget.school;

    for (final row in ready) {
      if (_cancel) break;
      try {
        final res = await repo.provision({
          'action': 'create',
          'school_id': school.id,
          'role': 'student',
          'student': {
            'admission_number': row.v['adm'],
            'first_name': row.v['first'],
            'last_name': row.v['last'],
            if (row.v['other']!.isNotEmpty) 'other_names': row.v['other'],
            'pin': row.pin,
            'class_id': row.classId,
            'session_id': _sessionId,
          },
        });
        final studentId = res['student_id'] as String?;
        row.status = 'created';
        _studentLogins.add(StudentLogin(row.v['adm']!, row.name, row.pin));

        final email = row.v['pemail']!;
        if (email.isNotEmpty && studentId != null) {
          try {
            final known = _parentIds[email];
            if (known != null) {
              await repo.linkParent(school.id, known, studentId);
            } else {
              final pw = _password();
              final pname = row.v['pname']!.isNotEmpty ? row.v['pname']! : 'Parent of ${row.v['first']}';
              final pr = await repo.provision({
                'action': 'create',
                'school_id': school.id,
                'role': 'parent',
                'email': email,
                'password': pw,
                'full_name': pname,
                'link_student_ids': [studentId],
              });
              _parentIds[email] = pr['user_id'] as String;
              _parentLogins.add(ParentLogin(pname, email, pw));
            }
          } on FunctionException catch (e) {
            row.message = e.status == 409
                ? 'Student added. That parent email already has an account: link them in People.'
                : 'Student added, but the parent account failed: ${provisionError(e)}';
          } catch (e) {
            row.message = 'Student added, but linking the parent failed: ${friendlyError(e)}';
          }
        }
      } catch (e) {
        row.status = 'failed';
        row.message = provisionError(e);
      }
      if (mounted) setState(() => _progress++);
    }
    if (mounted) {
      setState(() {
        _running = false;
        _done = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget body;
    if (_done) {
      body = _doneView(theme, cs);
    } else if (_running) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Importing ${_progress + 1 > _rows.where((r) => r.ready).length ? _progress : _progress + 1} of ${_rows.where((r) => r.ready).length}',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress / _rows.where((r) => r.ready).length, minHeight: 8),
            const SizedBox(height: 16),
            const Text('Please keep this screen open.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: () => setState(() => _cancel = true), child: const Text('Stop after this student')),
          ]),
        ),
      );
    } else if (_rows.isEmpty) {
      body = _inputView(theme, cs);
    } else {
      body = _previewView(theme, cs);
    }

    return PopScope(
      canPop: !_running,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Import students'),
          actions: const [
            HelpButton(
              title: 'Import students',
              steps: [
                'In Excel or Google Sheets, make a table with the columns shown on this screen and save it as CSV.',
                'Choose the file here, or paste the text. Then tap "Check the list".',
                'Fix any problems shown, then tap "Import". Students are put in their class for the current school year.',
                'At the end you get a printable list with each PIN and parent password. Hand them out privately.',
              ],
            ),
          ],
        ),
        body: body,
      ),
    );
  }

  Widget _inputView(ThemeData theme, ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const HintBanner(
          text: 'Required columns: admission_number, first_name, last_name, class (the class must already exist).\n'
              'Optional: other_names, pin, parent_name, parent_email. A missing PIN is generated for you.',
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(onPressed: _chooseFile, icon: const Icon(Icons.upload_file), label: const Text('Choose CSV file')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: _example));
                if (mounted) notify(context, 'Example copied. Paste it into a spreadsheet to see the layout.');
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy example'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          minLines: 8,
          maxLines: 14,
          decoration: const InputDecoration(labelText: 'Or paste the list here', alignLabelWithHint: true),
        ),
        if (_headerError != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
            child: Text(_headerError!, style: TextStyle(color: cs.onErrorContainer)),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _checking || _text.text.trim().isEmpty ? null : _check,
          child: _checking
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Text('Check the list'),
        ),
      ],
    );
  }

  Widget _previewView(ThemeData theme, ColorScheme cs) {
    final ready = _rows.where((r) => r.ready).length;
    final exist = _rows.where((r) => r.exists && r.problems.isEmpty).length;
    final bad = _rows.where((r) => r.problems.isNotEmpty).length;
    final shown = [..._rows.where((r) => r.problems.isNotEmpty), ..._rows.where((r) => r.exists && r.problems.isEmpty)];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        AppCard(
          child: Row(children: [
            _stat('Ready', ready, AppTheme.green),
            _stat('Already here', exist, Colors.grey),
            _stat('Need fixing', bad, cs.error),
          ]),
        ),
        const SizedBox(height: 12),
        if (bad > 0) const HintBanner(text: 'Rows that need fixing are skipped. Fix them in your file and check again, or import the ready ones now.'),
        for (final r in shown.take(40)) ...[
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Line ${r.line}: ${r.name.isEmpty ? '(no name)' : r.name}  ·  ${r.v['adm']}',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              if (r.exists && r.problems.isEmpty)
                Text('Already in the school, so it is skipped.', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              for (final p in r.problems) Text('• $p', style: theme.textTheme.bodySmall?.copyWith(color: cs.error)),
            ]),
          ),
        ],
        if (shown.length > 40) Padding(padding: const EdgeInsets.only(top: 8), child: Text('...and ${shown.length - 40} more.')),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: ready == 0 ? null : _import,
          icon: const Icon(Icons.group_add),
          label: Text('Import $ready student${ready == 1 ? '' : 's'}'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => setState(() => _rows = const []), child: const Text('Back to the list')),
      ],
    );
  }

  Widget _doneView(ThemeData theme, ColorScheme cs) {
    final created = _rows.where((r) => r.status == 'created').length;
    final failed = _rows.where((r) => r.status == 'failed').toList();
    final notes = _rows.where((r) => r.status == 'created' && r.message.isNotEmpty).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        AppCard(
          child: Row(children: [
            _stat('Added', created, AppTheme.green),
            _stat('Parents', _parentLogins.length, cs.primary),
            _stat('Failed', failed.length, failed.isEmpty ? Colors.grey : cs.error),
          ]),
        ),
        const SizedBox(height: 12),
        const HintBanner(
          icon: Icons.lock_outline,
          text: 'The PINs and passwords below are shown ONLY NOW and are not stored in the app. Print or copy them before you leave.',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _studentLogins.isEmpty
              ? null
              : () => printCredentials(schoolName: widget.school.name, students: _studentLogins, parents: _parentLogins),
          icon: const Icon(Icons.print_outlined),
          label: const Text('Print or save the login list (PDF)'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: credentialsText(widget.school.name, _studentLogins, _parentLogins)));
            if (mounted) notify(context, 'Copied. Paste it somewhere private.');
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy as text'),
        ),
        if (failed.isNotEmpty) ...[
          const SectionTitle('Could not add'),
          for (final r in failed) ...[
            AppCard(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Line ${r.line}: ${r.name}  ·  ${r.v['adm']}', style: theme.textTheme.titleSmall),
                Text(r.message, style: theme.textTheme.bodySmall?.copyWith(color: cs.error)),
              ]),
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (notes.isNotEmpty) ...[
          const SectionTitle('Added, with a note'),
          for (final r in notes) ...[
            AppCard(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r.name}  ·  ${r.v['adm']}', style: theme.textTheme.titleSmall),
                Text(r.message, style: theme.textTheme.bodySmall),
              ]),
            ),
            const SizedBox(height: 8),
          ],
        ],
        const SizedBox(height: 12),
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Finished')),
      ],
    );
  }

  Widget _stat(String label, int v, Color c) => Expanded(
        child: Column(children: [
          Text('$v', style: TextStyle(color: c, fontSize: 24, fontWeight: FontWeight.bold)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}
