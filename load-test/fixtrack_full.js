// اختبار ضغط شامل لـ FixTrack: كل أنواع العمليات، من 500 لحد 10000 عملية/دقيقة في 5 دقايق
import http from 'k6/http';
import { check } from 'k6';
import { Trend, Counter } from 'k6/metrics';
import encoding from 'k6/encoding';

const BASE = __ENV.BASE || 'http://127.0.0.1:18790';
const opTime = new Trend('op_time', true);        // وقت العملية كلها (كل طلباتها)
const reqTime = new Trend('req_time', true);      // وقت كل طلب لوحده، متقسم بنوع الطلب
const opsOk = new Counter('ops_ok');
const opsFail = new Counter('ops_fail');
const screenTime = new Trend('screen_time', true);
const backupTime = new Trend('backup_time', true);

const stages = [];
for (let i = 1; i <= 20; i++) {
  stages.push({ target: 500 * i, duration: '1s' });
  stages.push({ target: 500 * i, duration: '14s' });
}

export const options = {
  setupTimeout: '120s',
  scenarios: {
    ops: { executor: 'ramping-arrival-rate', exec: 'operation', startRate: 500, timeUnit: '1m', preAllocatedVUs: 80, maxVUs: 800, stages },
    screens: { executor: 'constant-arrival-rate', exec: 'screens', rate: 3, timeUnit: '1s', duration: '300s', preAllocatedVUs: 10, maxVUs: 80 },
    backup: { executor: 'shared-iterations', exec: 'backup', vus: 1, iterations: 1, startTime: '150s', maxDuration: '150s' },
  },
  thresholds: { http_req_failed: ['rate<0.01'], op_time: ['p(95)<1500'] },
};

const JPEG = encoding.b64encode(new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 74, 70, 73, 70, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0xFF, 0xD9]).buffer);
let token;
let failLogs = 0;

function req(method, path, body, name) {
  const params = { headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` }, tags: { name }, timeout: '60s' };
  const r = http.request(method, `${BASE}${path}`, body === undefined ? null : JSON.stringify(body), params);
  reqTime.add(r.timings.duration, { req: name });
  if (r.status !== 200) {
    if (failLogs++ < 15) console.error(`FAIL ${name} ${r.status} ${String(r.body).slice(0, 200)}`);
    throw new Error(`${name} ${r.status}`);
  }
  return r.json();
}

function setupPost(t, path, body) {
  const r = http.post(`${BASE}${path}`, JSON.stringify(body), { headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${t}` } });
  if (r.status !== 200) throw new Error(`setup ${path} ${r.status} ${r.body}`);
  return r.json();
}

export function setup() {
  const t = setupPost('', '/api/setup', { shopName: 'محل اختبار الضغط', ownerName: 'تجربة', username: 'owner', password: 'owner123' }).token;
  const products = [];
  for (let i = 0; i < 300; i++) {
    products.push(setupPost(t, '/api/products', { name: `اكسسوار ${i}`, category: `قسم ${i % 12}`, barcode: `62${String(100000 + i)}`, costCents: 1000, priceCents: 2500, qty: 1000000, lowStock: 2 }).product.id);
  }
  const phones = [];
  for (let i = 0; i < 10; i++) {
    phones.push(setupPost(t, '/api/products', { name: `Samsung A${i}5 128GB`, category: 'موبايلات', costCents: 800000, priceCents: 950000, serialized: true, warrantyMonths: 12 }).product.id);
  }
  const customers = [];
  for (let i = 0; i < 50; i++) customers.push(setupPost(t, '/api/customers', { name: `عميل آجل ${i}`, phone: `0115${String(1000000 + i)}` }).customer.id);
  const wallet = setupPost(t, '/api/wallets', { name: 'فودافون كاش', kind: 'vodafone', balanceCents: 1000000000 }).wallet.id;
  const supplier = setupPost(t, '/api/suppliers', { name: 'مورد الاختبار', phone: '0222333444' }).supplier.id;
  return { token: t, products, phones, customers, wallet, supplier };
}

function uniq() { return __VU * 1000000 + __ITER; }
function pick(a, n) { return a[n % a.length]; }
function imei(n, prefix) { return `${prefix}${String(n).padStart(15 - prefix.length, '0')}`.slice(0, 15); }

