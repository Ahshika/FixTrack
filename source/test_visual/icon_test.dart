// بيرسم أيقونة البرنامج بجودة عالية (1024×1024) عشان تتعمل منها كل مقاسات Windows و Android.
// التشغيل: flutter test test_visual/icon_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _blue = Color(0xFF1B4FD8);
const _blueLight = Color(0xFF3B82F6);
const _orange = Color(0xFFFF7A1A);

/// العلامة: موبايل أبيض جوه مربع أزرق بزوايا مدورة، وعليه دايرة برتقاني فيها مفتاح صيانة.
class _Mark extends StatelessWidget {
  const _Mark({required this.withBackground});
  final bool withBackground;

  @override
  Widget build(BuildContext context) {
    const size = 1024.0;
    final content = Stack(alignment: Alignment.center, children: [
      const Icon(Icons.phone_android_rounded, color: Colors.white, size: size * 0.62),
      Positioned(
        bottom: size * 0.15,
        right: size * 0.17,
        child: Container(
          width: size * 0.30,
          height: size * 0.30,
          decoration: BoxDecoration(color: _orange, shape: BoxShape.circle, border: Border.all(color: _blue, width: size * 0.025)),
          child: const Icon(Icons.build_rounded, color: Colors.white, size: size * 0.17),
        ),
      ),
    ]);
    if (!withBackground) {
      // الأيقونة المتكيفة في أندرويد: الشكل في النص في مساحة الأمان (حوالي 66%)
      return SizedBox(width: size, height: size, child: Transform.scale(scale: 0.66, child: content));
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_blue, _blueLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: content,
    );
  }
}

Future<void> _render(WidgetTester t, Widget w, String out) async {
  t.view.physicalSize = const Size(1024, 1024);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: RepaintBoundary(child: w)),
  ));
  await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile(out));
}

void main() {
  setUpAll(() async {
    final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter';
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
    await loader.load();
  });

  testWidgets('app icon', (t) => _render(t, const _Mark(withBackground: true), '../assets/icon/app_icon.png'));
  testWidgets('adaptive foreground', (t) => _render(t, const _Mark(withBackground: false), '../assets/icon/app_icon_foreground.png'));
}
