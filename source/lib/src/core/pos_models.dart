import 'format.dart';
import 'ticket_status.dart';

class Product {
  Product(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        barcode = j['barcode'] as String?,
        category = j['category'] as String?,
        costCents = j['costCents'] as int? ?? 0,
        priceCents = j['priceCents'] as int? ?? 0,
        qty = j['qty'] as int? ?? 0,
        lowStock = j['lowStock'] as int? ?? 0,
        trackStock = j['trackStock'] as bool? ?? true,
        serialized = j['serialized'] as bool? ?? false,
        warrantyMonths = j['warrantyMonths'] as int? ?? 0,
        notes = j['notes'] as String?;

  final String id;
  final String name;
  final String? barcode;
  final String? category;
  final int costCents;
  final int priceCents;
  final int qty;
  final int lowStock;
  final bool trackStock;
  final bool serialized;
  final int warrantyMonths;
  final String? notes;

  bool get isLow => trackStock && qty <= lowStock;
  bool get outOfStock => trackStock && qty <= 0;
}

class CartLine {
  CartLine(this.product, {this.qty = 1, int? unitPriceCents, this.unit}) : unitPriceCents = unitPriceCents ?? unit?.priceCents ?? product.priceCents;

  final Product product;

  /// الجهاز نفسه (لو الصنف موبايل بـ IMEI).
  final PhoneUnit? unit;
  int qty;
  int unitPriceCents;

  int get totalCents => qty * unitPriceCents;
}

class SaleSummary {
  SaleSummary(Map<String, dynamic> j)
      : id = j['id'] as String,
        number = j['number'] as int,
        customerId = j['customerId'] as String?,
        customerName = j['customerName'] as String?,
        subtotalCents = j['subtotalCents'] as int,
        discountCents = j['discountCents'] as int? ?? 0,
        totalCents = j['totalCents'] as int,
        paidCents = j['paidCents'] as int,
        returnedCents = j['returnedCents'] as int? ?? 0,
        dueCents = j['dueCents'] as int? ?? 0,
        itemsCount = j['itemsCount'] as int? ?? 0,
        userName = j['userName'] as String?,
        note = j['note'] as String?,
        createdAt = parseDate(j['createdAt'])!;

  final String id;
  final int number;
  final String? customerId;
  final String? customerName;
  final int subtotalCents;
  final int discountCents;
  final int totalCents;
  final int paidCents;
  final int returnedCents;
  final int dueCents;
  final int itemsCount;
  final String? userName;
  final String? note;
  final DateTime createdAt;
}

class SaleItem {
  SaleItem(Map<String, dynamic> j)
      : id = j['id'] as String,
        productId = j['productId'] as String?,
        name = j['name'] as String,
        qty = j['qty'] as int,
        unitPriceCents = j['unitPriceCents'] as int,
        returnedQty = j['returnedQty'] as int? ?? 0,
        costCents = j['costCents'] as int?,
        imei = j['imei'] as String?,
        condition = j['condition'] as String?,
        warrantyMonths = j['warrantyMonths'] as int? ?? 0;

  final String id;
  final String? productId;
  final String name;
  final int qty;
  final int unitPriceCents;
  final int returnedQty;
  final int? costCents;
  final String? imei;
  final String? condition;
  final int warrantyMonths;

  int get returnableQty => qty - returnedQty;
}

class SaleDetail {
  SaleDetail(Map<String, dynamic> j)
      : sale = SaleSummary(j['sale'] as Map<String, dynamic>),
        items = (j['items'] as List).map((i) => SaleItem(i as Map<String, dynamic>)).toList(),
        payments = (j['payments'] as List)
            .map((p) => (
                  type: p['type'] as String,
                  amountCents: p['amountCents'] as int,
                  method: PaymentMethod.parse(p['method'] as String?),
                ))
            .toList();

  final SaleSummary sale;
  final List<SaleItem> items;
  final List<({String type, int amountCents, PaymentMethod method})> payments;
}

class CashMove {
  CashMove(Map<String, dynamic> j)
      : id = j['id'] as String,
        type = j['type'] as String,
        amountCents = j['amountCents'] as int,
        method = PaymentMethod.parse(j['method'] as String?),
        category = j['category'] as String?,
        refType = j['refType'] as String?,
        refId = j['refId'] as String?,
        note = j['note'] as String?,
        userName = j['userName'] as String?,
        createdAt = parseDate(j['createdAt'])!;

  final String id;
  final String type;
  final int amountCents;
  final PaymentMethod method;
  final String? category;
  final String? refType;
  final String? refId;
  final String? note;
  final String? userName;
  final DateTime createdAt;
}

const cashMoveLabels = {
  'sale': 'بيع',
  'sale_refund': 'مرتجع بيع',
  'repair_payment': 'دفعة صيانة',
  'repair_refund': 'مرتجع صيانة',
  'customer_payment': 'تحصيل من عميل',
  'expense': 'مصروف',
  'deposit': 'إيداع',
  'withdraw': 'سحب',
  'supplier_payment': 'دفعة لمورد',
  'purchase_payment': 'فاتورة شرا',
  'used_purchase': 'شرا مستعمل',
  'service': 'خدمات ومحافظ',
  'wallet_topup': 'تغذية محفظة',
  'wallet_withdraw': 'سحب من محفظة',
};

class CashSession {
  CashSession(Map<String, dynamic> j)
      : id = j['id'] as String,
        openedAt = parseDate(j['openedAt'])!,
        openedBy = j['openedBy'] as String?,
        closedAt = parseDate(j['closedAt']),
        closedBy = j['closedBy'] as String?,
        openingCashCents = j['openingCashCents'] as int? ?? 0,
        byMethod = {for (final e in (j['byMethod'] as Map).entries) PaymentMethod.parse(e.key as String): e.value as int},
        byType = Map<String, int>.from(j['byType'] as Map),
        expectedCashCents = j['expectedCashCents'] as int? ?? 0,
        countedCashCents = j['countedCashCents'] as int?,
        keptCashCents = j['keptCashCents'] as int?,
        differenceCents = j['differenceCents'] as int?,
        note = j['note'] as String?,
        moves = (j['moves'] as List? ?? const []).map((m) => CashMove(m as Map<String, dynamic>)).toList(),
        movesCount = j['movesCount'] as int? ?? (j['moves'] as List? ?? const []).length;

