import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/realtime.dart';
import '../../core/session.dart';
import '../../core/ticket_models.dart';

ApiClient apiOf(Ref ref) => ref.watch(sessionProvider).value!.api!;

typedef TicketQuery = ({String scope, String q});

final ticketsProvider = FutureProvider.autoDispose.family<List<Ticket>, TicketQuery>((ref, query) async {
  refreshOn(ref, 'tickets');
  final res = await apiOf(ref).get('/api/tickets', query: {
    'scope': query.scope,
    if (query.q.isNotEmpty) 'q': query.q,
    'limit': '200',
  });
  return (res['tickets'] as List).map((j) => Ticket(j as Map<String, dynamic>)).toList();
});

final ticketDetailProvider = FutureProvider.autoDispose.family<TicketDetail, String>((ref, id) async {
  refreshOn(ref, 'tickets');
  return TicketDetail(await apiOf(ref).get('/api/tickets/$id'));
});

final dashboardProvider = FutureProvider.autoDispose<DashboardStats>((ref) async {
  refreshOn(ref, 'tickets');
  return DashboardStats(await apiOf(ref).get('/api/dashboard'));
});

final staffProvider = FutureProvider.autoDispose<List<StaffMember>>((ref) async {
  refreshOn(ref, 'users');
  final res = await apiOf(ref).get('/api/staff');
  return (res['staff'] as List).map((j) => StaffMember(j as Map<String, dynamic>)).toList();
});

final customersProvider = FutureProvider.autoDispose.family<List<Customer>, String>((ref, q) async {
  refreshOn(ref, 'customers');
  final res = await apiOf(ref).get('/api/customers', query: {if (q.isNotEmpty) 'q': q, 'limit': '200'});
  return (res['customers'] as List).map((j) => Customer.fromJson(j as Map<String, dynamic>)).toList();
});

final customerDetailProvider =
    FutureProvider.autoDispose.family<({Customer customer, List<Ticket> tickets}), String>((ref, id) async {
  refreshOn(ref, 'customers');
  refreshOn(ref, 'tickets');
  final res = await apiOf(ref).get('/api/customers/$id');
  return (
    customer: Customer.fromJson(res['customer'] as Map<String, dynamic>),
    tickets: (res['tickets'] as List).map((j) => Ticket(j as Map<String, dynamic>)).toList(),
  );
});

final remindersProvider = FutureProvider.autoDispose<List<Ticket>>((ref) async {
  refreshOn(ref, 'tickets');
  refreshOn(ref, 'messages');
  final res = await apiOf(ref).get('/api/reminders');
  return (res['tickets'] as List).map((j) => Ticket(j as Map<String, dynamic>)).toList();
});

final licenseProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  refreshOn(ref, 'license');
  ref.keepAlive();
  return apiOf(ref).get('/api/license');
});
