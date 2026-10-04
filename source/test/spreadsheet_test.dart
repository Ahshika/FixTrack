import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fixtrack/src/core/spreadsheet.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _xlsx() {
  final a = Archive();
  void add(String path, String text) {
    final data = utf8.encode(text);
    a.addFile(ArchiveFile(path, data.length, data));
  }

  add('xl/workbook.xml',
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="الأصناف" sheetId="1" r:id="rId1"/></sheets></workbook>');
  add('xl/_rels/workbook.xml.rels',
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/></Relationships>');
  add('xl/sharedStrings.xml',
      '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>الاسم</t></si><si><t>السعر</t></si><si><t>باركود</t></si><si><t>جراب شفاف</t></si></sst>');
  add('xl/worksheets/sheet1.xml',
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
      '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c></row>'
      '<row r="2"><c r="A2" t="s"><v>3</v></c><c r="B2"><v>49.999999999</v></c><c r="C2"><v>6221234567890</v></c></row>'
      '<row r="3"><c r="A3" t="inlineStr"><is><t>شاحن</t></is></c><c r="C3"><v>123</v></c></row>'
      '</sheetData></worksheet>');
  return Uint8List.fromList(ZipEncoder().encode(a));
}

void main() {
  test('reads xlsx with shared strings, inline strings, gaps and long numbers', () {
    final rows = SpreadsheetReader.read(_xlsx(), 'items.xlsx');
    expect(rows[0], ['الاسم', 'السعر', 'باركود']);
    expect(rows[1], ['جراب شفاف', '50', '6221234567890']);
    expect(rows[2], ['شاحن', '', '123']);
  });

  test('reads csv with quotes, semicolons and BOM', () {
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('الاسم;السعر\n"جراب ""شفاف""";50\r\nشاحن;120\n')]);
    final rows = SpreadsheetReader.read(bytes, 'x.csv');
    expect(rows, [
      ['الاسم', 'السعر'],
      ['جراب "شفاف"', '50'],
      ['شاحن', '120'],
    ]);
  });

  test('falls back to Windows-1256 for old Arabic CSV files', () {
    // "جراب" بترميز Windows-1256
    final bytes = Uint8List.fromList([0xCC, 0xD1, 0xC7, 0xC8, 0x2C, 0x35]);
    expect(SpreadsheetReader.read(bytes, 'old.csv'), [
      ['جراب', '5'],
    ]);
  });

  test('Windows-1256 table covers the first and last high bytes', () {
    final rows = SpreadsheetReader.read(Uint8List.fromList([0x80, 0xFF, 0x2C, 0xC1, 0xE3]), 'x.csv');
    expect(rows.single, ['€ے', 'ءم']);
  });

  test('xlsx writer round-trips through the reader (Arabic, numbers, escaping)', () {
    final w = XlsxWriter()
      ..addSheet('المبيعات', [
        ['الصنف', 'الكمية', 'الإيراد'],
        ['جراب <شفاف> & "سيليكون"', 3, 225.5],
        ['شاحن', null, 450],
      ])
      ..addSheet('ملخص', [
        ['صافي الربح', 95000],
      ]);
    final rows = SpreadsheetReader.read(w.build(), 'report.xlsx');
    expect(rows[0], ['الصنف', 'الكمية', 'الإيراد']);
    expect(rows[1], ['جراب <شفاف> & "سيليكون"', '3', '225.5']);
    expect(rows[2], ['شاحن', '', '450']);
  });

  test('old .xls gives a clear message', () {
    expect(() => SpreadsheetReader.read(Uint8List(10), 'old.xls'), throwsA(isA<FormatException>()));
  });
}
