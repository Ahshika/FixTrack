import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/core/app_config.dart';
import 'src/core/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await AppConfig.load();
  runApp(ProviderScope(
    // الأخطاء بنعرضها للمستخدم بنفسنا، فمش عايزين Riverpod يعيد المحاولة لوحده
    retry: (_, _) => null,
    overrides: [appConfigProvider.overrideWithValue(config)],
    child: const FixTrackApp(),
  ));
}
