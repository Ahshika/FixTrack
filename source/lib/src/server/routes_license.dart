part of 'api_server.dart';

/// الاشتراك: تجربة مجانية 14 يوم، وبعدها كود تفعيل موقّع ومربوط بالجهاز.
/// لو الاشتراك خلص: البيانات كلها موجودة، وتقدر تسلّم الأجهزة وتشوف التقارير، لكن مفيش تسجيل شغل جديد.
extension _LicenseRoutes on FixTrackServer {
  void _registerLicenseRoutes(Router r) {
    r.get('/api/license', _authed((req, u) async => _licenseStatus()));
    r.post('/api/license', _authed(_activateLicense, only: {'owner'}));
  }

  String get _deviceCode => deviceCodeFor(db.setting('server_id')!);

  Future<Map<String, Object?>> _licenseStatus() async {
    final now = DateTime.now().toUtc();
    // لو حد رجّع ساعة الكمبيوتر لورا عشان يطوّل الاشتراك
    final seen = DateTime.tryParse(db.setting('license_clock') ?? '');
    final tampered = seen != null && now.isBefore(seen.subtract(const Duration(days: 2)));
    if (!tampered && (seen == null || now.isAfter(seen))) db.setSetting('license_clock', now.toIso8601String());

    var trialStart = DateTime.tryParse(db.setting('trial_started') ?? '');
    if (trialStart == null) {
      trialStart = now;
      db.setSetting('trial_started', now.toIso8601String());
    }
    final base = {'deviceCode': _deviceCode, 'tampered': tampered};

    final code = db.setting('license_code');
    if (code != null && code.isNotEmpty) {
      try {
        final lic = await verifyLicense(code, deviceCode: _deviceCode);
        final expired = lic.expires != null && now.isAfter(lic.expires!);
        return {
          ...base,
          'state': tampered ? 'tampered' : expired ? 'expired' : 'active',
          'plan': lic.plan,
          'shop': lic.shop,
          'expiresAt': lic.expires?.toIso8601String(),
          'daysLeft': lic.expires?.difference(now).inDays,
          'devices': lic.devices,
          'branches': lic.branches,
          'licenseId': lic.id,
        };
      } on LicenseException {
        // كود مش صالح (مثلاً اتنقلت البيانات لجهاز تاني): نرجع للتجربة/الانتهاء
      }
    }
    final trialEnd = trialStart.add(const Duration(days: trialDays));
    return {
      ...base,
      'state': tampered ? 'tampered' : now.isBefore(trialEnd) ? 'trial' : 'expired',
      'plan': 'trial',
      'expiresAt': trialEnd.toIso8601String(),
      'daysLeft': trialEnd.difference(now).inDays,
      'devices': 3,
      'branches': 1,
    };
  }

  Future<Object?> _activateLicense(Request req, AuthUser u) async {
    final body = await _body(req);
    final code = (body['code'] as String? ?? '').trim();
    try {
      final lic = await verifyLicense(code, deviceCode: _deviceCode);
      if (lic.expires != null && DateTime.now().toUtc().isAfter(lic.expires!)) {
        throw ApiError(400, 'الكود ده خلص يوم ${formatDate(lic.expires!.toLocal())}');
      }
      db.setSetting('license_code', code);
      _audit(u.id, 'license.activate', 'license', lic.id, '${lic.plan} ${lic.expires?.toIso8601String() ?? 'مدى الحياة'}');
      _broadcast('license');
      return await _licenseStatus();
    } on LicenseException catch (e) {
      throw ApiError(400, e.message);
    }
  }

  /// بيتنادى قبل أي عملية بتسجل شغل جديد (استلام، بيع، شرا...).
  Future<void> _requireLicense() async {
    final s = await _licenseStatus();
    switch (s['state']) {
      case 'expired':
        throw ApiError(402, s['plan'] == 'trial'
            ? 'فترة التجربة المجانية خلصت. كلم صاحب البرنامج عشان كود التفعيل (كود جهازك: ${s['deviceCode']})'
            : 'الاشتراك خلص. جدّده عشان تكمّل تسجيل شغل جديد (كود جهازك: ${s['deviceCode']})');
      case 'tampered':
        throw ApiError(402, 'تاريخ الكمبيوتر مش مظبوط. ظبط التاريخ والساعة وجرّب تاني');
    }
  }

  /// عدد الأجهزة المسموح بيها: جهاز جديد مايقدرش يدخل لو العدد اكتمل.
  Future<void> _checkDeviceLimit(String? deviceName) async {
    if (deviceName == null) return;
    final limit = (await _licenseStatus())['devices'] as int? ?? 3;
    final since = DateTime.now().toUtc().subtract(const Duration(days: 30)).toIso8601String();
    final known = db
        .select('SELECT DISTINCT device_name FROM sessions WHERE device_name IS NOT NULL AND last_seen_at >= ?', [since])
        .map((r) => r['device_name'] as String)
        .toSet();
    if (known.contains(deviceName) || known.length < limit) return;
    throw ApiError(402, 'الاشتراك بيسمح بـ $limit أجهزة بس، وكلهم مستخدمين. اخرج من جهاز قديم أو كبّر الاشتراك');
  }
}
