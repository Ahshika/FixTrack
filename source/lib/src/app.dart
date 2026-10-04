import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/session.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';
import 'features/setup/connect_screen.dart';
import 'features/setup/create_shop_screen.dart';
import 'features/setup/status_screens.dart';
import 'features/setup/welcome_screen.dart';

class FixTrackApp extends ConsumerWidget {
  const FixTrackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'FixTrack',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      home: const _SessionGate(),
    );
  }
}

/// بيختار الشاشة حسب حالة الجهاز: أول تشغيل، أو محتاج سيرفر، أو تسجيل دخول، أو جاهز.
class _SessionGate extends ConsumerWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final value = session.value;
    if (value == null || session.isLoading) return const SplashScreen();

    return switch (value.status) {
      SessionStatus.chooseMode => const WelcomeScreen(),
      SessionStatus.needsServer => const ConnectScreen(),
      SessionStatus.serverFailed => ServerFailedScreen(message: value.error ?? ''),
      SessionStatus.unreachable => UnreachableScreen(message: value.error ?? ''),
      SessionStatus.needsSetup => const CreateShopScreen(),
      SessionStatus.needsLogin => const LoginScreen(),
      SessionStatus.ready => const HomeShell(),
    };
  }
}
