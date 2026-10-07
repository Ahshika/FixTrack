// اختبار ضغط FixTrack: أوردرات صيانة بتزيد من 500 لحد 10000 أوردر/دقيقة خلال 5 دقايق
import http from 'k6/http';
import { check } from 'k6';
import { Trend, Counter } from 'k6/metrics';

const BASE = __ENV.BASE || 'http://127.0.0.1:18790';
const orderTime = new Trend('order_time', true);
const readTime = new Trend('screen_time', true);
const ordersOk = new Counter('orders_ok');
const ordersFail = new Counter('orders_fail');

// 20 درجة × 15 ثانية = 5 دقايق: 500، 1000، ... 10000 أوردر في الدقيقة
const stages = [];
for (let i = 1; i <= 20; i++) {
  stages.push({ target: 500 * i, duration: '1s' });
  stages.push({ target: 500 * i, duration: '14s' });
}

export const options = {
  setupTimeout: '60s',
  scenarios: {
    orders: {
      executor: 'ramping-arrival-rate',
      exec: 'createOrder',
      startRate: 500,
      timeUnit: '1m',
      preAllocatedVUs: 50,
      maxVUs: 600,
      stages,
    },
    // باقي أجهزة المحل (الشاشة الرئيسية وقايمة الأجهزة) شغالة في نفس الوقت
    screens: {
      executor: 'constant-arrival-rate',
      exec: 'readScreens',
      rate: 2,
      timeUnit: '1s',
      duration: '300s',
      preAllocatedVUs: 5,
      maxVUs: 50,
    },
  },
  thresholds: {
    'http_req_failed': ['rate<0.01'],
    'order_time': ['p(95)<1000'],
  },
};

export function setup() {
  const r = http.post(`${BASE}/api/setup`, JSON.stringify({ shopName: 'محل اختبار الضغط', ownerName: 'تجربة', username: 'owner', password: 'owner123' }),
    { headers: { 'Content-Type': 'application/json' } });
  if (r.status !== 200) throw new Error(`setup failed ${r.status} ${r.body}`);
  return { token: r.json('token') };
}

const brands = ['Samsung', 'iPhone', 'Oppo', 'Xiaomi', 'Realme', 'Infinix'];
const problems = ['الشاشة', 'البطارية', 'الشحن', 'السماعة', 'الكاميرا', 'سوفت وير'];

export function createOrder(data) {
  const n = __VU * 100000 + __ITER;
  const body = {
    customer: { name: `عميل ${n}`, phone: `010${String(10000000 + (n % 90000000)).slice(-8)}` },
    brand: brands[n % brands.length],
    model: `Model ${n % 40}`,
    problems: [problems[n % problems.length]],
    estimatedCents: 150000,
    depositCents: n % 3 === 0 ? 20000 : 0,
    depositMethod: 'cash',
  };
  const r = http.post(`${BASE}/api/tickets`, JSON.stringify(body), {
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${data.token}` },
    tags: { name: 'create_order' },
    timeout: '30s',
  });
  orderTime.add(r.timings.duration);
  const ok = check(r, { 'order saved': (x) => x.status === 200 });
  if (ok) ordersOk.add(1); else ordersFail.add(1, { status: String(r.status) });
}

export function readScreens(data) {
  const h = { headers: { Authorization: `Bearer ${data.token}` }, timeout: '30s' };
  const a = http.get(`${BASE}/api/dashboard`, Object.assign({ tags: { name: 'dashboard' } }, h));
  const b = http.get(`${BASE}/api/tickets?scope=active&limit=200`, Object.assign({ tags: { name: 'tickets_list' } }, h));
  readTime.add(a.timings.duration, { screen: 'dashboard' });
  readTime.add(b.timings.duration, { screen: 'tickets_list' });
  check(a, { 'dashboard ok': (x) => x.status === 200 });
  check(b, { 'tickets list ok': (x) => x.status === 200 });
}
