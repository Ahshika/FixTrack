import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_config.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// تسجيل المحل لأول مرة على السيرفر: بيانات المحل وحساب صاحب المحل.
class CreateShopScreen extends ConsumerStatefulWidget {
  const CreateShopScreen({super.key});

  @override
  ConsumerState<CreateShopScreen> createState() => _CreateShopScreenState();
}

class _CreateShopScreenState extends ConsumerState<CreateShopScreen> {
  final _form = GlobalKey<FormState>();
  final _shopName = TextEditingController();
  final _shopPhone = TextEditingController();
  final _shopAddress = TextEditingController();
  final _branchName = TextEditingController(text: 'الفرع الرئيسي');
  final _ownerName = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_shopName, _shopPhone, _shopAddress, _branchName, _ownerName, _username, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).completeSetup({
        'shopName': _shopName.text,
        'shopPhone': _shopPhone.text,
        'shopAddress': _shopAddress.text,
        'branchName': _branchName.text,
        'ownerName': _ownerName.text,
        'username': _username.text,
        'password': _password.text,
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _required(String? v, String label) => (v == null || v.trim().isEmpty) ? 'لازم تكتب $label' : null;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isServer = ref.read(appConfigProvider).mode == AppMode.server;

    if (!isServer) {
      return CenteredPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FixTrackLogo(size: 56),
            const SizedBox(height: 24),
            Text('السيرفر لسه ما اتجهزش', style: text.titleLarge?.bold, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('لازم تسجل بيانات المحل الأول من برنامج الكمبيوتر اللي شغال كسيرفر، وبعدها ارجع هنا.',
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => ref.read(sessionProvider.notifier).retry(), child: const Text('حاول تاني')),
            TextButton(
              onPressed: () => ref.read(sessionProvider.notifier).resetConnection(),
              child: const Text('اختار سيرفر تاني'),
            ),
          ],
        ),
      );
    }

    return CenteredPanel(
      maxWidth: 560,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FixTrackLogo(size: 56),
            const SizedBox(height: 24),
            Text('أهلاً بيك! يلا نسجل المحل', style: text.titleLarge?.bold),
            const SizedBox(height: 4),
            const Text('البيانات دي هتظهر في الوصولات ورسايل العملاء، وتقدر تعدلها بعدين من الإعدادات.'),
            const SectionTitle('بيانات المحل'),
            TextFormField(
              controller: _shopName,
              decoration: const InputDecoration(labelText: 'اسم المحل *', prefixIcon: Icon(Icons.storefront_rounded)),
              validator: (v) => _required(v, 'اسم المحل'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _shopPhone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'رقم تليفون المحل', prefixIcon: Icon(Icons.call_rounded)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _shopAddress,
              decoration: const InputDecoration(labelText: 'العنوان', prefixIcon: Icon(Icons.place_rounded)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _branchName,
              decoration: const InputDecoration(labelText: 'اسم الفرع', prefixIcon: Icon(Icons.account_tree_rounded)),
            ),
            const SizedBox(height: 8),
            const SectionTitle('حساب صاحب المحل'),
            TextFormField(
              controller: _ownerName,
              decoration: const InputDecoration(labelText: 'اسمك *', prefixIcon: Icon(Icons.person_rounded)),
              validator: (v) => _required(v, 'اسمك'),
            ),
            const SizedBox(height: 12),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextFormField(
                controller: _username,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'اسم المستخدم (بالإنجليزي) *',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
                validator: (v) => RegExp(r'^[a-zA-Z0-9_.]{3,30}$').hasMatch(v?.trim() ?? '')
                    ? null
                    : 'من 3 لـ 30 حرف إنجليزي أو أرقام',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: 'كلمة السر *',
                prefixIcon: const Icon(Icons.lock_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              validator: (v) => (v ?? '').length < 6 ? '6 حروف أو أرقام على الأقل' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              obscureText: !_showPassword,
              decoration: const InputDecoration(labelText: 'تأكيد كلمة السر *', prefixIcon: Icon(Icons.lock_outline_rounded)),
              validator: (v) => v != _password.text ? 'كلمة السر مش زي اللي فوق' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
            const SizedBox(height: 20),
            BusyButton(label: 'تسجيل المحل والبدء', busy: _busy, onPressed: _submit),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => ref.read(sessionProvider.notifier).resetConnection(),
              child: const Text('رجوع'),
            ),
          ],
        ),
      ),
    );
  }
}
