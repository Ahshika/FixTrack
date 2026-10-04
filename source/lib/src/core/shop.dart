import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/tickets/providers.dart';
import 'firebase_config.dart';
import 'format.dart';
import 'messages.dart';
import 'realtime.dart';

class ShopProfile {
  ShopProfile(Map<String, dynamic> j)
      : _raw = j,
        name = j['name'] as String? ?? '',
        phone = j['phone'] as String?,
        address = j['address'] as String?,
        branchName = j['branchName'] as String?,
        logo = j['logoBase64'] == null ? null : base64.decode(j['logoBase64'] as String),
        receiptTerms = j['receiptTerms'] as String? ?? '',
        receiptPaper = j['receiptPaper'] as String? ?? '80mm',
        trackingBaseUrl = (j['trackingBaseUrl'] as String?)?.isEmpty ?? true ? null : j['trackingBaseUrl'] as String,
        pickupHours = Map<String, dynamic>.from(j['pickupHours'] as Map? ?? defaultPickupHours),
        cloudLastSync = parseDate((j['cloud'] as Map?)?['lastSync']),
        cloudError = ((j['cloud'] as Map?)?['lastError'] as String?)?.isEmpty ?? true ? null : (j['cloud'] as Map)['lastError'] as String,
        cloudPending = (j['cloud'] as Map?)?['pending'] as int? ?? 0,
        templates = Map<String, String>.from(j['templates'] as Map? ?? defaultTemplates),
        rules = (j['rules'] as Map? ?? defaultMessageRules)
            .map((k, v) => MapEntry(MessageEvent.parse(k as String), MessageRule.parse(v as String?)));

  final String name;
  final String? phone;
  final String? address;
  final String? branchName;
  final Uint8List? logo;
  final String receiptTerms;
  final String receiptPaper;
  final String? trackingBaseUrl;
  final Map<String, dynamic> pickupHours;
  late final bool cashierCanDiscount = _raw['cashierCanDiscount'] as bool? ?? true;
  late final bool allowNegativeStock = _raw['allowNegativeStock'] as bool? ?? true;
  late final int repairWarrantyDays = _raw['repairWarrantyDays'] as int? ?? 30;
  final Map<String, dynamic> _raw;
  final DateTime? cloudLastSync;
  final String? cloudError;
  final int cloudPending;
  final Map<String, String> templates;
  final Map<MessageEvent, MessageRule> rules;

  MessageRule ruleFor(MessageEvent e) => rules[e] ?? MessageRule.off;

  String? trackingLink(String? publicToken) =>
      trackingBaseUrl == null || publicToken == null ? null : '$trackingBaseUrl/t/$publicToken';
}

final shopProvider = FutureProvider.autoDispose<ShopProfile>((ref) async {
  refreshOn(ref, 'shop');
  ref.keepAlive();
  return ShopProfile(await apiOf(ref).get('/api/shop'));
});
