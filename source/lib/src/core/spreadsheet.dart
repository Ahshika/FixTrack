import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// قارئ بسيط لملفات Excel (xlsx) و CSV عشان استيراد البيانات من البرنامج القديم.
/// بيرجع أول شيت كجدول صفوف ونصوص.
class SpreadsheetReader {
  static List<List<String>> read(Uint8List bytes, String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.csv') || lower.endsWith('.txt')) return readCsv(_decodeText(bytes));
    if (lower.endsWith('.xls')) {
      throw const FormatException('ملفات .xls القديمة مش مدعومة. افتح الملف في Excel واحفظه باسم "Excel Workbook (.xlsx)" أو CSV.');
    }
    return readXlsx(bytes);
  }

  static String _decodeText(Uint8List bytes) {
    // CSV من Excel العربي ساعات بيبقى UTF-8 بـ BOM وساعات Windows-1256؛ بنجرب UTF-8 الأول
    var b = bytes;
    if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) b = b.sublist(3);
    try {
      return utf8.decode(b);
    } on FormatException {
      return _cp1256.decode(b);
    }
  }

  static List<List<String>> readCsv(String text) {
    final delimiter = _guessDelimiter(text);
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"') {
        quoted = true;
      } else if (ch == delimiter) {
        row.add(cell.toString().trim());
        cell.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString().trim());
        cell.clear();
        if (row.any((c) => c.isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        cell.write(ch);
      }
    }
    row.add(cell.toString().trim());
    if (row.any((c) => c.isNotEmpty)) rows.add(row);
    return rows;
  }

  static String _guessDelimiter(String text) {
    final firstLine = text.split('\n').first;
    final counts = {',': ','.allMatches(firstLine).length, ';': ';'.allMatches(firstLine).length, '\t': '\t'.allMatches(firstLine).length};
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  static List<List<String>> readXlsx(Uint8List bytes) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('الملف ده مش ملف Excel صالح');
    }
    String? file(String path) {
      final f = zip.findFile(path);
      return f == null ? null : utf8.decode(f.content as List<int>);
    }

    // الشيت الأول حسب ترتيب الـ workbook
    var sheetPath = 'xl/worksheets/sheet1.xml';
    final workbook = file('xl/workbook.xml');
    final rels = file('xl/_rels/workbook.xml.rels');
    if (workbook != null && rels != null) {
      final firstSheet = XmlDocument.parse(workbook).findAllElements('sheet').firstOrNull;
      final rid = firstSheet?.getAttribute('r:id') ?? firstSheet?.attributes.where((a) => a.name.local == 'id').firstOrNull?.value;
      final target = XmlDocument.parse(rels)
          .findAllElements('Relationship')
          .where((r) => r.getAttribute('Id') == rid)
          .firstOrNull
          ?.getAttribute('Target');
      if (target != null) sheetPath = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    }
    final sheet = file(sheetPath);
    if (sheet == null) throw const FormatException('مفيش شيت في الملف');

    final shared = <String>[];
    final sst = file('xl/sharedStrings.xml');
    if (sst != null) {
      for (final si in XmlDocument.parse(sst).findAllElements('si')) {
        shared.add(si.findAllElements('t').map((t) => t.innerText).join());
      }
    }

    final rows = <List<String>>[];
    for (final r in XmlDocument.parse(sheet).findAllElements('row')) {
      final cells = <int, String>{};
      var nextCol = 0;
      for (final c in r.findElements('c')) {
        final ref = c.getAttribute('r');
        final col = ref == null ? nextCol : _columnIndex(ref);
        nextCol = col + 1;
        final type = c.getAttribute('t');
        String value;
        if (type == 'inlineStr') {
          value = c.findAllElements('t').map((t) => t.innerText).join();
        } else {
          final v = c.findElements('v').firstOrNull?.innerText ?? '';
          value = type == 's' ? (int.tryParse(v) != null && int.parse(v) < shared.length ? shared[int.parse(v)] : '') : _cleanNumber(v);
        }
        cells[col] = value.trim();
      }
      if (cells.values.every((v) => v.isEmpty)) continue;
      final width = cells.keys.fold<int>(0, (m, k) => k > m ? k : m) + 1;
      rows.add(List.generate(width, (i) => cells[i] ?? ''));
    }
    return rows;
  }

  /// "B12" ← 1
  static int _columnIndex(String ref) {
    var n = 0;
    for (final ch in ref.codeUnits) {
      if (ch < 65 || ch > 90) break;
      n = n * 26 + (ch - 64);
    }
    return n - 1;
  }

  /// Excel بيخزن 12.5 أحياناً كـ 12.499999999; وبيخزن الباركود الطويل كرقم. بنرجعه نص نضيف.
  static String _cleanNumber(String v) {
    final raw = double.tryParse(v);
    if (raw == null) return v;
    final d = raw.abs() < 1e15 ? double.parse(raw.toStringAsFixed(6)) : raw;
    if (d == d.roundToDouble() && d.abs() < 1e15) return d.toStringAsFixed(0);
    return d.toString();
  }
}

