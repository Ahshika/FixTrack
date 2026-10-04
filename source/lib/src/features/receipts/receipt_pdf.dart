import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/catalog.dart';
import '../../core/format.dart';
import '../../core/pos_models.dart';
import '../../core/shop.dart';
import '../../core/ticket_models.dart';
import '../../core/ticket_status.dart';

pw.ThemeData? _theme;

Future<pw.ThemeData> _loadTheme() async {
  if (_theme != null) return _theme!;
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Bold.ttf'));
  return _theme = pw.ThemeData.withFont(base: regular, bold: bold, fontFallback: [regular]);
}

PdfPageFormat paperFormat(String paper) => switch (paper) {
      '58mm' => const PdfPageFormat(58 * PdfPageFormat.mm, double.infinity, marginAll: 2 * PdfPageFormat.mm),
      'a5' => PdfPageFormat.a5.copyWith(marginLeft: 12 * PdfPageFormat.mm, marginRight: 12 * PdfPageFormat.mm, marginTop: 10 * PdfPageFormat.mm, marginBottom: 10 * PdfPageFormat.mm),
      'a4' => PdfPageFormat.a4.copyWith(marginLeft: 20 * PdfPageFormat.mm, marginRight: 20 * PdfPageFormat.mm, marginTop: 15 * PdfPageFormat.mm, marginBottom: 15 * PdfPageFormat.mm),
      _ => const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 3 * PdfPageFormat.mm),
    };

bool _isRoll(String paper) => paper == '80mm' || paper == '58mm';

/// وصل استلام الجهاز اللي بيتسلم للعميل.
Future<Uint8List> buildReceiptPdf(TicketDetail detail, ShopProfile shop, {String? paper}) async {
  final theme = await _loadTheme();
  final t = detail.ticket;
  final size = paper ?? shop.receiptPaper;
  final small = size == '58mm';
  final scale = small ? 0.85 : _isRoll(size) ? 1.0 : 1.15;
  final delivered = t.status == TicketStatus.delivered;
  final link = delivered ? null : shop.trackingLink(t.publicToken);
  final doc = pw.Document(theme: theme, title: 'وصل ${t.number}', author: shop.name);

  pw.TextStyle st(double s, {bool bold = false}) =>
      pw.TextStyle(fontSize: s * scale, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
  pw.Widget divider() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Divider(thickness: 0.6, borderStyle: pw.BorderStyle.dashed, color: PdfColors.grey700),
      );
  pw.Widget row(String label, String value, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: (small ? 44 : 58) * scale, child: pw.Text(label, style: st(8))),
            pw.Expanded(child: pw.Text(value, style: st(9, bold: bold))),
          ],
        ),
      );

  final content = pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      if (shop.logo != null)
        pw.Center(child: pw.Image(pw.MemoryImage(shop.logo!), height: 44 * scale, fit: pw.BoxFit.contain)),
      pw.Center(child: pw.Text(shop.name, style: st(14, bold: true), textAlign: pw.TextAlign.center)),
      if (shop.branchName != null) pw.Center(child: pw.Text(shop.branchName!, style: st(8))),
      if (shop.phone != null) pw.Center(child: pw.Text(shop.phone!, style: st(9), textDirection: pw.TextDirection.ltr)),
      if (shop.address != null) pw.Center(child: pw.Text(shop.address!, style: st(8), textAlign: pw.TextAlign.center)),
      divider(),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(delivered ? 'فاتورة صيانة' : 'وصل استلام جهاز', style: st(11, bold: true)),
          pw.Text('#${t.number}', style: st(16, bold: true), textDirection: pw.TextDirection.ltr),
        ],
      ),
      pw.Text(latinDigits(formatDateTime(t.createdAt)), style: st(8)),
      divider(),
      row('العميل', t.customerName, bold: true),
      row('التليفون', t.customerPhone),
      divider(),
      row('الجهاز', '${t.deviceName}${t.color != null ? ' - ${t.color}' : ''}', bold: true),
      if (t.deviceType != 'phone') row('النوع', deviceTypes[t.deviceType] ?? ''),
      if (t.imei != null) row('IMEI', t.imei!),
      row('المشكلة', [...t.problems, ?t.problemDesc].join(' - ')),
      if (t.powersOn != null) row('بيفتح؟', t.powersOn! ? 'أيوه' : 'لأ'),
      if (t.conditionFlags.isNotEmpty) row('الحالة', t.conditionFlags.join('، ')),
      if (t.accessories.isNotEmpty) row('مع الجهاز', t.accessories.join('، ')),
      divider(),
      if (t.totalCents > 0) row(t.finalCents != null ? 'التكلفة' : 'التكلفة المبدئية', money(t.totalCents)),
      if (t.paidCents > 0) row('المدفوع', money(t.paidCents)),
      if (t.totalCents > 0) row('الباقي', money(t.remainingCents), bold: true),
      if (t.dueAt != null && !delivered) row('الموعد المتوقع', formatDateTime(t.dueAt!), bold: true),
      if (delivered) ...[
        for (final part in detail.parts) row('قطعة غيار', '${part['name']} × ${part['qty']}'),
        if (t.deliveredAt != null) row('اتسلم', formatDateTime(t.deliveredAt!)),
        if (t.warrantyUntil != null) row('الضمان', '${t.warrantyDays ?? ''} يوم لحد ${formatDate(t.warrantyUntil!)}', bold: true),
      ],
      pw.SizedBox(height: 6),
      if (t.pickupPin != null && !delivered)
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.2), borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Column(children: [
            pw.Text('كود الاستلام', style: st(8)),
            pw.Text(t.pickupPin!, style: st(20, bold: true).copyWith(letterSpacing: 4), textDirection: pw.TextDirection.ltr),
            pw.Text('هتحتاجه وإنت بتستلم الجهاز', style: st(7)),
          ]),
        ),
      if (link != null) ...[
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium),
            drawText: false,
            data: link,
            width: (small ? 90 : 110) * scale,
            height: (small ? 90 : 110) * scale,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Center(child: pw.Text('امسح الكود بكاميرا الموبايل وتابع حالة جهازك', style: st(8, bold: true), textAlign: pw.TextAlign.center)),
      ],
      if (shop.receiptTerms.trim().isNotEmpty) ...[
        divider(),
        pw.Text(shop.receiptTerms.trim(), style: st(6.5)),
      ],
      pw.SizedBox(height: 6),
      pw.Center(child: pw.Text('FixTrack', style: st(6).copyWith(color: PdfColors.grey600))),
    ],
  );

  doc.addPage(pw.Page(
    pageFormat: paperFormat(size),
    textDirection: pw.TextDirection.rtl,
    build: (_) => _isRoll(size) ? content : pw.Center(child: pw.SizedBox(width: 110 * PdfPageFormat.mm, child: content)),
  ));
  return doc.save();
}

