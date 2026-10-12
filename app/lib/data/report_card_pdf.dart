import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'models.dart';

/// Builds a printable term report card from PUBLISHED results only (the caller passes a
/// [TermGroup] that came from the published_results view) and opens the system print / save-as-PDF screen.
/// A bundled font is used so names with characters like "ọ" or "ẹ" print correctly.
Future<void> printReportCard({
  required String schoolName,
  required String studentName,
  required String admissionNumber,
  required TermGroup term,
  required List<GradeBand> scale,
}) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));

  const green = PdfColor.fromInt(0xFF0B5D3B);
  const gold = PdfColor.fromInt(0xFFC9A227);
  const grey = PdfColor.fromInt(0xFF666666);

  pw.Widget info(String label, String value) => pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: grey)),
          pw.SizedBox(height: 2),
          pw.Text(value, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        ]),
      );

  final ordered = [...scale]..sort((a, b) => b.minScore.compareTo(a.minScore));
  final legend = ordered.map((b) => '${b.grade} (${_n(b.minScore)}+)').join('   ');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      footer: (ctx) => pw.Text(
        'Generated from results published by the school on ${formatDate(DateTime.now())}.   Page ${ctx.pageNumber} of ${ctx.pagesCount}',
        style: const pw.TextStyle(fontSize: 8, color: grey),
      ),
      build: (ctx) => [
        pw.Container(
          color: green,
          padding: const pw.EdgeInsets.all(16),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(schoolName,
                style: pw.TextStyle(color: PdfColors.white, fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Terminal Report Card', style: const pw.TextStyle(color: gold, fontSize: 13)),
          ]),
        ),
        pw.SizedBox(height: 16),
        pw.Row(children: [
          info('STUDENT', studentName),
          info('ADMISSION NO.', admissionNumber),
        ]),
        pw.SizedBox(height: 10),
        pw.Row(children: [
          info('CLASS', term.className),
          info('TERM', term.termName),
          info('SCHOOL YEAR', term.sessionName),
        ]),
        pw.SizedBox(height: 18),
        pw.TableHelper.fromTextArray(
          headers: ['Subject', 'Test', 'Exam', 'Total', 'Grade', 'Remark'],
          data: [
            for (final r in term.rows)
              [r.subjectName, _n(r.ca), _n(r.exam), _n(r.total), r.grade ?? '-', r.remark ?? ''],
          ],
          headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
          headerDecoration: const pw.BoxDecoration(color: green),
          cellStyle: const pw.TextStyle(fontSize: 10),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(1),
            4: const pw.FlexColumnWidth(1),
            5: const pw.FlexColumnWidth(3),
          },
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.center,
            2: pw.Alignment.center,
            3: pw.Alignment.center,
            4: pw.Alignment.center,
            5: pw.Alignment.centerLeft,
          },
          border: pw.TableBorder(
            bottom: const pw.BorderSide(color: PdfColors.grey300),
            horizontalInside: const pw.BorderSide(color: PdfColors.grey300),
          ),
        ),
        pw.SizedBox(height: 14),
        pw.Row(children: [
          info('SUBJECTS', '${term.rows.length}'),
          info('TOTAL SCORE', _n(term.totalScore)),
          info('AVERAGE', _n(term.average)),
        ]),
        pw.SizedBox(height: 14),
        if (legend.isNotEmpty) ...[
          pw.Text('GRADING', style: const pw.TextStyle(fontSize: 9, color: grey)),
          pw.SizedBox(height: 2),
          pw.Text(legend, style: const pw.TextStyle(fontSize: 10)),
        ],
        pw.SizedBox(height: 40),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          _signature('Class teacher'),
          _signature('Head of school'),
          _signature('Parent / guardian'),
        ]),
      ],
    ),
  );

  await Printing.layoutPdf(
    name: 'Report card - $studentName - ${term.label}',
    onLayout: (_) async => doc.save(),
  );
}

pw.Widget _signature(String label) => pw.Column(children: [
      pw.Container(width: 130, height: 1, color: PdfColors.grey600),
      pw.SizedBox(height: 4),
      pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
    ]);

String _n(double? v) => fmt(v);
