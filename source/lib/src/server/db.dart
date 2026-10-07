import 'package:sqlite3/sqlite3.dart';

/// قاعدة بيانات المحل. موجودة على كمبيوتر السيرفر بس.
///
/// كل تعديل على شكل الجداول بيتضاف كـ migration جديدة في آخر [_migrations]،
/// وماينفعش نعدّل migration قديمة لأنها ممكن تكون اتنفذت عند محلات بالفعل.
class AppDb {
  AppDb._(this.raw);

  final Database raw;

  /// الجمل المجهزة بتتحفظ وتتعاد بدل ما SQLite يحللها من الأول مع كل طلب.
  final _statements = <String, PreparedStatement>{};
  static const _maxStatements = 300;

  PreparedStatement _prepared(String sql) {
    final cached = _statements.remove(sql);
    if (cached != null) return _statements[sql] = cached; // آخر واحدة اتستخدمت بتروح للآخر
    if (_statements.length >= _maxStatements) _statements.remove(_statements.keys.first)!.close();
    return _statements[sql] = raw.prepare(sql, persistent: true);
  }

  static AppDb open(String path) {
    final db = sqlite3.open(path);
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('PRAGMA busy_timeout = 5000;');
    db.execute('PRAGMA synchronous = NORMAL;');
    final appDb = AppDb._(db);
    appDb._migrate();
    return appDb;
  }

  void _migrate() {
    for (var v = raw.userVersion; v < _migrations.length; v++) {
      transaction(() {
        raw.execute(_migrations[v]);
        raw.userVersion = v + 1;
      });
    }
  }

  T transaction<T>(T Function() body) {
    raw.execute('BEGIN IMMEDIATE');
    try {
      final result = body();
      raw.execute('COMMIT');
      return result;
    } catch (_) {
      raw.execute('ROLLBACK');
      rethrow;
    }
  }

  List<Map<String, Object?>> select(String sql, [List<Object?> params = const []]) =>
      _prepared(sql).select(params).map((r) => Map<String, Object?>.from(r)).toList();

  Map<String, Object?>? selectOne(String sql, [List<Object?> params = const []]) {
    final rows = select(sql, params);
    return rows.isEmpty ? null : rows.first;
  }

  /// من غير باراميترز ممكن تبقى أكتر من جملة (زي الـ migrations)، فبتتنفذ على طول.
  void execute(String sql, [List<Object?> params = const []]) =>
      params.isEmpty ? raw.execute(sql) : _prepared(sql).execute(params);

  String? setting(String key) =>
      selectOne('SELECT value FROM settings WHERE key = ?', [key])?['value'] as String?;

  void setSetting(String key, String value) => execute(
        'INSERT INTO settings(key, value) VALUES(?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [key, value],
      );

  /// فحص سريع إن ملف قاعدة البيانات سليم ('ok' لو تمام).
  String integrity() {
    try {
      final rows = raw.select('PRAGMA quick_check;');
      final msgs = rows.map((r) => '${r.values.first}').toList();
      return msgs.length == 1 && msgs.first == 'ok' ? 'ok' : msgs.take(5).join(' | ');
    } catch (e) {
      return '$e';
    }
  }

  /// صيانة بتتعمل كل ساعة: تحسين الفهارس، وتصغير ملف الـ WAL.
  void maintenance() {
    try {
      raw.execute('PRAGMA optimize;');
      raw.execute('PRAGMA wal_checkpoint(TRUNCATE);');
    } catch (_) {}
  }

  void close() {
    for (final s in _statements.values) {
      s.close();
    }
    _statements.clear();
    raw.close();
  }
}