/// ستيكر صغير بيتلزق على الجهاز نفسه جوه المحل.
Future<Uint8List> buildStickerPdf(TicketDetail detail, ShopProfile shop, {String? paper}) async {
  final theme = await _loadTheme();
  final t = detail.ticket;
  final size = paper ?? shop.receiptPaper;
  final link = shop.trackingLink(t.publicToken);
  final doc = pw.Document(theme: theme, title: 'ستيكر ${t.number}');
  final roll = _isRoll(size);

  final sticker = pw.Container(
    padding: const pw.EdgeInsets.all(4),
    decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8), borderRadius: pw.BorderRadius.circular(3)),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('#${t.number}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold), textDirection: pw.TextDirection.ltr),
              pw.Text(t.customerName, style: const pw.TextStyle(fontSize: 9), maxLines: 1),
              pw.Text(t.deviceName, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), maxLines: 1),
              pw.Text(t.problems.isNotEmpty ? t.problems.join('، ') : (t.problemDesc ?? ''), style: const pw.TextStyle(fontSize: 7), maxLines: 2),
              if (t.dueAt != null) pw.Text('التسليم: ${formatDay(t.dueAt!)}', style: const pw.TextStyle(fontSize: 7)),
            ],
          ),
        ),
        if (link != null)
          pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: link, width: 52, height: 52, drawText: false),
      ],
    ),
  );

  doc.addPage(pw.Page(
    pageFormat: roll ? paperFormat(size) : const PdfPageFormat(60 * PdfPageFormat.mm, 35 * PdfPageFormat.mm, marginAll: 2 * PdfPageFormat.mm),
    textDirection: pw.TextDirection.rtl,
    build: (_) => sticker,
  ));
  return doc.save();
}

