# يحوّل نتايج k6 + قراءات السيرفر لداشبورد Grafana (مصدر TestData، بيانات CSV مضمّنة)
# python make_dashboard.py <folder> <datasource uid> <orders|full>
import csv, json, sys, os
from collections import defaultdict
from datetime import datetime, timezone

S = os.path.abspath(sys.argv[1])
DS_UID = sys.argv[2]
MODE = sys.argv[3]
B = 5

OP_AR = {'sale': 'بيع كاش', 'credit_sale': 'بيع آجل + تحصيل', 'sale_return': 'بيع + مرتجع', 'repair_intake': 'استلام جهاز صيانة',
         'repair_cycle': 'دورة صيانة كاملة', 'approval': 'موافقة على تكلفة', 'wallet': 'محافظ وشحن', 'expense': 'مصروف',
         'buy_used': 'شرا مستعمل', 'purchase': 'فاتورة مورد', 'phone_sale': 'بيع موبايل بالـ IMEI', 'stock': 'صنف جديد وجرد'}

def iso(t): return datetime.fromtimestamp(t, timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
def pct(v, p):
    if not v: return ''
    v = sorted(v); return round(v[min(len(v) - 1, int(len(v) * p))], 1)

okm, failm, timem = ('orders_ok', 'orders_fail', 'order_time') if MODE == 'orders' else ('ops_ok', 'ops_fail', 'op_time')
lat = defaultdict(list); ok = defaultdict(int); fail = defaultdict(int); scr = defaultdict(list)
per_op = defaultdict(list); per_op_fail = defaultdict(int); per_req = defaultdict(list); per_screen = defaultdict(list)
t0 = None
with open(os.path.join(S, 'results.csv'), newline='', encoding='utf-8') as f:
    for r in csv.DictReader(f):
        if not r['scenario']: continue
        t = int(r['timestamp']); m = r['metric_name']; v = float(r['metric_value']); tag = (r['extra_tags'] or '').split('=')[-1]
        if m not in (okm, failm, timem, 'screen_time', 'req_time'): continue
        t0 = t if t0 is None else min(t0, t); b = t - t % B
        if m == timem: lat[b].append(v); per_op[tag].append(v)
        elif m == okm: ok[b] += 1
        elif m == failm: fail[b] += 1; per_op_fail[tag] += 1
        elif m == 'screen_time': scr[b].append(v); per_screen[tag].append(v)
        elif m == 'req_time': per_req[tag].append(v)

buckets = sorted(set(lat) | set(scr))
unit_word = 'أوردر' if MODE == 'orders' else 'عملية'
rows_rate = ['time,target,saved,failed']
rows_lat = ['time,p50,p95,max,screens_p95']
for b in buckets:
    step = min(20, (b - t0) // 15 + 1)
    rows_rate.append(f'{iso(b)},{step*500},{ok[b]*60//B},{fail[b]*60//B}')
    rows_lat.append(f'{iso(b)},{pct(lat[b],.5)},{pct(lat[b],.95)},{pct(lat[b],1)},{pct(scr[b],.95)}')

rows_res = ['time,cpu,mem,db']
with open(os.path.join(S, 'server_res.csv')) as f:
    for r in csv.DictReader(f):
        t = int(r['time']) // 1000
        if buckets[0] - 10 <= t <= buckets[-1] + 10 and t % 6 < 2:
            rows_res.append(f"{iso(t)},{r['cpu_pct']},{r['mem_mb']},{r['db_mb']}")

M = json.load(open(os.path.join(S, 'summary.json')))['metrics']
stat_csv = 'saved,failed,p95,max,dropped\n%d,%d,%.0f,%.0f,%d' % (M.get(okm, {}).get('count', 0), M.get(failm, {}).get('count', 0),
    M[timem]['p(95)'], M[timem]['max'], M.get('dropped_iterations', {}).get('count', 0))

ds = {'type': 'grafana-testdata-datasource', 'uid': DS_UID}
def q(c): return [{'refId': 'A', 'datasource': ds, 'scenarioId': 'csv_content', 'csvContent': c}]
def rn(field, name, color=None, unit=None):
    props = [{'id': 'displayName', 'value': name}]
    if color: props.append({'id': 'color', 'value': {'mode': 'fixed', 'fixedColor': color}})
    if unit: props.append({'id': 'unit', 'value': unit})
    return {'matcher': {'id': 'byName', 'options': field}, 'properties': props}
def ts(title, c, unit, x, y, w=12, h=9, ov=None, desc=''):
    return {'type': 'timeseries', 'title': title, 'description': desc, 'datasource': ds, 'gridPos': {'x': x, 'y': y, 'w': w, 'h': h}, 'targets': q(c),
            'fieldConfig': {'defaults': {'unit': unit, 'custom': {'lineWidth': 2, 'fillOpacity': 8, 'spanNulls': True}}, 'overrides': ov or []},
            'options': {'legend': {'displayMode': 'list', 'placement': 'bottom'}, 'tooltip': {'mode': 'multi'}}}
def col(rows, i): return '\n'.join(r.split(',')[0] + ',' + r.split(',')[i] for r in rows)
def table(title, header, rows, x, y, w, h, ov):
    return {'type': 'table', 'title': title, 'datasource': ds, 'gridPos': {'x': x, 'y': y, 'w': w, 'h': h}, 'targets': q('\n'.join([header] + rows)),
            'fieldConfig': {'defaults': {'custom': {'align': 'auto'}}, 'overrides': ov}, 'options': {'showHeader': True}}

panels = [
    {'type': 'stat', 'title': 'ملخص الاختبار', 'datasource': ds, 'gridPos': {'x': 0, 'y': 0, 'w': 24, 'h': 5}, 'targets': q(stat_csv),
     'fieldConfig': {'defaults': {}, 'overrides': [rn('saved', f'{unit_word} نجحت', 'green'), rn('failed', f'{unit_word} فشلت', 'red'),
        rn('p95', '95% خلصت في أقل من', 'orange', 'ms'), rn('max', 'الأبطأ', 'red', 'ms'), rn('dropped', 'ما اتبعتتش (السيرفر مش ملاحق)', 'purple')]},
     'options': {'reduceOptions': {'calcs': ['lastNotNull']}, 'colorMode': 'value', 'graphMode': 'none', 'textMode': 'value_and_name'}},
    ts(f'{unit_word} في الدقيقة: المطلوب مقابل اللي اتنفذ فعلاً', '\n'.join(rows_rate), 'short', 0, 5,
       ov=[rn('target', 'المطلوب', 'blue'), rn('saved', 'اتنفذ', 'green'), rn('failed', 'فشل', 'red')],
       desc='لما الأخضر ينزل تحت الأزرق يبقى السيرفر وصل لأقصى حاجة يقدر عليها'),
    ts(f'وقت تنفيذ ال{unit_word}', '\n'.join(rows_lat), 'ms', 12, 5,
       ov=[rn('p50', 'العادي (50%)', 'green'), rn('p95', '95%', 'orange'), rn('max', 'الأبطأ', 'red'), rn('screens_p95', 'فتح الشاشات (95%)', 'purple')]),
    ts('معالج السيرفر (من كل أنوية الجهاز)', col(rows_res, 1), 'percent', 0, 14, w=8, ov=[rn('cpu', 'المعالج')]),
    ts('ذاكرة السيرفر', col(rows_res, 2), 'decmbytes', 8, 14, w=8, ov=[rn('mem', 'الذاكرة')]),
    ts('حجم قاعدة البيانات', col(rows_res, 3), 'decmbytes', 16, 14, w=8, ov=[rn('db', 'الحجم')]),
]
y = 23
ms = lambda f, n: rn(f, n, unit='ms')
if MODE == 'full':
    rows = [f'{OP_AR.get(k, k)},{len(v)},{per_op_fail[k]},{pct(v,.5)},{pct(v,.95)},{pct(v,1)}' for k, v in sorted(per_op.items(), key=lambda kv: -pct(kv[1], .95))]
    panels.append(table('كل نوع عملية لوحده', 'op,count,failed,p50,p95,max', rows, 0, y, 12, 12,
        [rn('op', 'العملية'), rn('count', 'العدد'), rn('failed', 'فشل'), ms('p50', 'العادي'), ms('p95', '95%'), ms('max', 'الأبطأ')]))
    rows = [f'{k},{len(v)},{pct(v,.5)},{pct(v,.95)},{pct(v,1)}' for k, v in sorted(per_screen.items(), key=lambda kv: -pct(kv[1], .95))]
    panels.append(table('فتح الشاشات أثناء الضغط', 'screen,count,p50,p95,max', rows, 12, y, 12, 12,
        [rn('screen', 'الشاشة'), rn('count', 'العدد'), ms('p50', 'العادي'), ms('p95', '95%'), ms('max', 'الأبطأ')]))
    y += 12
    rows = [f'{k},{len(v)},{pct(v,.5)},{pct(v,.95)},{pct(v,1)}' for k, v in sorted(per_req.items(), key=lambda kv: -pct(kv[1], .95))]
    panels.append(table('كل طلب لوحده', 'req,count,p50,p95,max', rows, 0, y, 24, 12,
        [rn('req', 'الطلب'), rn('count', 'العدد'), ms('p50', 'العادي'), ms('p95', '95%'), ms('max', 'الأبطأ')]))

title = 'FixTrack - اختبار ضغط الأوردرات' if MODE == 'orders' else 'FixTrack - اختبار ضغط شامل'
dash = {'title': title, 'uid': 'fixtrack-load-' + MODE, 'schemaVersion': 39, 'editable': True, 'panels': panels,
        'time': {'from': iso(buckets[0] - 5), 'to': iso(buckets[-1] + 10)}, 'timezone': 'browser'}
json.dump(dash, open(os.path.join(S, 'grafana_dashboard.json'), 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
print('ok', len(buckets))
