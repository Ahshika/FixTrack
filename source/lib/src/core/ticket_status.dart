/// مراحل الصيانة. الملف ده من غير Flutter عشان السيرفر والبرنامج الاتنين يستخدموه.
enum TicketStatus {
  received('تم الاستلام'),
  diagnosing('جاري الفحص'),
  waitingApproval('في انتظار موافقة العميل'),
  waitingParts('في انتظار قطع الغيار'),
  repairing('جاري الإصلاح'),
  testing('اختبار'),
  ready('جاهز للاستلام'),
  delivered('تم التسليم'),
  cancelled('مرفوض / ملغي'),
  unrepairable('غير قابل للإصلاح');

  const TicketStatus(this.label);
  final String label;

  static TicketStatus? tryParse(String? v) {
    for (final s in values) {
      if (s.name == v) return s;
    }
    return null;
  }

  static TicketStatus parse(String? v) => tryParse(v) ?? received;

  /// المراحل الأساسية بالترتيب (اللي بتظهر في الخط الزمني).
  static const flow = [received, diagnosing, repairing, testing, ready, delivered];

  /// الجهاز لسه في المحل ومحتاج شغل.
  bool get isOpen => !{ready, delivered, cancelled, unrepairable}.contains(this);

  /// الجهاز مستني العميل ييجي يستلمه.
  bool get awaitingPickup => {ready, cancelled, unrepairable}.contains(this);

  /// المرحلة المنطقية اللي بعدها (لزرار "المرحلة التالية").
  TicketStatus? get next => switch (this) {
        received => diagnosing,
        diagnosing => repairing,
        waitingApproval => repairing,
        waitingParts => repairing,
        repairing => testing,
        testing => ready,
        _ => null,
      };
}

const problemOptions = [
  'الشاشة',
  'البطارية',
  'الشحن',
  'سوفتوير',
  'دخول مياه',
  'السماعة / الصوت',
  'المايك',
  'الكاميرا',
  'البصمة / الفيس',
  'الشبكة / الواي فاي',
  'الزراير',
  'الضهر / الجسم',
  'لا يعمل نهائياً',
];

const conditionOptions = [
  'خدوش',
  'شاشة مكسورة',
  'ضهر مكسور',
  'آثار مياه',
  'جسم معووج',
  'اتفتح قبل كده',
];

const accessoryOptions = [
  'شاحن',
  'كابل',
  'جراب',
  'شريحة',
  'كارت ميموري',
  'العلبة',
  'سماعة',
];

enum LockType {
  none('مفيش'),
  pin('رقم سري'),
  pattern('باترن'),
  password('باسورد');

  const LockType(this.label);
  final String label;

  static LockType parse(String? v) => values.firstWhere((t) => t.name == v, orElse: () => none);
}

enum PaymentMethod {
  cash('كاش'),
  vodafoneCash('فودافون كاش'),
  instapay('إنستاباي'),
  card('فيزا'),
  other('أخرى');

  const PaymentMethod(this.label);
  final String label;

  static PaymentMethod parse(String? v) => values.firstWhere((m) => m.name == v, orElse: () => cash);
}

enum PaymentKind {
  deposit('عربون'),
  payment('دفعة'),
  refund('مرتجع');

  const PaymentKind(this.label);
  final String label;

  static PaymentKind parse(String? v) => values.firstWhere((k) => k.name == v, orElse: () => payment);
}

/// بيوحّد شكل رقم التليفون عشان البحث: أرقام إنجليزي بس، ومن غير كود مصر.
String normalizePhone(String input) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in input.split('')) {
    final a = arabic.indexOf(ch);
    final p = persian.indexOf(ch);
    if (a >= 0) {
      b.write(a);
    } else if (p >= 0) {
      b.write(p);
    } else if (RegExp(r'[0-9]').hasMatch(ch)) {
      b.write(ch);
    }
  }
  var digits = b.toString();
  if (digits.startsWith('0020')) digits = '0${digits.substring(4)}';
  if (digits.startsWith('20') && digits.length == 12) digits = '0${digits.substring(2)}';
  return digits;
}