const OPS = {
  // بيع اكسسوارات كاش
  sale(d, n) {
    const p1 = pick(d.products, n), p2 = pick(d.products, n * 7 + 3);
    req('POST', '/api/sales', { items: [{ productId: p1, qty: 1 }, { productId: p2, qty: 2 }], payments: [{ method: 'cash', amountCents: 7500 }] }, 'sale');
  },
  // بيع بالآجل لعميل + تحصيل جزء
  credit_sale(d, n) {
    const c = pick(d.customers, n);
    req('POST', '/api/sales', { customerId: c, items: [{ productId: pick(d.products, n), qty: 4 }], payments: [{ method: 'cash', amountCents: 5000 }] }, 'credit_sale');
    req('POST', `/api/customers/${c}/payments`, { amountCents: 2500, method: 'vodafoneCash' }, 'customer_payment');
  },
  // بيع وبعدين مرتجع
  sale_return(d, n) {
    const s = req('POST', '/api/sales', { items: [{ productId: pick(d.products, n), qty: 3 }], payments: [{ method: 'cash', amountCents: 7500 }] }, 'sale');
    req('POST', `/api/sales/${s.sale.id}/return`, { items: [{ saleItemId: s.items[0].id, qty: 1 }] }, 'sale_return');
  },
  // استلام جهاز صيانة
  repair_intake(d, n) {
    req('POST', '/api/tickets', { customer: { name: `عميل ${n}`, phone: `010${String(n % 100000000).padStart(8, '0')}` }, brand: pick(['Samsung', 'iPhone', 'Oppo', 'Xiaomi'], n), model: `Model ${n % 40}`, problems: ['الشاشة'], estimatedCents: 150000, depositCents: 20000, depositMethod: 'cash' }, 'ticket_create');
  },
  // دورة صيانة كاملة: استلام، قطعة غيار، جاهز، تسليم
  repair_cycle(d, n) {
    const t = req('POST', '/api/tickets', { customer: { name: `عميل ${n}`, phone: `012${String(n % 100000000).padStart(8, '0')}` }, brand: 'Samsung', model: 'A55', problems: ['البطارية'], estimatedCents: 80000 }, 'ticket_create').ticket;
    req('POST', `/api/tickets/${t.id}/parts`, { productId: pick(d.products, n), qty: 1, addToBill: true }, 'ticket_part');
    req('POST', `/api/tickets/${t.id}/status`, { status: 'ready' }, 'ticket_status');
    req('GET', `/api/tickets/${t.id}`, undefined, 'ticket_detail');
    req('POST', `/api/tickets/${t.id}/deliver`, { pin: t.pickupPin, paymentCents: 82500, warrantyDays: 30 }, 'ticket_deliver');
  },
  // طلب موافقة العميل على تكلفة زيادة
  approval(d, n) {
    const t = req('POST', '/api/tickets', { customer: { name: `عميل ${n}`, phone: `011${String(n % 100000000).padStart(8, '0')}` }, brand: 'iPhone', model: '13', problems: ['الشحن'], estimatedCents: 100000 }, 'ticket_create').ticket;
    req('POST', `/api/tickets/${t.id}/approval`, { totalCents: 160000, note: 'الفلاتة بايظة' }, 'approval_request');
    req('POST', `/api/tickets/${t.id}/approval/resolve`, { approved: n % 4 !== 0 }, 'approval_resolve');
  },
  // محافظ وشحن
  wallet(d, n) {
    req('POST', `/api/wallets/${d.wallet}/txns`, { type: pick(['cash_in', 'cash_out', 'recharge'], n), amountCents: 20000, commissionCents: 500 }, 'wallet_txn');
  },
  // مصروف من الدرج
  expense(d, n) {
    req('POST', '/api/cash/moves', { type: 'expense', amountCents: 1500, category: 'أكل وشرب' }, 'expense');
  },
  // شرا موبايل مستعمل: صورة البطاقة + بيانات البايع
  buy_used(d, n) {
    const photo = req('POST', '/api/files', { data: JPEG, kind: 'national_id' }, 'file_upload').id;
    req('POST', '/api/units/buy-used', { model: 'iPhone 12 128GB', imei: imei(n, '35'), color: 'أزرق', sellerName: 'محمد علي', sellerPhone: '01012345678', sellerNationalId: '29001011234567', idPhotoId: photo, costCents: 900000, priceCents: 1100000 }, 'buy_used');
    req('GET', `/api/imei/${imei(n, '35')}`, undefined, 'imei_history');
  },
  // فاتورة شرا من مورد: موبايلات بالـ IMEI + اكسسوارات
  purchase(d, n) {
    req('POST', '/api/purchases', { supplierId: d.supplier, items: [
      { productId: pick(d.phones, n), unitCostCents: 800000, units: [{ imei: imei(n, '86') }, { imei: imei(n, '87') }] },
      { productId: pick(d.products, n), qty: 20, unitCostCents: 1000 },
    ], paidCents: 1000000 }, 'purchase');
    if (n % 5 === 0) req('POST', `/api/suppliers/${d.supplier}/payments`, { amountCents: 100000, method: 'cash' }, 'supplier_payment');
  },
  // بيع موبايل جديد بالـ IMEI: دخول المخزن، مسح الباركود، بيع
  phone_sale(d, n) {
    const code = imei(n, '49');
    const pid = pick(d.phones, n);
    req('POST', '/api/units', { productId: pid, units: [{ imei: code }] }, 'unit_add');
    const l = req('GET', `/api/products/lookup?barcode=${code}`, undefined, 'barcode_lookup');
    req('POST', '/api/sales', { items: [{ productId: pid, qty: 1, unitId: l.unit.id }], payments: [{ method: 'cash', amountCents: 950000 }] }, 'phone_sale');
  },
  // صنف جديد وجرد
  stock(d, n) {
    const p = req('POST', '/api/products', { name: `صنف جديد ${n}`, category: 'جديد', costCents: 500, priceCents: 1500, qty: 10 }, 'product_create').product;
    req('POST', `/api/products/${p.id}/adjust`, { qtyChange: 5, reason: 'purchase' }, 'stock_adjust');
    req('GET', `/api/products/lookup?barcode=62${String(100000 + (n % 300))}`, undefined, 'barcode_lookup');
  },
};