/// فاتورة بيع (كاشير).
Future<Uint8List> buildSalePdf(SaleDetail detail, ShopProfile shop, {String? paper}) async {
  final theme = await _loadTheme();
  final s = detail.sale;
  final size = paper ?? shop.receiptPaper;
  final small = size == '58mm';
  final scale = small ? 0.85 : _isRoll(size) ? 1.0 : 1.15;
  final doc = pw.Document(theme: theme, title: 'فاتورة ${s.number}', author: shop.name);

  pw.TextStyle st(double v, {bool bold = false}) =>
      pw.TextStyle(fontSize: v * scale, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
  pw.Widget divider() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Divider(thickness: 0.6, borderStyle: pw.BorderStyle.dashed, color: PdfColors.grey700),
      );
  pw.Widget total(String label, String value, {bool bold = false}) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(label, style: st(bold ? 11 : 9, bold: bold)), pw.Text(value, style: st(bold ? 12 : 9, bold: bold))],
      );

  final content = pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      if (shop.logo != null) pw.Center(child: pw.Image(pw.MemoryImage(shop.logo!), height: 40 * scale, fit: pw.BoxFit.contain)),
      pw.Center(child: pw.Text(shop.name, style: st(14, bold: true), textAlign: pw.TextAlign.center)),
      if (shop.phone != null) pw.Center(child: pw.Text(shop.phone!, style: st(9), textDirection: pw.TextDirection.ltr)),
      if (shop.address != null) pw.Center(child: pw.Text(shop.address!, style: st(8), textAlign: pw.TextAlign.center)),
      divider(),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('فاتورة بيع', style: st(11, bold: true)),
        pw.Text('#${s.number}', style: st(14, bold: true), textDirection: pw.TextDirection.ltr),
      ]),
      pw.Text(formatDateTime(s.createdAt), style: st(8)),
      if (s.customerName != null) pw.Text('العميل: ${s.customerName}', style: st(9)),
      if (s.userName != null) pw.Text('الكاشير: ${s.userName}', style: st(8)),
      divider(),
      for (final i in detail.items) ...[
        pw.Text(i.name, style: st(9, bold: true)),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('${i.qty} × ${money(i.unitPriceCents)}', style: st(8)),
          pw.Text(money(i.qty * i.unitPriceCents), style: st(9)),
        ]),
        if (i.imei != null) pw.Text('IMEI: ${i.imei}${i.condition == 'used' ? ' (مستعمل)' : ''}', style: st(8)),
        if (i.warrantyMonths > 0)
          pw.Text(
            'ضمان ${i.warrantyMonths} شهر لحد ${formatDate(DateTime(s.createdAt.year, s.createdAt.month + i.warrantyMonths, s.createdAt.day))}',
            style: st(8, bold: true),
          ),
        if (i.returnedQty > 0) pw.Text('مرتجع: ${i.returnedQty}', style: st(7)),
        pw.SizedBox(height: 3),
      ],
      divider(),
      if (s.discountCents > 0) ...[total('الإجمالي', money(s.subtotalCents)), total('خصم', '- ${money(s.discountCents)}')],
      total('المطلوب', money(s.totalCents), bold: true),
      for (final p in detail.payments.where((p) => p.type == 'sale')) total('مدفوع (${p.method.label})', money(p.amountCents)),
      if (s.returnedCents > 0) total('مرتجع', money(s.returnedCents)),
      if (s.dueCents > 0) total('الباقي (آجل)', money(s.dueCents), bold: true),
      pw.SizedBox(height: 8),
      pw.Center(child: pw.Text('شكراً لزيارتكم', style: st(9, bold: true))),
      pw.Center(child: pw.Text('الاستبدال والاسترجاع بالفاتورة', style: st(7))),
      pw.SizedBox(height: 4),
      pw.Center(child: pw.Text('FixTrack', style: st(6).copyWith(color: PdfColors.grey600))),
    ],
  );

  doc.addPage(pw.Page(
    pageFormat: paperFormat(size),
    textDirection: pw.TextDirection.rtl,
    build: (_) => _isRoll(size) ? content : pw.Center(child: pw.SizedBox(width: 110 * PdfPageFormat.mm, child: content)),
  ));
  return doc.save();
}

