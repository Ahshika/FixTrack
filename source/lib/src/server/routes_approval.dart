part of 'api_server.dart';

/// طلب موافقة العميل على تكلفة زيادة، وحجز معاد الاستلام.
extension _ApprovalRoutes on FixTrackServer {
  void _registerApprovalRoutes(Router r) {
    r.post('/api/tickets/<id>/approval', _authed(_requestApproval));
    r.post('/api/tickets/<id>/approval/resolve', _authed(_resolveApprovalByStaff, only: _ticketStaff));
    r.post('/api/tickets/<id>/pickup', _authed(_setPickup, only: _ticketStaff));
  }

  Map<String, Object?> get _pickupHours => _jsonSetting('pickup_hours', defaultPickupHours);

  Future<Object?> _requestApproval(Request req, AuthUser u) async {
    final t = _loadTicket(req.params['id']!, u);
    final id = t['id'] as String;
    if (TicketStatus.parse(t['status'] as String?) == TicketStatus.delivered) throw ApiError(400, 'الجهاز اتسلم خلاص');
    final body = await _body(req);
    final total = _cents(body['totalCents'], 'التكلفة الجديدة');
    if (total <= 0) throw ApiError(400, 'اكتب التكلفة الجديدة');
    final note = _requiredText(body, 'note', 'سبب التكلفة الزيادة');
    final from = t['status'] as String;

    db.transaction(() {
      db.execute(
        "UPDATE tickets SET approval_state = 'pending', approval_cents = ?, approval_note = ?, approval_at = ?, "
        "status = 'waitingApproval', updated_at = ? WHERE id = ?",
        [total, note, nowIso(), nowIso(), id],
      );
      _event(id, 'approval_request', to: '$total', note: note, userId: u.id);
      if (from != 'waitingApproval') {
        _event(id, 'status', from: from, to: 'waitingApproval', userId: u.id, internal: false);
      }
    });
    _autoMessage(id, MessageEvent.approval);
    _audit(u.id, 'ticket.approval', 'ticket', id, '#${t['number']} ${_money(total)}');
    _broadcast('tickets');
    return _ticketDetail(_loadTicket(id, u), u);
  }

  /// الموظف بيسجل رد العميل (مثلاً رد في التليفون).
  Future<Object?> _resolveApprovalByStaff(Request req, AuthUser u) async {
    final t = _loadTicket(req.params['id']!, u);
    final body = await _body(req);
    _applyApproval(t, body['approved'] == true, source: 'staff', userId: u.id);
    return _ticketDetail(_loadTicket(t['id'] as String, u), u);
  }

  /// بيطبّق رد العميل: موافقة ← التكلفة الجديدة وكمّل إصلاح، رفض ← الجهاز يستنى العميل ياخده.
  void _applyApproval(Map<String, Object?> t, bool approved, {required String source, String? userId}) {
    if (t['approval_state'] != 'pending') throw ApiError(400, 'مفيش طلب موافقة مستني رد');
    final id = t['id'] as String;
    final newStatus = approved ? TicketStatus.repairing : TicketStatus.cancelled;
    final by = source == 'customer' ? 'العميل من صفحة التتبع' : 'اتسجل بواسطة الموظف';
    db.transaction(() {
      db.execute(
        'UPDATE tickets SET approval_state = ?, final_cents = CASE WHEN ? THEN approval_cents ELSE final_cents END, '
        'status = ?, updated_at = ? WHERE id = ?',
        [approved ? 'approved' : 'rejected', approved ? 1 : 0, newStatus.name, nowIso(), id],
      );
      _event(id, approved ? 'approval_yes' : 'approval_no', to: '${t['approval_cents']}', note: by, userId: userId);
      _event(id, 'status', from: t['status'] as String, to: newStatus.name, userId: userId, internal: false);
      _onStatusChanged(id, TicketStatus.parse(t['status'] as String?), newStatus);
    });
    _audit(userId, approved ? 'ticket.approved' : 'ticket.rejected', 'ticket', id, '#${t['number']} ($by)');
    _broadcast('tickets');
  }

  Future<Object?> _setPickup(Request req, AuthUser u) async {
    final t = _loadTicket(req.params['id']!, u);
    final body = await _body(req);
    final at = _validDate(body['at']);
    _applyPickup(t, at, source: 'staff', userId: u.id);
    return _ticketDetail(_loadTicket(t['id'] as String, u), u);
  }

  void _applyPickup(Map<String, Object?> t, String? at, {required String source, String? userId}) {
    final id = t['id'] as String;
    if (t['status'] == 'delivered') throw ApiError(400, 'الجهاز اتسلم خلاص');
    if (at != null && source == 'customer' && !_isValidSlot(DateTime.parse(at).toLocal())) {
      throw ApiError(400, 'المعاد ده مش متاح');
    }
    db.execute('UPDATE tickets SET pickup_at = ?, updated_at = ? WHERE id = ?', [at, nowIso(), id]);
    _event(id, 'pickup', to: at, note: source == 'customer' ? 'حجز من العميل' : null, userId: userId, internal: false);
    _broadcast('tickets');
  }

  /// المعاد لازم يكون جاي، في يوم شغل، وجوه مواعيد المحل، وعلى بداية فترة.
  bool _isValidSlot(DateTime local) {
    final h = _pickupHours;
    if (local.isBefore(DateTime.now())) return false;
    if (local.isAfter(DateTime.now().add(const Duration(days: 8)))) return false;
    final days = (h['days'] as List).cast<int>();
    if (!days.contains(local.weekday % 7)) return false;
    int minutes(String hhmm) => int.parse(hhmm.split(':')[0]) * 60 + int.parse(hhmm.split(':')[1]);
    final m = local.hour * 60 + local.minute;
    final from = minutes(h['from'] as String), to = minutes(h['to'] as String);
    final slot = h['slotMinutes'] as int;
    return m >= from && m + slot <= to && (m - from) % slot == 0;
  }
}
