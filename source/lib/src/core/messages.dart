/// قوالب الرسائل وقواعد إرسالها. من غير Flutter عشان السيرفر يستخدمه.
library;

import 'ticket_status.dart';

enum MessageEvent {
  received('استلام الجهاز'),
  ready('الجهاز جاهز'),
  waitingParts('مستني قطع غيار'),
  approval('طلب موافقة على تكلفة'),
  dueChanged('تغيير الموعد المتوقع'),
  delivered('بعد التسليم'),
  reminder('تذكير بالاستلام'),
  custom('رسالة حرة');

  const MessageEvent(this.label);
  final String label;

  static MessageEvent parse(String? v) => values.firstWhere((e) => e.name == v, orElse: () => custom);

  /// الأحداث اللي ليها قاعدة إرسال أوتوماتيك (كل حاجة ما عدا الرسالة الحرة).
  static List<MessageEvent> get automatic => values.where((e) => e != custom).toList();

  /// الحدث اللي بيحصل لما الجهاز يدخل المرحلة دي (لو فيه).
  static MessageEvent? forStatus(TicketStatus s) => switch (s) {
        TicketStatus.ready => ready,
        TicketStatus.waitingParts => waitingParts,
        TicketStatus.waitingApproval => approval,
        TicketStatus.delivered => delivered,
        _ => null,
      };
}

/// طريقة الإرسال لكل حدث.
enum MessageRule {
  off('من غير رسالة'),
  whatsapp('واتساب (بزرار)'),
  sms('SMS أوتوماتيك');

  const MessageRule(this.label);
  final String label;

  static MessageRule parse(String? v) => values.firstWhere((r) => r.name == v, orElse: () => off);
}

const defaultMessageRules = {
  'received': 'whatsapp',
  'ready': 'whatsapp',
  'waitingParts': 'whatsapp',
  'approval': 'whatsapp',
  'dueChanged': 'off',
  'delivered': 'off',
  'reminder': 'whatsapp',
};

const defaultTemplates = {
  'received': 'أهلاً {customer} 👋\n'
      'استلمنا جهازك {device} في {shop}.\n'
      'رقم الوصل: {number}\n'
      'كود الاستلام: {pin} (هتحتاجه وإنت بتستلم)\n'
      'الموعد المتوقع: {due}\n'
      'تابع حالة جهازك من هنا: {link}\n'
      'للاستفسار: {shop_phone}',
  'ready': 'أهلاً {customer}، جهازك {device} جاهز للاستلام ✅\n'
      'المبلغ المتبقي: {remaining}\n'
      'متنساش كود الاستلام: {pin}\n'
      '{shop} - {shop_phone}',
  'waitingParts': 'أهلاً {customer}، جهازك {device} مستني قطعة غيار.\n'
      'الموعد المتوقع الجديد: {due}\n'
      'آسفين على التأخير 🙏\n'
      '{shop}',
  'approval': 'أهلاً {customer}، الفني لقى في جهازك {device}:\n'
      '{approval_note}\n'
      'التكلفة الجديدة: {approval_total}\n'
      'وافق أو ارفض من هنا: {link}\n'
      'أو رد علينا على {shop_phone}',
  'dueChanged': 'أهلاً {customer}، الموعد المتوقع لجهازك {device} بقى {due}.\n'
      'تابع حالة جهازك من هنا: {link}\n'
      '{shop}',
  'delivered': 'شكراً لتعاملك مع {shop} 🙏\n'
      'اتسلم جهازك {device}. لو فيه أي مشكلة كلمنا على {shop_phone}.',
  'reminder': 'أهلاً {customer}، جهازك {device} جاهز من {days} يوم ومستنيك ✅\n'
      'المبلغ المتبقي: {remaining}\n'
      'متنساش كود الاستلام: {pin}\n'
      '{shop} - {shop_phone}',
  'custom': 'أهلاً {customer}،\n\n{shop}',
};

/// المتغيرات اللي ينفع تتكتب في القوالب، مع شرحها.
const templateVariables = {
  'customer': 'اسم العميل',
  'device': 'الجهاز',
  'number': 'رقم الوصل',
  'pin': 'كود الاستلام',
  'status': 'المرحلة الحالية',
  'due': 'الموعد المتوقع',
  'total': 'التكلفة',
  'paid': 'المدفوع',
  'remaining': 'الباقي',
  'approval_total': 'التكلفة الجديدة (طلب الموافقة)',
  'approval_note': 'سبب التكلفة الزيادة',
  'pickup': 'معاد الاستلام المحجوز',
  'days': 'عدد الأيام من ساعة ما بقى جاهز',
  'link': 'لينك متابعة الجهاز',
  'shop': 'اسم المحل',
  'shop_phone': 'تليفون المحل',
};

/// بيملا القالب بالقيم. أي سطر فيه متغير قيمته فاضية بيتشال كله
/// (مثلاً لو مفيش لينك تتبع، سطر "تابع حالة جهازك" مش هيظهر).
String renderTemplate(String template, Map<String, String?> values) {
  final lines = <String>[];
  final pattern = RegExp(r'\{([a-z_]+)\}');
  for (final line in template.split('\n')) {
    var missing = false;
    final rendered = line.replaceAllMapped(pattern, (m) {
      final key = m.group(1)!;
      if (!values.containsKey(key)) return m.group(0)!;
      final v = values[key];
      if (v == null || v.trim().isEmpty) {
        missing = true;
        return '';
      }
      return v;
    });
    if (!missing) lines.add(rendered);
  }
  return lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// الرقم بصيغة دولية للواتساب: 01001234567 ← 201001234567
String whatsappNumber(String phone) {
  final d = normalizePhone(phone);
  if (d.startsWith('0') && d.length == 11) return '20${d.substring(1)}';
  return d;
}
