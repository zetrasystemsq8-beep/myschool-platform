/// Small CSV reader (no extra package): handles quotes, commas inside quotes, a leading BOM,
/// Windows line endings, and picks comma, semicolon or tab from the header line.
List<List<String>> parseCsv(String input) {
  var text = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  final firstLine = text.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
  final candidates = {',': ','.allMatches(firstLine).length, ';': ';'.allMatches(firstLine).length, '\t': '\t'.allMatches(firstLine).length};
  final delimiter = (candidates.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;

  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;

  void endCell() {
    row.add(cell.toString().trim());
    cell.clear();
  }

  void endRow() {
    endCell();
    if (row.any((c) => c.isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == delimiter) {
      endCell();
    } else if (ch == '\n') {
      endRow();
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}