// نسبة كل عملية من الشغل (قريبة من يوم محل عادي)
const MIX = [['sale', 30], ['credit_sale', 6], ['sale_return', 4], ['repair_intake', 15], ['repair_cycle', 12], ['approval', 4],
  ['wallet', 10], ['expense', 3], ['buy_used', 3], ['purchase', 3], ['phone_sale', 5], ['stock', 5]];
const WHEEL = [];
for (const [k, w] of MIX) for (let i = 0; i < w; i++) WHEEL.push(k);

export function operation(d) {
  token = d.token;
  const n = uniq();
  const op = WHEEL[(n * 7919) % WHEEL.length];
  const start = Date.now();
  try {
    OPS[op](d, n);
    opsOk.add(1, { op });
  } catch (e) {
    opsFail.add(1, { op });
  }
  opTime.add(Date.now() - start, { op });
}

const SCREENS = [
  ['dashboard', '/api/dashboard'], ['tickets_list', '/api/tickets?scope=active&limit=200'], ['tickets_search', '/api/tickets?scope=all&q=%D8%B9%D9%85%D9%8A%D9%84%205&limit=200'],
  ['products_list', '/api/products'], ['products_search', '/api/products?q=%D8%A7%D9%83%D8%B3'], ['sales_list', '/api/sales'], ['customers_search', '/api/customers?q=010'],
  ['cash_current', '/api/cash/current'], ['reminders', '/api/reminders'], ['report', '/api/reports/summary'], ['audit', '/api/audit'], ['wallets', '/api/wallets'],
  ['suppliers', '/api/suppliers'], ['purchases', '/api/purchases'], ['units', '/api/units'],
];

export function screens(d) {
  token = d.token;
  const [name, path] = SCREENS[__ITER % SCREENS.length];
  const r = http.get(`${BASE}${path}`, { headers: { Authorization: `Bearer ${token}` }, tags: { name }, timeout: '60s' });
  screenTime.add(r.timings.duration, { screen: name });
  if (!check(r, { 'screen ok': (x) => x.status === 200 }) && failLogs++ < 15) console.error(`FAIL screen ${name} ${r.status} ${String(r.body).slice(0, 200)}`);
}

export function backup(d) {
  token = d.token;
  const r = http.post(`${BASE}/api/backups`, null, { headers: { Authorization: `Bearer ${token}` }, tags: { name: 'backup' }, timeout: '140s' });
  backupTime.add(r.timings.duration);
  console.log(`BACKUP status=${r.status} took=${Math.round(r.timings.duration)}ms`);
}

// تجربة سريعة: كل عملية مرة واحدة (k6 run -i 1 -u 1)
export default function (d) {
  token = d.token;
  for (const k of Object.keys(OPS)) {
    try { OPS[k](d, uniq() + k.length * 7); console.log(`OK ${k}`); } catch (e) { console.error(`BAD ${k}: ${e}`); }
  }
  for (const [name, path] of SCREENS) {
    const r = http.get(`${BASE}${path}`, { headers: { Authorization: `Bearer ${token}` } });
    if (r.status !== 200) console.error(`BAD screen ${name} ${r.status} ${String(r.body).slice(0, 150)}`);
  }
}
