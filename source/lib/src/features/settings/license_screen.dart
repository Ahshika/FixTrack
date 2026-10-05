import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../messages/message_dialog.dart';
import '../tickets/providers.dart';

const _planLabels = {'trial': 'تجربة مجانية', 'monthly': 'شهري', 'yearly': 'سنوي', 'lifetime': 'مدى الحياة', 'custom': 'اشتراك'};

/// شريط بيظهر فوق الرئيسية لو التجربة أو الاشتراك قرّب يخلص أو خلص.
class LicenseBanner extends ConsumerWidget {
  const LicenseBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(licenseProvider).value;
    if (s == null) return const SizedBox.shrink();
    final state = s['state'] as String;
    final days = s['daysLeft'] as int?;
    final scheme = Theme.of(context).colorScheme;
    String? text;
    var color = brandOrange;
    if (state == 'expired') {
      text = s['plan'] == 'trial' ? 'التجربة المجانية خلصت. فعّل البرنامج عشان تكمّل تسجيل شغل جديد.' : 'الاشتراك خلص. جدّده عشان تكمّل تسجيل شغل جديد.';
      color = scheme.error;
    } else if (state == 'tampered') {
      text = 'تاريخ الكمبيوتر مش مظبوط، ظبطه عشان البرنامج يشتغل.';
      color = scheme.error;
    } else if (state == 'trial') {
      text = 'تجربة مجانية: فاضل ${days ?? 0} يوم';
      color = brandBlue;
    } else if (days != null && days <= 7) {
      text = 'الاشتراك هيخلص بعد $days يوم';
    }
    if (text == null) return const SizedBox.shrink();
    final isOwner = ref.watch(sessionProvider).value?.user?.isOwner ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: isOwner ? () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const LicenseScreen())) : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(state == 'trial' ? Icons.hourglass_bottom_rounded : Icons.workspace_premium_rounded, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(color: color).semiBold)),
              if (isOwner) Text('التفعيل', style: TextStyle(color: color).bold),
            ]),
          ),
        ),
      ),
    );
  }
}

class LicenseScreen extends ConsumerStatefulWidget {
  const LicenseScreen({super.key});

  @override
  ConsumerState<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends ConsumerState<LicenseScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider).value!.api!.post('/api/license', {'code': _code.text.trim()});
      ref.invalidate(licenseProvider);
      _code.clear();
      if (mounted) showMessage(context, 'اتفعّل البرنامج ✅ شكراً!');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(licenseProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('الاشتراك')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: ErrorBanner(errorText(e))),
        data: (s) {
          final state = s['state'] as String;
          final exp = parseDate(s['expiresAt']);
          final device = s['deviceCode'] as String;
          final (label, color) = switch (state) {
            'active' => ('مفعّل ✅', const Color(0xFF16A34A)),
            'trial' => ('تجربة مجانية', brandBlue),
            'tampered' => ('تاريخ الجهاز مش مظبوط', Theme.of(context).colorScheme.error),
            _ => ('خلص', Theme.of(context).colorScheme.error),
          };
          return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(label, style: text.headlineSmall?.bold.copyWith(color: color)),
                        const SizedBox(height: 6),
                        Text('النوع: ${_planLabels[s['plan']] ?? s['plan']}'),
                        Text(exp == null ? 'مدى الحياة' : '${state == 'expired' ? 'خلص' : 'لحد'} ${formatDate(exp)}'
                            '${s['daysLeft'] != null && state != 'expired' ? ' (فاضل ${s['daysLeft']} يوم)' : ''}'),
                        Text('عدد الأجهزة المسموح: ${s['devices']}'),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(title: 'كود الجهاز', icon: Icons.fingerprint_rounded, children: [
                    const Text('ابعت الكود ده لصاحب البرنامج عشان يعملك كود التفعيل:'),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: SelectableText(device, textDirection: TextDirection.ltr, style: text.headlineSmall?.bold.copyWith(letterSpacing: 3)),
                      ),
                      IconButton(
                        tooltip: 'نسخ',
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: device));
                          showMessage(context, 'اتنسخ كود الجهاز');
                        },
                      ),
                    ]),
                    if (supportWhatsApp.isNotEmpty)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                        onPressed: () => openWhatsApp(supportWhatsApp, activationMessage(s)),
                        icon: const Icon(Icons.chat_rounded),
                        label: const Text('ابعته واتساب لصاحب البرنامج'),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  SectionCard(title: 'كود التفعيل', icon: Icons.key_rounded, children: [
                    TextField(
                      controller: _code,
                      minLines: 3,
                      maxLines: 5,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(hintText: 'الصق كود التفعيل هنا (بيبدأ بـ FT1.)'),
                    ),
                    if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
                    const SizedBox(height: 12),
                    BusyButton(label: 'تفعيل', icon: Icons.verified_rounded, busy: _busy, onPressed: _activate),
                  ]),
                  const SizedBox(height: 12),
                  Text('لو الاشتراك خلص، كل بياناتك بتفضل موجودة، وتقدر تسلّم الأجهزة اللي عندك وتشوف التقارير. اللي بيقف بس تسجيل شغل جديد.',
                      style: text.bodySmall),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// رسالة طلب التفعيل اللي بتتبعت لصاحب البرنامج على واتساب.
String activationMessage(Map<String, dynamic> s) {
  String? v(String k) {
    final x = (s[k] as String?)?.trim();
    return x == null || x.isEmpty ? null : x;
  }

  return [
    'طلب تفعيل FixTrack',
    if (v('shopName') != null) 'المحل: ${v('shopName')}',
    if (v('branchName') != null && v('branchName') != 'الفرع الرئيسي') 'الفرع: ${v('branchName')}',
    if (v('ownerName') != null) 'صاحب المحل: ${v('ownerName')}',
    if (v('shopPhone') != null) 'التليفون: ${v('shopPhone')}',
    'كود الجهاز: ${s['deviceCode']}',
  ].join('\n');
}
