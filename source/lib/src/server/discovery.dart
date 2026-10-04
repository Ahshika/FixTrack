import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// البورت اللي السيرفر بيسمع عليه طلبات "فين السيرفر؟" من الموبايلات.
const discoveryPort = 8744;
const _request = 'FIXTRACK_DISCOVER';
const _replyPrefix = 'FIXTRACK_HERE:';

/// بيشتغل على السيرفر: يرد على أي موبايل بيدوّر على سيرفر في الشبكة.
class DiscoveryResponder {
  DiscoveryResponder(this.describe);

  /// بيرجع بيانات السيرفر اللي هتتبعت للموبايل (البورت، اسم المحل، ...).
  final Map<String, Object?> Function() describe;
  RawDatagramSocket? _socket;

  Future<void> start() async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort);
    _socket = socket;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket.receive();
      if (dg == null || utf8.decode(dg.data, allowMalformed: true) != _request) return;
      final reply = utf8.encode('$_replyPrefix${jsonEncode(describe())}');
      socket.send(reply, dg.address, dg.port);
    });
  }

  void close() => _socket?.close();
}

class DiscoveredServer {
  DiscoveredServer({required this.url, required this.shopName, required this.branchName, required this.serverId});

  final String url;
  final String shopName;
  final String branchName;
  final String serverId;
}

/// بيشتغل على الموبايل: يبعت طلب في الشبكة كلها ويجمع الردود.
Future<List<DiscoveredServer>> discoverServers({Duration timeout = const Duration(seconds: 3)}) async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  socket.broadcastEnabled = true;
  final found = <String, DiscoveredServer>{};

  final sub = socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = socket.receive();
    if (dg == null) return;
    final text = utf8.decode(dg.data, allowMalformed: true);
    if (!text.startsWith(_replyPrefix)) return;
    try {
      final info = jsonDecode(text.substring(_replyPrefix.length)) as Map<String, dynamic>;
      final url = 'http://${dg.address.address}:${info['port']}';
      found[url] = DiscoveredServer(
        url: url,
        shopName: info['shopName'] as String? ?? '',
        branchName: info['branchName'] as String? ?? '',
        serverId: info['serverId'] as String? ?? '',
      );
    } catch (_) {
      // رد مش مفهوم، نتجاهله
    }
  });

  final payload = utf8.encode(_request);
  final targets = {InternetAddress('255.255.255.255'), ...await _subnetBroadcasts()};
  // بنبعت أكتر من مرة لأن الـ UDP ممكن يضيع على الواي فاي
  for (var i = 0; i < 3; i++) {
    for (final target in targets) {
      try {
        socket.send(payload, target, discoveryPort);
      } catch (_) {}
    }
    await Future<void>.delayed(timeout ~/ 3);
  }

  await sub.cancel();
  socket.close();
  return found.values.toList();
}

/// عناوين الـ broadcast لكل شبكة الجهاز متوصل بيها (بنفترض /24 زي أغلب الراوترات).
Future<Set<InternetAddress>> _subnetBroadcasts() async {
  final result = <InternetAddress>{};
  try {
    for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final addr in iface.addresses) {
        final p = addr.rawAddress;
        result.add(InternetAddress('${p[0]}.${p[1]}.${p[2]}.255'));
      }
    }
  } catch (_) {}
  return result;
}

/// عناوين الـ IP بتاعة الجهاز في الشبكة المحلية (بتظهر في الإعدادات عشان الاتصال اليدوي).
Future<List<String>> localIpAddresses() async {
  final ips = <String>[];
  try {
    for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback && !addr.isLinkLocal) ips.add(addr.address);
      }
    }
  } catch (_) {}
  return ips;
}