const _migrations = <String>[
  // v1: المحل، والفروع، والمستخدمين، والجلسات، والإعدادات، وسجل النشاط
  '''
  CREATE TABLE shop (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    phone       TEXT,
    address     TEXT,
    created_at  TEXT NOT NULL
  );

  CREATE TABLE branches (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    phone       TEXT,
    address     TEXT,
    is_local    INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL
  );

  CREATE TABLE users (
    id             TEXT PRIMARY KEY,
    branch_id      TEXT REFERENCES branches(id),
    name           TEXT NOT NULL,
    username       TEXT NOT NULL UNIQUE,
    password_hash  TEXT NOT NULL,
    role           TEXT NOT NULL CHECK (role IN ('owner', 'reception', 'technician')),
    active         INTEGER NOT NULL DEFAULT 1,
    created_at     TEXT NOT NULL,
    updated_at     TEXT NOT NULL
  );

  CREATE TABLE sessions (
    token_hash    TEXT PRIMARY KEY,
    user_id       TEXT NOT NULL REFERENCES users(id),
    device_name   TEXT,
    created_at    TEXT NOT NULL,
    last_seen_at  TEXT NOT NULL
  );
  CREATE INDEX idx_sessions_user ON sessions(user_id);

  CREATE TABLE settings (
    key    TEXT PRIMARY KEY,
    value  TEXT NOT NULL
  );

  CREATE TABLE audit_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     TEXT,
    action      TEXT NOT NULL,
    entity      TEXT,
    entity_id   TEXT,
    details     TEXT,
    created_at  TEXT NOT NULL
  );
  CREATE INDEX idx_audit_created ON audit_log(created_at);
  ''',

  // v2: العملاء، والأجهزة (الوصولات)، ومراحلها، والدفعات
  // الفلوس كلها بالقروش (INTEGER) عشان نتجنب أخطاء الكسور.
  '''
  CREATE TABLE customers (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    phone       TEXT NOT NULL,
    phone_norm  TEXT NOT NULL,
    whatsapp    TEXT,
    notes       TEXT,
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL
  );
  CREATE INDEX idx_customers_phone ON customers(phone_norm);
  CREATE INDEX idx_customers_name ON customers(name);

  CREATE TABLE tickets (
    id                  TEXT PRIMARY KEY,
    number              INTEGER NOT NULL UNIQUE,
    branch_id           TEXT REFERENCES branches(id),
    customer_id         TEXT NOT NULL REFERENCES customers(id),
    device_type         TEXT NOT NULL DEFAULT 'phone',
    brand               TEXT NOT NULL,
    model               TEXT NOT NULL,
    color               TEXT,
    imei                TEXT,
    problems            TEXT NOT NULL DEFAULT '[]',
    problem_desc        TEXT,
    powers_on           INTEGER,
    condition_flags     TEXT NOT NULL DEFAULT '[]',
    condition_notes     TEXT,
    accessories         TEXT NOT NULL DEFAULT '[]',
    lock_type           TEXT NOT NULL DEFAULT 'none',
    lock_secret         TEXT,
    estimated_cents     INTEGER NOT NULL DEFAULT 0,
    final_cents         INTEGER,
    due_at              TEXT,
    technician_id       TEXT REFERENCES users(id),
    status              TEXT NOT NULL,
    pickup_pin          TEXT NOT NULL,
    public_token        TEXT NOT NULL UNIQUE,
    created_by          TEXT REFERENCES users(id),
    created_at          TEXT NOT NULL,
    updated_at          TEXT NOT NULL,
    delivered_at        TEXT,
    delivered_by        TEXT REFERENCES users(id)
  );
  CREATE INDEX idx_tickets_status ON tickets(status);
  CREATE INDEX idx_tickets_customer ON tickets(customer_id);
  CREATE INDEX idx_tickets_technician ON tickets(technician_id);
  CREATE INDEX idx_tickets_created ON tickets(created_at);
  CREATE INDEX idx_tickets_imei ON tickets(imei);

  CREATE TABLE ticket_events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    ticket_id   TEXT NOT NULL REFERENCES tickets(id),
    type        TEXT NOT NULL,
    from_value  TEXT,
    to_value    TEXT,
    note        TEXT,
    internal    INTEGER NOT NULL DEFAULT 1,
    user_id     TEXT REFERENCES users(id),
    created_at  TEXT NOT NULL
  );
  CREATE INDEX idx_events_ticket ON ticket_events(ticket_id);

  CREATE TABLE payments (
    id            TEXT PRIMARY KEY,
    ticket_id     TEXT NOT NULL REFERENCES tickets(id),
    amount_cents  INTEGER NOT NULL,
    method        TEXT NOT NULL,
    kind          TEXT NOT NULL,
    note          TEXT,
    user_id       TEXT REFERENCES users(id),
    created_at    TEXT NOT NULL
  );
  CREATE INDEX idx_payments_ticket ON payments(ticket_id);
  CREATE INDEX idx_payments_created ON payments(created_at);
  ''',

  // v3: الرسائل (واتساب اللي اتفتح، و SMS اللي في الطابور أو اتبعت)
  '''
  CREATE TABLE messages (
    id           TEXT PRIMARY KEY,
    ticket_id    TEXT REFERENCES tickets(id),
    customer_id  TEXT REFERENCES customers(id),
    phone        TEXT NOT NULL,
    channel      TEXT NOT NULL,
    event        TEXT NOT NULL,
    body         TEXT NOT NULL,
    status       TEXT NOT NULL,
    error        TEXT,
    claimed_by   TEXT,
    claimed_at   TEXT,
    user_id      TEXT REFERENCES users(id),
    created_at   TEXT NOT NULL,
    sent_at      TEXT
  );
  CREATE INDEX idx_messages_ticket ON messages(ticket_id);
  CREATE INDEX idx_messages_status ON messages(status);
  ''',

  // v4: موافقة العميل على تكلفة زيادة، ومعاد الاستلام، والمزامنة مع صفحة التتبع
  '''
  ALTER TABLE tickets ADD COLUMN approval_state TEXT;
  ALTER TABLE tickets ADD COLUMN approval_cents INTEGER;
  ALTER TABLE tickets ADD COLUMN approval_note TEXT;
  ALTER TABLE tickets ADD COLUMN approval_at TEXT;
  ALTER TABLE tickets ADD COLUMN pickup_at TEXT;
  ALTER TABLE tickets ADD COLUMN sync_dirty INTEGER NOT NULL DEFAULT 1;
  CREATE INDEX idx_tickets_sync ON tickets(sync_dirty);
  CREATE INDEX idx_tickets_pickup ON tickets(pickup_at);
  -- أي تعديل على الجهاز بيعلّمه إنه محتاج يتبعت لصفحة التتبع تاني
  CREATE TRIGGER trg_tickets_dirty AFTER UPDATE ON tickets
  WHEN NEW.sync_dirty = 0 AND OLD.sync_dirty = 0
  BEGIN
    UPDATE tickets SET sync_dirty = 1 WHERE id = NEW.id;
  END;
  ''',

  // v5: نظام البيع: الأصناف، وحركة المخزون، والفواتير، والمرتجعات، والخزنة، وتحصيل الديون
  '''
  CREATE TABLE products (
    id            TEXT PRIMARY KEY,
    name          TEXT NOT NULL,
    barcode       TEXT UNIQUE,
    category      TEXT,
    cost_cents    INTEGER NOT NULL DEFAULT 0,
    price_cents   INTEGER NOT NULL DEFAULT 0,
    qty           INTEGER NOT NULL DEFAULT 0,
    low_stock     INTEGER NOT NULL DEFAULT 0,
    track_stock   INTEGER NOT NULL DEFAULT 1,
    serialized    INTEGER NOT NULL DEFAULT 0,
    active        INTEGER NOT NULL DEFAULT 1,
    notes         TEXT,
    created_at    TEXT NOT NULL,
    updated_at    TEXT NOT NULL
  );
  CREATE INDEX idx_products_name ON products(name);
  CREATE INDEX idx_products_category ON products(category);

  CREATE TABLE stock_moves (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id   TEXT NOT NULL REFERENCES products(id),
    qty_change   INTEGER NOT NULL,
    qty_after    INTEGER NOT NULL,
    reason       TEXT NOT NULL,
    ref_type     TEXT,
    ref_id       TEXT,
    note         TEXT,
    user_id      TEXT REFERENCES users(id),
    created_at   TEXT NOT NULL
  );
  CREATE INDEX idx_stock_moves_product ON stock_moves(product_id);

  CREATE TABLE register_sessions (
    id                   TEXT PRIMARY KEY,
    branch_id            TEXT REFERENCES branches(id),
    opened_by            TEXT REFERENCES users(id),
    opened_at            TEXT NOT NULL,
    opening_cash_cents   INTEGER NOT NULL DEFAULT 0,
    closed_by            TEXT REFERENCES users(id),
    closed_at            TEXT,
    expected_cash_cents  INTEGER,
    counted_cash_cents   INTEGER,
    kept_cash_cents      INTEGER,
    note                 TEXT
  );
  CREATE INDEX idx_sessions_open ON register_sessions(closed_at);

  CREATE TABLE sales (
    id              TEXT PRIMARY KEY,
    number          INTEGER NOT NULL UNIQUE,
    customer_id     TEXT REFERENCES customers(id),
    session_id      TEXT REFERENCES register_sessions(id),
    subtotal_cents  INTEGER NOT NULL,
    discount_cents  INTEGER NOT NULL DEFAULT 0,
    total_cents     INTEGER NOT NULL,
    paid_cents      INTEGER NOT NULL DEFAULT 0,
    returned_cents  INTEGER NOT NULL DEFAULT 0,
    note            TEXT,
    user_id         TEXT REFERENCES users(id),
    created_at      TEXT NOT NULL
  );
  CREATE INDEX idx_sales_created ON sales(created_at);
  CREATE INDEX idx_sales_customer ON sales(customer_id);

  CREATE TABLE sale_items (
    id                TEXT PRIMARY KEY,
    sale_id           TEXT NOT NULL REFERENCES sales(id),
    product_id        TEXT REFERENCES products(id),
    name              TEXT NOT NULL,
    qty               INTEGER NOT NULL,
    unit_price_cents  INTEGER NOT NULL,
    cost_cents        INTEGER NOT NULL DEFAULT 0,
    returned_qty      INTEGER NOT NULL DEFAULT 0
  );
  CREATE INDEX idx_sale_items_sale ON sale_items(sale_id);

  -- كل فلوس داخلة أو خارجة من الخزنة (بيع، صيانة، مصروف، تحصيل دين، مرتجع...)
  CREATE TABLE cash_moves (
    id            TEXT PRIMARY KEY,
    session_id    TEXT NOT NULL REFERENCES register_sessions(id),
    type          TEXT NOT NULL,
    amount_cents  INTEGER NOT NULL,
    method        TEXT NOT NULL,
    category      TEXT,
    ref_type      TEXT,
    ref_id        TEXT,
    note          TEXT,
    user_id       TEXT REFERENCES users(id),
    created_at    TEXT NOT NULL
  );
  CREATE INDEX idx_cash_moves_session ON cash_moves(session_id);
  CREATE INDEX idx_cash_moves_ref ON cash_moves(ref_type, ref_id);

  CREATE TABLE customer_payments (
    id            TEXT PRIMARY KEY,
    customer_id   TEXT NOT NULL REFERENCES customers(id),
    amount_cents  INTEGER NOT NULL,
    method        TEXT NOT NULL,
    note          TEXT,
    user_id       TEXT REFERENCES users(id),
    created_at    TEXT NOT NULL
  );
  CREATE INDEX idx_customer_payments_customer ON customer_payments(customer_id);
  ''',

  // v6: الأجهزة بالـ IMEI (جديد ومستعمل)، والموردين والمشتريات، والمحافظ والخدمات
  '''
  ALTER TABLE products ADD COLUMN warranty_months INTEGER NOT NULL DEFAULT 0;
  ALTER TABLE sale_items ADD COLUMN unit_id TEXT;

  CREATE TABLE suppliers (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    phone       TEXT,
    notes       TEXT,
    active      INTEGER NOT NULL DEFAULT 1,
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL
  );

  CREATE TABLE purchases (
    id           TEXT PRIMARY KEY,
    number       INTEGER NOT NULL UNIQUE,
    supplier_id  TEXT REFERENCES suppliers(id),
    total_cents  INTEGER NOT NULL,
    paid_cents   INTEGER NOT NULL DEFAULT 0,
    note         TEXT,
    user_id      TEXT REFERENCES users(id),
    created_at   TEXT NOT NULL
  );
  CREATE INDEX idx_purchases_supplier ON purchases(supplier_id);

  CREATE TABLE purchase_items (
    id               TEXT PRIMARY KEY,
    purchase_id      TEXT NOT NULL REFERENCES purchases(id),
    product_id       TEXT NOT NULL REFERENCES products(id),
    name             TEXT NOT NULL,
    qty              INTEGER NOT NULL,
    unit_cost_cents  INTEGER NOT NULL
  );
  CREATE INDEX idx_purchase_items_purchase ON purchase_items(purchase_id);

  CREATE TABLE supplier_payments (
    id            TEXT PRIMARY KEY,
    supplier_id   TEXT NOT NULL REFERENCES suppliers(id),
    amount_cents  INTEGER NOT NULL,
    method        TEXT NOT NULL,
    note          TEXT,
    user_id       TEXT REFERENCES users(id),
    created_at    TEXT NOT NULL
  );
  CREATE INDEX idx_supplier_payments_supplier ON supplier_payments(supplier_id);

  -- كل جهاز لوحده (موبايل جديد أو مستعمل) بالـ IMEI بتاعه، من الشرا لحد البيع
  CREATE TABLE units (
    id                  TEXT PRIMARY KEY,
    product_id          TEXT NOT NULL REFERENCES products(id),
    imei                TEXT NOT NULL,
    imei2               TEXT,
    condition           TEXT NOT NULL DEFAULT 'new',
    color               TEXT,
    storage             TEXT,
    notes               TEXT,
    cost_cents          INTEGER NOT NULL DEFAULT 0,
    price_cents         INTEGER,
    warranty_months     INTEGER,
    status              TEXT NOT NULL DEFAULT 'in_stock',
    source              TEXT NOT NULL,
    purchase_id         TEXT REFERENCES purchases(id),
    supplier_id         TEXT REFERENCES suppliers(id),
    seller_name         TEXT,
    seller_phone        TEXT,
    seller_national_id  TEXT,
    seller_id_photo     TEXT,
    sale_id             TEXT REFERENCES sales(id),
    sold_at             TEXT,
    created_by          TEXT REFERENCES users(id),
    created_at          TEXT NOT NULL,
    updated_at          TEXT NOT NULL
  );
  CREATE INDEX idx_units_imei ON units(imei);
  CREATE INDEX idx_units_imei2 ON units(imei2);
  CREATE INDEX idx_units_product ON units(product_id, status);

  CREATE TABLE files (
    id          TEXT PRIMARY KEY,
    kind        TEXT NOT NULL,
    mime        TEXT NOT NULL,
    size        INTEGER NOT NULL,
    user_id     TEXT REFERENCES users(id),
    created_at  TEXT NOT NULL
  );

  CREATE TABLE wallets (
    id             TEXT PRIMARY KEY,
    name           TEXT NOT NULL,
    kind           TEXT NOT NULL,
    phone          TEXT,
    balance_cents  INTEGER NOT NULL DEFAULT 0,
    active         INTEGER NOT NULL DEFAULT 1,
    created_at     TEXT NOT NULL
  );

  CREATE TABLE wallet_txns (
    id                TEXT PRIMARY KEY,
    wallet_id         TEXT NOT NULL REFERENCES wallets(id),
    type              TEXT NOT NULL,
    amount_cents      INTEGER NOT NULL,
    commission_cents  INTEGER NOT NULL DEFAULT 0,
    balance_after     INTEGER NOT NULL,
    customer_phone    TEXT,
    note              TEXT,
    user_id           TEXT REFERENCES users(id),
    created_at        TEXT NOT NULL
  );
  CREATE INDEX idx_wallet_txns_wallet ON wallet_txns(wallet_id, created_at);
  ''',

  // v7: ضمان الصيانة ومرتجعاتها، وقطع الغيار المستخدمة في كل جهاز، وعمولات الفنيين، وتذكير العملاء
  '''
  ALTER TABLE tickets ADD COLUMN warranty_days INTEGER;
  ALTER TABLE tickets ADD COLUMN warranty_until TEXT;
  ALTER TABLE tickets ADD COLUMN warranty_of TEXT REFERENCES tickets(id);
  ALTER TABLE tickets ADD COLUMN ready_at TEXT;
  ALTER TABLE tickets ADD COLUMN reminders_sent INTEGER NOT NULL DEFAULT 0;
  ALTER TABLE tickets ADD COLUMN last_reminder_at TEXT;
  CREATE INDEX idx_tickets_warranty_of ON tickets(warranty_of);

  ALTER TABLE users ADD COLUMN commission_type TEXT NOT NULL DEFAULT 'none';
  ALTER TABLE users ADD COLUMN commission_value INTEGER NOT NULL DEFAULT 0;

  CREATE TABLE ticket_parts (
    id           TEXT PRIMARY KEY,
    ticket_id    TEXT NOT NULL REFERENCES tickets(id),
    product_id   TEXT REFERENCES products(id),
    name         TEXT NOT NULL,
    qty          INTEGER NOT NULL,
    cost_cents   INTEGER NOT NULL DEFAULT 0,
    price_cents  INTEGER NOT NULL DEFAULT 0,
    user_id      TEXT REFERENCES users(id),
    created_at   TEXT NOT NULL
  );
  CREATE INDEX idx_ticket_parts_ticket ON ticket_parts(ticket_id);

  -- الأجهزة اللي جاهزة من قبل التحديث: بنعتبر آخر تعديل هو وقت ما بقت جاهزة
  UPDATE tickets SET ready_at = updated_at WHERE status IN ('ready', 'cancelled', 'unrepairable');
  ''',
];
