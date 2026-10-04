import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pos_models.dart';
import '../../core/ticket_models.dart';

class CartState {
  const CartState({this.lines = const [], this.customer, this.discountCents = 0, this.note});

  final List<CartLine> lines;
  final Customer? customer;
  final int discountCents;
  final String? note;

  int get subtotalCents => lines.fold(0, (s, l) => s + l.totalCents);
  int get totalCents => (subtotalCents - discountCents).clamp(0, 1 << 50);
  int get itemsCount => lines.fold(0, (s, l) => s + l.qty);
  bool get isEmpty => lines.isEmpty;

  CartState copyWith({List<CartLine>? lines, Customer? customer, bool clearCustomer = false, int? discountCents, String? note}) => CartState(
        lines: lines ?? this.lines,
        customer: clearCustomer ? null : customer ?? this.customer,
        discountCents: discountCents ?? this.discountCents,
        note: note ?? this.note,
      );
}

/// السلة بتفضل موجودة لو الكاشير راح شاشة تانية ورجع.
final cartProvider = NotifierProvider<CartController, CartState>(CartController.new);

class CartController extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  void add(Product p, {int qty = 1, PhoneUnit? unit}) {
    final lines = [...state.lines];
    if (unit != null) {
      // كل جهاز بـ IMEI سطر لوحده
      if (lines.any((l) => l.unit?.id == unit.id)) return;
      state = state.copyWith(lines: [...lines, CartLine(p, unit: unit)]);
      return;
    }
    final i = lines.indexWhere((l) => l.product.id == p.id && l.unit == null);
    if (i >= 0) {
      lines[i].qty += qty;
    } else {
      lines.add(CartLine(p, qty: qty));
    }
    state = state.copyWith(lines: lines);
  }

  void setQty(CartLine line, int qty) {
    if (qty <= 0) return remove(line);
    if (line.unit != null) return;
    line.qty = qty;
    state = state.copyWith(lines: [...state.lines]);
  }

  void setPrice(CartLine line, int cents) {
    line.unitPriceCents = cents;
    state = state.copyWith(lines: [...state.lines]);
  }

  void remove(CartLine line) => state = state.copyWith(lines: state.lines.where((l) => l != line).toList());

  void setCustomer(Customer? c) => state = c == null ? state.copyWith(clearCustomer: true) : state.copyWith(customer: c);

  void setDiscount(int cents) => state = state.copyWith(discountCents: cents);

  void clear() => state = const CartState();
}
