enum Role {
  owner('المالك'),
  reception('استقبال'),
  technician('فني');

  const Role(this.label);
  final String label;

  static Role parse(String? v) => Role.values.firstWhere((r) => r.name == v, orElse: () => Role.technician);
}

class AppUser {
  AppUser({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    required this.active,
    this.createdAt,
    this.commissionType = 'none',
    this.commissionValue = 0,
  });

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        name: j['name'] as String,
        username: j['username'] as String,
        role: Role.parse(j['role'] as String?),
        active: j['active'] as bool? ?? true,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal(),
        commissionType: j['commissionType'] as String? ?? 'none',
        commissionValue: j['commissionValue'] as int? ?? 0,
      );

  final String id;
  final String name;
  final String username;
  final Role role;
  final bool active;
  final DateTime? createdAt;

  /// عمولة الفني: 'none' أو 'percent' (القيمة × 100، يعني 2500 = 25%) أو 'fixed' (قروش لكل جهاز).
  final String commissionType;
  final int commissionValue;

  bool get isOwner => role == Role.owner;
}

class ServerInfo {
  ServerInfo({
    required this.serverId,
    required this.setupDone,
    required this.version,
    required this.api,
    this.shopName,
    this.branchName,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> j) {
    if (j['app'] != 'fixtrack') throw const FormatException('not a FixTrack server');
    return ServerInfo(
      serverId: j['serverId'] as String? ?? '',
      setupDone: j['setupDone'] as bool? ?? false,
      version: j['version'] as String? ?? '',
      api: j['api'] as int? ?? 0,
      shopName: j['shopName'] as String?,
      branchName: j['branchName'] as String?,
    );
  }

  final String serverId;
  final bool setupDone;
  final String version;
  final int api;
  final String? shopName;
  final String? branchName;
}
