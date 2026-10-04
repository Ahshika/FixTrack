import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/messages.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../tickets/providers.dart';

/// بيفتح واتساب على رقم العميل والرسالة مكتوبة جاهزة.
Future<bool> openWhatsApp(String internationalNumber, String text) async {
  final uri = Uri.parse('https://wa.me/$internationalNumber?text=${Uri.encodeComponent(text)}');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// شاشة إرسال رسالة للعميل: الرسالة جاية من القالب وتقدر تعدّلها قبل ما تبعت.
Future<void> showMessageDialog(BuildContext context, String ticketId, MessageEvent event) =>
    showDialog<void>(context: context, builder: (_) => _MessageDialog(ticketId: ticketId, initialEvent: event));

class _MessageDialog extends ConsumerStatefulWidget {
  const _MessageDialog({required this.ticketId, required this.initialEvent});
  final String ticketId;
  final MessageEvent initialEvent;

  @override
  ConsumerState<_MessageDialog> createState() => _MessageDialogState();
}

class _MessageDialogState extends ConsumerState<_MessageDialog> {
  late MessageEvent _event = widget.initialEvent;
  final _body = TextEditingController();
  String? _whatsapp;
  String? _phone;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref
          .read(sessionProvider)
          .value!
          .api!
          .get('/api/tickets/${widget.ticketId}/message', query: {'event': _event.name});
      _body.text = res['body'] as String;
      _whatsapp = res['whatsapp'] as String;
      _phone = res['phone'] as String;
    } catch (e) {
      _error = errorText(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send(String channel) async {
    if (_body.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (channel == 'whatsapp') {
        final ok = await openWhatsApp(_whatsapp!, _body.text.trim());
        if (!ok) throw Exception('مش قادر أفتح واتساب على الجهاز ده');
      }
      await ref.read(sessionProvider).value!.api!.post('/api/tickets/${widget.ticketId}/messages', {
        'channel': channel,
        'event': _event.name,
        'body': _body.text.trim(),
      });
      ref.invalidate(ticketDetailProvider(widget.ticketId));
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(
        context,
        channel == 'sms' ? 'الرسالة اتحطت في طابور الـ SMS، وموبايل المحل هيبعتها' : 'اتفتح واتساب، دوس إرسال هناك',
      );
    } catch (e) {
      if (mounted) setState(() => _error = e is Exception ? e.toString().replaceFirst('Exception: ', '') : errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('رسالة للعميل'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<MessageEvent>(
              initialValue: _event,
              decoration: const InputDecoration(labelText: 'نوع الرسالة'),
              items: [for (final e in MessageEvent.values) DropdownMenuItem(value: e, child: Text(e.label))],
              onChanged: (e) {
                if (e == null) return;
                setState(() => _event = e);
                _load();
              },
            ),
            const SizedBox(height: 12),
            if (_loading)
              const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
            else
              TextField(
                controller: _body,
                minLines: 6,
                maxLines: 12,
                decoration: InputDecoration(
                  labelText: 'نص الرسالة',
                  helperText: _phone == null ? null : 'هتتبعت على: $_phone',
                ),
              ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
            const SizedBox(height: 8),
            Text(
              'SMS بيتبعت أوتوماتيك من موبايل المحل اللي متفعّل عليه "بوابة SMS" في الإعدادات.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        OutlinedButton.icon(
          onPressed: _busy || _loading ? null : () => _send('sms'),
          icon: const Icon(Icons.sms_rounded),
          label: const Text('SMS'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
          onPressed: _busy || _loading || _whatsapp == null ? null : () => _send('whatsapp'),
          icon: const Icon(Icons.chat_rounded),
          label: Text('واتساب', style: const TextStyle().semiBold),
        ),
      ],
    );
  }
}

/// بعد حدث معين (زي "الجهاز جاهز")، لو قاعدة الحدث واتساب بيظهر اقتراح للإرسال.
void suggestMessage(BuildContext context, WidgetRef ref, String ticketId, MessageEvent event, MessageRule rule) {
  if (rule == MessageRule.whatsapp) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text('ابعت للعميل رسالة "${event.label}" على واتساب؟'),
      action: SnackBarAction(label: 'ابعت', onPressed: () => showMessageDialog(context, ticketId, event)),
    ));
  } else if (rule == MessageRule.sms) {
    showMessage(context, 'اتحطت رسالة "${event.label}" في طابور الـ SMS');
  }
}
