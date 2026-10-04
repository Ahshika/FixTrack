import 'package:intl/intl.dart';

const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';

/// بيحوّل الأرقام العربي (٠١٢) لإنجليزي (012) عشان الأرقام تبقى شكل واحد في البرنامج كله.
String latinDigits(String s) {
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = _arabicDigits.indexOf(ch);
    b.write(i >= 0 ? '$i' : ch);
  }
  return b.toString();
}

final _moneyFormat = NumberFormat('#,##0.##', 'en');

String money(int cents) => '${_moneyFormat.format(cents / 100)} ج.م';

/// "2,500" أو "٢٥٠٠" أو "2500.5" ← قروش. بيرجع null لو المكتوب مش رقم.
int? parseMoney(String input) {
  final cleaned = latinDigits(input).replaceAll(RegExp(r'[,\s٬ج.م]'), '').replaceAll('٫', '.');
  if (cleaned.isEmpty) return 0;
  final v = double.tryParse(cleaned);
  if (v == null || v < 0) return null;
  return (v * 100).round();
}

String moneyInput(int cents) {
  final v = cents / 100;
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

String formatDate(DateTime d) => latinDigits(DateFormat('d MMMM yyyy', 'ar').format(d));

String formatTime(DateTime d) => latinDigits(DateFormat('h:mm a', 'ar').format(d));

String formatDateTime(DateTime d) => '${formatDay(d)}، ${formatTime(d)}';

/// "النهارده" / "بكرة" / "امبارح" / "السبت 3 أكتوبر"
String formatDay(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'النهارده';
  if (diff == 1) return 'بكرة';
  if (diff == -1) return 'امبارح';
  final pattern = d.year == now.year ? 'EEEE d MMMM' : 'd MMMM yyyy';
  return latinDigits(DateFormat(pattern, 'ar').format(d));
}

/// وصف قصير للمدة اللي فاتت: "من 5 دقايق"، "من ساعتين"، "من 3 أيام"
String timeAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'دلوقتي';
  if (diff.inMinutes < 60) return 'من ${_count(diff.inMinutes, 'دقيقة', 'دقيقتين', 'دقايق')}';
  if (diff.inHours < 24) return 'من ${_count(diff.inHours, 'ساعة', 'ساعتين', 'ساعات')}';
  if (diff.inDays < 30) return 'من ${_count(diff.inDays, 'يوم', 'يومين', 'أيام')}';
  return formatDate(d);
}

String _count(int n, String one, String two, String many) {
  if (n == 1) return one;
  if (n == 2) return two;
  if (n <= 10) return '$n $many';
  return '$n $one';
}

DateTime? parseDate(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
