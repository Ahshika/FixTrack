import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_config.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// أول شاشة بعد التثبيت: الجهاز ده هيبقى سيرفر المحل ولا هيتصل بسيرفر موجود؟
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final controller = ref.read(sessionProvider.notifier);

    return CenteredPanel(
      maxWidth: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FixTrackLogo(size: 72),
          const SizedBox(height: 8),
          Text('نظام إدارة محلات صيانة الموبايلات', textAlign: TextAlign.center, style: text.bodyLarge),
          const SizedBox(height: 32),
          Text('الجهاز ده هيشتغل إزاي؟', style: text.titleLarge?.bold),
          const SizedBox(height: 12),
          if (AppConfig.canHostServer) ...[
            _ModeCard(
              icon: Icons.dns_rounded,
              title: 'الجهاز ده هو السيرفر الرئيسي للمحل',
              subtitle: 'كل بيانات المحل هتتخزن على الكمبيوتر ده، والموبايلات والأجهزة التانية هتتصل بيه.\n'
                  'اختار ده لو ده أول جهاز بتسطب عليه البرنامج في الفرع.',
              recommended: true,
              onTap: () => controller.chooseMode(AppMode.server),
            ),
            const SizedBox(height: 12),
          ],
          _ModeCard(
            icon: Icons.wifi_rounded,
            title: 'الاتصال بسيرفر المحل',
            subtitle: 'فيه كمبيوتر في المحل عليه البرنامج بالفعل، وعايز الجهاز ده يتصل بيه على نفس الواي فاي.',
            onTap: () => controller.chooseMode(AppMode.client),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.recommended = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.primaryContainer,
                child: Icon(icon, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(title, style: text.titleMedium?.bold),
                        if (recommended)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: brandOrange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('أول جهاز', style: text.labelSmall?.bold.copyWith(color: brandOrange)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