  final String id;
  final DateTime openedAt;
  final String? openedBy;
  final DateTime? closedAt;
  final String? closedBy;
  final int openingCashCents;
  final Map<PaymentMethod, int> byMethod;
  final Map<String, int> byType;
  final int expectedCashCents;
  final int? countedCashCents;
  final int? keptCashCents;
  final int? differenceCents;
  final String? note;
  final List<CashMove> moves;

  /// عدد كل حركات اليوم (السيرفر بيبعت آخرها بس).
  final int movesCount;

  int get salesCents => (byType['sale'] ?? 0) + (byType['sale_refund'] ?? 0);
  int get repairsCents => (byType['repair_payment'] ?? 0) + (byType['repair_refund'] ?? 0);
  int get expensesCents => -(byType['expense'] ?? 0);
}

/// جهاز واحد بالـ IMEI بتاعه (موبايل جديد أو مستعمل).
class PhoneUnit {
  PhoneUnit(Map<String, dynamic> j)
      : id = j['id'] as String,
        productId = j['productId'] as String,
        productName = j['productName'] as String? ?? '',
        imei = j['imei'] as String,
        imei2 = j['imei2'] as String?,
        condition = j['condition'] as String? ?? 'new',
        color = j['color'] as String?,
        storage = j['storage'] as String?,
        notes = j['notes'] as String?,
        priceCents = j['priceCents'] as int? ?? 0,
        costCents = j['costCents'] as int?,
        warrantyMonths = j['warrantyMonths'] as int? ?? 0,
        status = j['status'] as String? ?? 'in_stock',
        source = j['source'] as String? ?? 'manual',
        createdAt = parseDate(j['createdAt']),
        soldAt = parseDate(j['soldAt']),
        sellerName = j['sellerName'] as String?,
        sellerPhone = j['sellerPhone'] as String?,
        sellerNationalId = j['sellerNationalId'] as String?,
        sellerIdPhoto = j['sellerIdPhoto'] as String?,
        supplierName = j['supplierName'] as String?,
        soldToName = j['soldToName'] as String?;

  final String id;
  final String productId;
  final String productName;
  final String imei;
  final String? imei2;
  final String condition;
  final String? color;
  final String? storage;
  final String? notes;
  final int priceCents;
  final int? costCents;
  final int warrantyMonths;
  final String status;
  final String source;
  final DateTime? createdAt;
  final DateTime? soldAt;
  final String? sellerName;
  final String? sellerPhone;
  final String? sellerNationalId;
  final String? sellerIdPhoto;
  final String? supplierName;
  final String? soldToName;

  bool get isUsed => condition == 'used';
  String get details => [?color, ?storage, if (isUsed) 'مستعمل'].join(' • ');
}

class Supplier {
  Supplier(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        phone = j['phone'] as String?,
        notes = j['notes'] as String?,
        balanceCents = j['balanceCents'] as int? ?? 0;

  final String id;
  final String name;
  final String? phone;
  final String? notes;
  final int balanceCents;
}

class PurchaseSummary {
  PurchaseSummary(Map<String, dynamic> j)
      : id = j['id'] as String,
        number = j['number'] as int,
        supplierName = j['supplierName'] as String?,
        totalCents = j['totalCents'] as int,
        paidCents = j['paidCents'] as int,
        dueCents = j['dueCents'] as int? ?? 0,
        itemsCount = j['itemsCount'] as int? ?? 0,
        userName = j['userName'] as String?,
        createdAt = parseDate(j['createdAt'])!;

  final String id;
  final int number;
  final String? supplierName;
  final int totalCents;
  final int paidCents;
  final int dueCents;
  final int itemsCount;
  final String? userName;
  final DateTime createdAt;
}

const walletKindLabels = {
  'vodafone': 'فودافون كاش',
  'etisalat': 'اتصالات كاش',
  'orange': 'أورنج كاش',
  'we': 'وي باي',
  'instapay': 'إنستاباي',
  'fawry': 'فوري',
  'aman': 'أمان',
  'other': 'أخرى',
};

const walletTxnLabels = {
  'cash_in': 'إيداع لعميل',
  'cash_out': 'سحب لعميل',
  'recharge': 'شحن رصيد',
  'bill': 'دفع فاتورة',
  'topup': 'تغذية المحفظة',
  'withdraw': 'سحب للدرج',
  'adjust': 'تسوية رصيد',
};

class Wallet {
  Wallet(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        kind = j['kind'] as String? ?? 'other',
        phone = j['phone'] as String?,
        balanceCents = j['balanceCents'] as int? ?? 0,
        todayCount = j['todayCount'] as int? ?? 0,
        todayCommissionCents = j['todayCommissionCents'] as int? ?? 0;

  final String id;
  final String name;
  final String kind;
  final String? phone;
  final int balanceCents;
  final int todayCount;
  final int todayCommissionCents;
}
