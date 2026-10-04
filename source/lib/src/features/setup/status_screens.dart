import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FixTrackLogo(size: 72),
            SizedBox(height: 24),
            SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          ],
        ),
      ),
    );
  }
}

class _ProblemScreen extends ConsumerWidget {
  const _ProblemScreen({
    required this.icon,
    required this.title,
    required this.message,
    required this.secondaryLabel,
  });

  final IconData icon;
  final String title;
  final String message;
  final String secondaryLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return CenteredPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 64, color: scheme.error),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: text.titleLarge?.bold),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: text.bodyLarge),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => ref.read(sessionProvider.notifier).retry(),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('حاول تاني'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => ref.read(sessionProvider.notifier).resetConnection(),
            child: Text(secondaryLabel),
          ),
        ],
      ),
    );
  }
}

class ServerFailedScreen extends StatelessWidget {
  const ServerFailedScreen({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => _ProblemScreen(
        icon: Icons.dns_rounded,
        title: 'السيرفر ما اشتغلش',
        message: message,
        secondaryLabel: 'تغيير طريقة تشغيل الجهاز',
      );
}

class UnreachableScreen extends StatelessWidget {
  const UnreachableScreen({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => _ProblemScreen(
        icon: Icons.wifi_off_rounded,
        title: 'مفيش اتصال بالسيرفر',
        message: message,
        secondaryLabel: 'اختار سيرفر تاني',
      );
}
