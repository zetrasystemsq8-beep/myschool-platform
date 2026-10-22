import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'models.dart';

class StudentLogin {
  const StudentLogin(this.admission, this.name, this.pin);
  final String admission;
  final String name;
  final String pin;
}

class ParentLogin {
  const ParentLogin(this.name, this.email, this.password);
  final String name;
  final String email;
  final String password;
}

/// Plain-text copy of the new logins (for pasting into a document).
String credentialsText(String schoolName, List<StudentLogin> students, List<ParentLogin> parents) {
  final b = StringBuffer('$schoolName - new logins (keep private)\n\nSTUDENTS (sign in with School ID + admission number + PIN)\n');
  for (final s in students) {
    b.writeln('${s.admission}, ${s.name}, PIN ${s.pin}');
  }
  if (parents.isNotEmpty) {
    b.writeln('\nPARENTS (sign in with email + password)');
    for (final p in parents) {
      b.writeln('${p.name}, ${p.email}, password ${p.password}');
    }
  }
  return b.toString();
}

/// A printable list of the new logins so the school can hand them out. Opens the print / save-as-PDF screen.
Future<void> printCredentials({
  required String schoolName,
  required List<StudentLogin> students,
  required List<ParentLogin> parents,
}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));
  const green = PdfColor.fromInt(0xFF0B5D3B);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      footer: (ctx) => pw.Text('Confidential. Created ${formatDate(DateTime.now())}.  Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      build: (ctx) => [
        pw.Text(schoolName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: green)),
        pw.SizedBox(height: 4),
        pw.Text('New sign-in details. Give each person only their own line, and ask them to change their PIN or password after the first sign-in.',
            style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 14),
        if (students.isNotEmpty) ...[
          pw.Text('Students', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: ['Admission number', 'Name', 'PIN'],
            data: [for (final s in students) [s.admission, s.name, s.pin]],
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: green),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            border: pw.TableBorder(horizontalInside: const pw.BorderSide(color: PdfColors.grey300)),
          ),
          pw.SizedBox(height: 16),
        ],
        if (parents.isNotEmpty) ...[
          pw.Text('Parents', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: ['Name', 'Email', 'Password'],
            data: [for (final p in parents) [p.name, p.email, p.password]],
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: green),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            border: pw.TableBorder(horizontalInside: const pw.BorderSide(color: PdfColors.grey300)),
          ),
        ],
      ],
    ),
  );

  await Printing.layoutPdf(name: 'New logins - $schoolName', onLayout: (_) async => doc.save());
}
