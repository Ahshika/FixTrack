import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_config.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = ref.read(sessionProvider).value?.error;
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'اكتب اسم المستخدم وكلمة السر');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).login(_username.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final info = ref.watch(sessionProvider).value?.info;
    final isClient = ref.read(appConfigProvider).mode == AppMode.client;

    return CenteredPanel(
      maxWidth: 420,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FixTrackLogo(size: 64),
            const SizedBox(height: 20),
            if (info?.shopName != null) ...[
              Text(info!.shopName!, textAlign: TextAlign.center, style: text.titleLarge?.bold),
              if (info.branchName != null)
                Text(info.branchName!, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 24),
            ],
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: _username,
                autofillHints: const [AutofillHints.username],
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'اسم المستخدم', prefixIcon: Icon(Icons.person_rounded)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: !_showPassword,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'كلمة السر',
                prefixIcon: const Icon(Icons.lock_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
            const SizedBox(height: 20),
            BusyButton(label: 'دخول', busy: _busy, onPressed: _submit),
            if (isClient) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _busy ? null : () => ref.read(sessionProvider.notifier).resetConnection(),
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('تغيير السيرفر'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