/// ستيكرات باركود للأصناف: ستيكر 50×30 مم لكل صنف (طابعة ليبل) أو ورقة A4 عليها كذا ستيكر.
Future<Uint8List> buildBarcodeLabelsPdf(List<({Product product, int copies})> items, ShopProfile shop, {bool a4 = false}) async {
  final theme = await _loadTheme();
  final doc = pw.Document(theme: theme, title: 'باركود');
  pw.Widget label(Product p) {
    final code = p.barcode!;
    final ean = code.length == 13 && RegExp(r'^\d+$').hasMatch(code);
    return pw.Container(
      width: 48 * PdfPageFormat.mm,
      padding: const pw.EdgeInsets.all(3),
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(shop.name, style: const pw.TextStyle(fontSize: 6), maxLines: 1),
          pw.Text(p.name, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold), maxLines: 1),
          pw.SizedBox(height: 2),
          pw.BarcodeWidget(
            barcode: ean ? pw.Barcode.ean13() : pw.Barcode.code128(),
            data: code,
            height: 26,
            width: 120,
            textStyle: const pw.TextStyle(fontSize: 6),
          ),
          pw.Text(money(p.priceCents), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  final labels = [
    for (final i in items.where((i) => i.product.barcode != null))
      for (var k = 0; k < i.copies; k++) label(i.product),
  ];
  if (a4) {
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.copyWith(marginLeft: 20, marginRight: 20, marginTop: 20, marginBottom: 20),
      textDirection: pw.TextDirection.rtl,
      build: (_) => [pw.Wrap(spacing: 6, runSpacing: 6, children: labels)],
    ));
  } else {
    for (final l in labels) {
      doc.addPage(pw.Page(
        pageFormat: const PdfPageFormat(50 * PdfPageFormat.mm, 30 * PdfPageFormat.mm, marginAll: 1 * PdfPageFormat.mm),
        textDirection: pw.TextDirection.rtl,
        build: (_) => pw.Center(child: l),
      ));
    }
  }
  return doc.save();
}

/// إيصال شرا موبايل مستعمل من زبون: البائع بيمضي عليه إن الجهاز ملكه.
Future<Uint8List> buildUsedPurchasePdf(PhoneUnit u, ShopProfile shop) async {
  final theme = await _loadTheme();
  final doc = pw.Document(theme: theme, title: 'إيصال شرا ${u.imei}');
  pw.TextStyle st(double v, {bool bold = false}) => pw.TextStyle(fontSize: v, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
  pw.Widget row(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 62, child: pw.Text(label, style: st(8))),
          pw.Expanded(child: pw.Text(value, style: st(9, bold: true))),
        ]),
      );
  pw.Widget divider() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Divider(thickness: 0.6, borderStyle: pw.BorderStyle.dashed, color: PdfColors.grey700),
      );
  final size = shop.receiptPaper;
  final content = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
    pw.Center(child: pw.Text(shop.name, style: st(14, bold: true))),
    if (shop.phone != null) pw.Center(child: pw.Text(shop.phone!, style: st(9), textDirection: pw.TextDirection.ltr)),
    divider(),
    pw.Center(child: pw.Text('إيصال شرا جهاز مستعمل', style: st(12, bold: true))),
    pw.Center(child: pw.Text(formatDateTime(u.createdAt ?? DateTime.now()), style: st(8))),
    divider(),
    row('الجهاز', u.productName),
    row('IMEI', u.imei),
    if (u.imei2 != null) row('IMEI 2', u.imei2!),
    if (u.details.isNotEmpty) row('المواصفات', u.details),
    if (u.notes != null) row('الحالة', u.notes!),
    divider(),
    row('البائع', u.sellerName ?? ''),
    row('الرقم القومي', u.sellerNationalId ?? ''),
    row('التليفون', u.sellerPhone ?? ''),
    row('المبلغ', money(u.costCents ?? 0)),
    divider(),
    pw.Text(
      'أقر أنا البائع المذكور أعلاه بأن الجهاز ملكي الخاص، وأنه غير مسروق أو محل نزاع، '
      'وأتحمل المسئولية القانونية كاملة في حالة ثبوت عكس ذلك، وقد استلمت المبلغ المذكور كاملاً.',
      style: st(8),
    ),
    pw.SizedBox(height: 18),
    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('توقيع البائع: ..................', style: st(8)),
      pw.Text('البصمة', style: st(8)),
    ]),
    pw.SizedBox(height: 14),
    pw.Text('توقيع المحل: ..................', style: st(8)),
    pw.SizedBox(height: 8),
    pw.Center(child: pw.Text('FixTrack', style: st(6).copyWith(color: PdfColors.grey600))),
  ]);
  doc.addPage(pw.Page(
    pageFormat: paperFormat(size),
    textDirection: pw.TextDirection.rtl,
    build: (_) => _isRoll(size) ? content : pw.Center(child: pw.SizedBox(width: 110 * PdfPageFormat.mm, child: content)),
  ));
  return doc.save();
}
