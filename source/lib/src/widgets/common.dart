import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/theme.dart';

/// اللوجو المؤقت لحد ما نعمل اللوجو النهائي: مفتاح صيانة جوه مربع بزوايا مدورة.
class FixTrackLogo extends StatelessWidget {
  const FixTrackLogo({super.key, this.size = 56, this.showName = true});

  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [brandBlue, Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.phone_android_rounded, color: Colors.white, size: size * 0.62),
          Positioned(
            bottom: size * 0.12,
            right: size * 0.12,
            child: Container(
              padding: EdgeInsets.all(size * 0.04),
              decoration: const BoxDecoration(color: brandOrange, shape: BoxShape.circle),
              child: Icon(Icons.build_rounded, color: Colors.white, size: size * 0.2),
            ),
          ),
        ],
      ),
    );
    if (!showName) return mark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(height: 12),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: 'Fix', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
              const TextSpan(text: 'Track', style: TextStyle(color: brandOrange)),
            ]),
            style: Theme.of(context).textTheme.headlineSmall?.bold,
          ),
        ),
      ],
    );
  }
}

/// كارت في نص الشاشة للشاشات البسيطة زي الدخول والإعداد.
class CenteredPanel extends StatelessWidget {
  const CenteredPanel({super.key, required this.child, this.maxWidth = 460});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: scheme.onErrorContainer))),
        ],
      ),
    );
  }
}

/// زرار بيعرض loading وهو بيستنى العملية تخلص.
class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.busy, required this.onPressed, this.icon});

  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
        : Text(label);
    if (icon != null && !busy) {
      return FilledButton.icon(onPressed: onPressed, icon: Icon(icon), label: child);
    }
    return FilledButton(onPressed: busy ? null : onPressed, child: child);
  }
}

String errorText(Object e) => e is ApiException ? e.message : 'حصل خطأ غير متوقع: $e';

void showMessage(BuildContext context, String message, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? scheme.error : null,
    ));
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.bold),
      );
}
