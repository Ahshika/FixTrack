import 'format.dart';
import 'models.dart';
import 'ticket_status.dart';

List<String> _strings(Object? v) => v is List ? v.whereType<String>().toList() : const [];

class Customer {
  Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.whatsapp,
    this.notes,
    this.ticketsCount = 0,
    this.lastVisit,
    this.balanceCents = 0,
  });

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String,
        whatsapp: j['whatsapp'] as String?,
        notes: j['notes'] as String?,
        ticketsCount: j['ticketsCount'] as int? ?? 0,
        lastVisit: parseDate(j['lastVisit']),
        balanceCents: j['balanceCents'] as int? ?? 0,
      );

  final String id;
  final String name;
  final String phone;
  final String? whatsapp;
  final String? notes;
  final int ticketsCount;
  final DateTime? lastVisit;
  final int balanceCents;
}

class Ticket {
  Ticket(this.json)
      : id = json['id'] as String,
        number = json['number'] as int,
        status = TicketStatus.parse(json['status'] as String?),
        brand = json['brand'] as String,
        model = json['model'] as String,
        color = json['color'] as String?,
        deviceType = json['deviceType'] as String? ?? 'phone',
        problems = _strings(json['problems']),
        customerId = json['customerId'] as String,
        customerName = json['customerName'] as String,
        customerPhone = json['customerPhone'] as String,
        technicianId = json['technicianId'] as String?,
        technicianName = json['technicianName'] as String?,
        estimatedCents = json['estimatedCents'] as int? ?? 0,
        finalCents = json['finalCents'] as int?,
        paidCents = json['paidCents'] as int? ?? 0,
        dueAt = parseDate(json['dueAt']),
        overdue = json['overdue'] as bool? ?? false,
        createdAt = parseDate(json['createdAt'])!,
        deliveredAt = parseDate(json['deliveredAt']);

  final Map<String, dynamic> json;
  final String id;
  final int number;
  final TicketStatus status;
  final String brand;
  final String model;
  final String? color;
  final String deviceType;
  final List<String> problems;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String? technicianId;
  final String? technicianName;
  final int estimatedCents;
  final int? finalCents;
  final int paidCents;
  final DateTime? dueAt;
  final bool overdue;
  final DateTime createdAt;
  final DateTime? deliveredAt;

  String get deviceName => model.toLowerCase().startsWith(brand.toLowerCase()) ? model : '$brand $model';
  int get totalCents => finalCents ?? estimatedCents;
  int get remainingCents => totalCents - paidCents;

  // الحقول دي موجودة بس في تفاصيل الجهاز (مش في القوائم)
  String? get imei => json['imei'] as String?;
  String? get problemDesc => json['problemDesc'] as String?;
  bool? get powersOn => json['powersOn'] as bool?;
  List<String> get conditionFlags => _strings(json['conditionFlags']);
  String? get conditionNotes => json['conditionNotes'] as String?;
  List<String> get accessories => _strings(json['accessories']);
  LockType get lockType => LockType.parse(json['lockType'] as String?);
  bool get hasLockSecret => json['hasLockSecret'] as bool? ?? false;
  bool get canRevealLock => json['canRevealLock'] as bool? ?? false;
  String? get pickupPin => json['pickupPin'] as String?;
  String? get customerWhatsapp => json['customerWhatsapp'] as String?;
  String? get createdByName => json['createdByName'] as String?;
  String? get deliveredByName => json['deliveredByName'] as String?;
  String? get publicToken => json['publicToken'] as String?;
  String? get approvalState => json['approvalState'] as String?;
  int? get approvalCents => json['approvalCents'] as int?;
  String? get approvalNote => json['approvalNote'] as String?;
  DateTime? get pickupAt => parseDate(json['pickupAt']);
  bool get approvalPending => approvalState == 'pending';
  int? get warrantyDays => json['warrantyDays'] as int?;
  DateTime? get warrantyUntil => parseDate(json['warrantyUntil']);
  String? get warrantyOf => json['warrantyOf'] as String?;
  bool get underWarranty => warrantyUntil != null && warrantyUntil!.isAfter(DateTime.now());
  DateTime? get readyAt => parseDate(json['readyAt']);
  int? get daysWaiting => json['daysWaiting'] as int?;
}