/// Windows-1256 (Arabic) ← Unicode للحروف فوق 0x80.
const _cp1256 = _Cp1256Decoder();

class _Cp1256Decoder {
  const _Cp1256Decoder();

  static const _high = '€پ‚ƒ„…†‡ˆ‰ٹ‹Œچژڈگ‘’“”•–—ک™ڑ›œ‌‍ں ،¢£¤¥¦§¨©ھ«¬­®¯°±²³´µ¶·¸¹؛»¼½¾؟ہءآأؤإئابةتثجحخدذرزسشصض×طظعغـفقكàلâمنهوçèéêëىيîïًٌٍَôُِ÷ّùْûü‎‏ے';

  String decode(List<int> bytes) =>
      String.fromCharCodes(bytes.map((b) => b < 0x80 ? b : _high.codeUnitAt(b - 0x80)));
}

/// كاتب بسيط لملفات Excel (xlsx): كذا شيت، نصوص وأرقام، والشيت من اليمين للشمال.
class XlsxWriter {
  final _sheets = <({String name, List<List<Object?>> rows})>[];

  void addSheet(String name, List<List<Object?>> rows) {
    final safe = name.replaceAll(RegExp(r'[\/?*\[\]:]'), ' ');
    _sheets.add((name: safe.length > 31 ? safe.substring(0, 31) : safe, rows: rows));
  }

  static String _esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  static String _col(int i) {
    var s = '';
    for (var n = i + 1; n > 0; n = (n - 1) ~/ 26) {
      s = String.fromCharCode(65 + (n - 1) % 26) + s;
    }
    return s;
  }

  Uint8List build() {
    final a = Archive();
    void add(String path, String xml) {
      final data = utf8.encode(xml);
      a.addFile(ArchiveFile(path, data.length, data));
    }

    const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
    const rns = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
    add('[Content_Types].xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '${[for (var i = 0; i < _sheets.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '</Types>');
    add('_rels/.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="$rns/officeDocument" Target="xl/workbook.xml"/></Relationships>');
    add('xl/workbook.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="$ns" xmlns:r="$rns"><sheets>'
        '${[for (var i = 0; i < _sheets.length; i++) '<sheet name="${_esc(_sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
        '</sheets></workbook>');
    add('xl/_rels/workbook.xml.rels',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var i = 0; i < _sheets.length; i++) '<Relationship Id="rId${i + 1}" Type="$rns/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
        '<Relationship Id="rId${_sheets.length + 1}" Type="$rns/styles" Target="styles.xml"/></Relationships>');
    // ستايل 1 = عنوان (بولد)
    add('xl/styles.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="$ns">'
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs>'
        '<cellXfs count="2"><xf/><xf fontId="1" applyFont="1"/></cellXfs></styleSheet>');
    for (var s = 0; s < _sheets.length; s++) {
      final b = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="$ns">'
          '<sheetViews><sheetView workbookViewId="0" rightToLeft="1"/></sheetViews><sheetData>');
      final rows = _sheets[s].rows;
      for (var r = 0; r < rows.length; r++) {
        b.write('<row r="${r + 1}">');
        for (var c = 0; c < rows[r].length; c++) {
          final v = rows[r][c];
          final ref = '${_col(c)}${r + 1}';
          final style = r == 0 ? ' s="1"' : '';
          if (v == null) continue;
          if (v is num) {
            b.write('<c r="$ref"$style><v>$v</v></c>');
          } else {
            b.write('<c r="$ref" t="inlineStr"$style><is><t xml:space="preserve">${_esc('$v')}</t></is></c>');
          }
        }
        b.write('</row>');
      }
      b.write('</sheetData></worksheet>');
      add('xl/worksheets/sheet${s + 1}.xml', b.toString());
    }
    return Uint8List.fromList(ZipEncoder().encode(a));
  }
}
