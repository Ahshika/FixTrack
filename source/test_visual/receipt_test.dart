// بيطلع ملفات PDF للوصل والستيكر ببيانات تجريبية للمراجعة (test_visual/shots/*.pdf).
import 'dart:io';

import 'package:fixtrack/src/core/shop.dart';
import 'package:fixtrack/src/core/ticket_models.dart';
import 'package:fixtrack/src/features/receipts/receipt_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final detail = TicketDetail({
    'ticket': {
      'id': 't1', 'number': 1042, 'status': 'received', 'deviceType': 'phone',
      'brand': 'Samsung', 'model': 'Galaxy A55', 'color': 'أسود', 'imei': '356789104561234',
      'problems': ['الشاشة', 'البطارية'], 'problemDesc': 'الشاشة بتنور بس مفيش صورة',
      'powersOn': true, 'conditionFlags': ['خدوش'], 'accessories': ['جراب', 'شريحة'],
      'customerId': 'c1', 'customerName': 'أحمد علي', 'customerPhone': '0100 123 4567',
      'estimatedCents': 250000, 'paidCents': 50000, 'pickupPin': '4821',
      'publicToken': 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-abcd',
      'dueAt': DateTime.now().add(const Duration(days: 1)).toUtc().toIso8601String(),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    },
    'events': [], 'payments': [],
  });
  final shop = ShopProfile({
    'name': 'محل النور لصيانة الموبايلات', 'phone': '0100 555 6677', 'address': 'شارع 9، المعادي، القاهرة',
    'branchName': 'فرع المعادي', 'receiptTerms': 'المحل غير مسؤول عن الأجهزة اللي بتعدّي 30 يوم من غير استلام.\nلازم تقدّم الوصل أو كود الاستلام وقت الاستلام.',
    'receiptPaper': '80mm', 'trackingBaseUrl': 'https://fixtrack-7fcf9.web.app',
  });

  test('render receipts', () async {
    await initializeDateFormatting('ar');
    Directory('test_visual/shots').createSync(recursive: true);
    for (final paper in ['80mm', '58mm', 'a5']) {
      File('test_visual/shots/receipt_$paper.pdf').writeAsBytesSync(await buildReceiptPdf(detail, shop, paper: paper));
    }
    File('test_visual/shots/sticker.pdf').writeAsBytesSync(await buildStickerPdf(detail, shop));
  });
}