class TicketEvent {
  TicketEvent(Map<String, dynamic> j)
      : type = j['type'] as String,
        from = j['from'] as String?,
        to = j['to'] as String?,
        note = j['note'] as String?,
        internal = j['internal'] as bool? ?? true,
        userName = j['userName'] as String?,
        createdAt = parseDate(j['createdAt'])!;

  final String type;
  final String? from;
  final String? to;
  final String? note;
  final bool internal;
  final String? userName;
  final DateTime createdAt;
}

class Payment {
  Payment(Map<String, dynamic> j)
      : amountCents = j['amountCents'] as int,
        method = PaymentMethod.parse(j['method'] as String?),
        kind = PaymentKind.parse(j['kind'] as String?),
        note = j['note'] as String?,
        userName = j['userName'] as String?,
        createdAt = parseDate(j['createdAt'])!;

  final int amountCents;
  final PaymentMethod method;
  final PaymentKind kind;
  final String? note;
  final String? userName;
  final DateTime createdAt;
}

class TicketDetail {
  TicketDetail(Map<String, dynamic> j)
      : ticket = Ticket(j['ticket'] as Map<String, dynamic>),
        events = (j['events'] as List).map((e) => TicketEvent(e as Map<String, dynamic>)).toList(),
        payments = (j['payments'] as List).map((p) => Payment(p as Map<String, dynamic>)).toList(),
        messages = (j['messages'] as List? ?? const []).map((m) => SentMessage(m as Map<String, dynamic>)).toList(),
        parts = (j['parts'] as List? ?? const []).cast<Map<String, dynamic>>(),
        warrantyOrigin = j['warrantyOrigin'] as Map<String, dynamic>?,
        warrantyReturns = (j['warrantyReturns'] as List? ?? const []).cast<Map<String, dynamic>>();

  final Ticket ticket;
  final List<TicketEvent> events;
  final List<Payment> payments;
  final List<SentMessage> messages;
  final List<Map<String, dynamic>> parts;
  final Map<String, dynamic>? warrantyOrigin;
  final List<Map<String, dynamic>> warrantyReturns;
}

class SentMessage {
  SentMessage(Map<String, dynamic> j)
      : channel = j['channel'] as String,
        event = j['event'] as String,
        body = j['body'] as String,
        status = j['status'] as String,
        error = j['error'] as String?,
        userName = j['userName'] as String?,
        createdAt = parseDate(j['createdAt'])!;

  final String channel;
  final String event;
  final String body;
  final String status;
  final String? error;
  final String? userName;
  final DateTime createdAt;
}

class StaffMember {
  StaffMember(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        role = Role.parse(j['role'] as String?);

  final String id;
  final String name;
  final Role role;
}

class DashboardStats {
  DashboardStats(Map<String, dynamic> j)
      : receivedToday = j['receivedToday'] as int? ?? 0,
        inProgress = j['inProgress'] as int? ?? 0,
        ready = j['ready'] as int? ?? 0,
        awaitingPickup = j['awaitingPickup'] as int? ?? 0,
        overdue = j['overdue'] as int? ?? 0,
        deliveredToday = j['deliveredToday'] as int? ?? 0,
        collectedTodayCents = j['collectedTodayCents'] as int?,
        pickupsToday = j['pickupsToday'] as int? ?? 0,
        salesTodayCount = j['salesTodayCount'] as int?,
        salesTodayCents = j['salesTodayCents'] as int?,
        lowStockCount = j['lowStockCount'] as int? ?? 0;

  final int receivedToday;
  final int inProgress;
  final int ready;
  final int awaitingPickup;
  final int overdue;
  final int deliveredToday;
  final int? collectedTodayCents;
  final int pickupsToday;
  final int? salesTodayCount;
  final int? salesTodayCents;
  final int lowStockCount;
}
