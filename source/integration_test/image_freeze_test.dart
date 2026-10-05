// بيشغّل البرنامج الحقيقي على ويندوز (سيرفر حقيقي في Isolate على فولدر مؤقت) ويرفع صورة موبايل كبيرة ويعرضها،
// وبيقيس أطول وقت الشاشة وقفت فيه. عمره ما بيلمس بيانات حقيقية.
// التشغيل:  flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/image_freeze_test.dart -d windows
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:fixtrack/src/core/api_client.dart';
import 'package:fixtrack/src/core/app_config.dart';
import 'package:fixtrack/src/core/models.dart';
import 'package:fixtrack/src/core/session.dart';
import 'package:fixtrack/src/core/theme.dart';
import 'package:fixtrack/src/features/phones/phones_screen.dart';
import 'package:fixtrack/src/server/server_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Session extends SessionController {
  _Session(this.api, this.info);
  final ApiClient api;
  final ServerInfo info;

  @override
  Future<Session> build() async => Session(SessionStatus.ready,
      api: api, info: info, user: AppUser(id: 'u', name: 'أحمد', username: 'owner', role: Role.owner, active: true));
}

class _Picker extends FileSelectorPlatform {
  _Picker(this.path);
  final String path;
  @override
  Future<XFile?> openFile({List<XTypeGroup>? acceptedTypeGroups, String? initialDirectory, String? confirmButtonText}) async => XFile(path);
}

/// صورة موبايل كبيرة (12 ميجابكسل) فيها تفاصيل كتير زي الصور الحقيقية.
Uint8List _bigPhoto() {
  final im = img.Image(width: 4000, height: 3000);
  for (final p in im) {
    p.setRgb((p.x * 7 + p.y * 3) % 256, (p.x * p.y) % 256, (p.y * 11) % 256);
  }
  return img.encodeJpg(im, quality: 92);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('رفع صورة كبيرة وعرضها ما بيوقفوش الشاشة', (tester) async {
    final dir = await Directory.systemTemp.createTemp('fixtrack_img');
    final port = await ServerHost.start(dir.path, port: 18772);
    final api = ApiClient('http://127.0.0.1:$port');
    api.token = (await api.post('/api/setup', {'shopName': 'محل تجربة', 'ownerName': 'أحمد', 'username': 'owner', 'password': 'owner123'}))['token'] as String;
    final photo = File('${dir.path}/photo.jpg')..writeAsBytesSync(await Isolate.run(_bigPhoto));
    debugPrint('PHOTO ${photo.lengthSync() ~/ 1024} KB');
    FileSelectorPlatform.instance = _Picker(photo.path);

    SharedPreferences.setMockInitialValues({});
    final config = await AppConfig.load();
    final info = ServerInfo.fromJson(await api.get('/api/info'));
    String? fileId;
    Object? error;
    await tester.pumpWidget(ProviderScope(
      overrides: [appConfigProvider.overrideWithValue(config), sessionProvider.overrideWith(() => _Session(api, info))],
      child: MaterialApp(
        locale: const Locale('ar', 'EG'),
        supportedLocales: const [Locale('ar', 'EG')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Brightness.light),
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: ref.watch(sessionProvider).hasValue
                  ? FilledButton(
                      onPressed: () => captureAndUploadPhoto(context, ref, 'id').then((id) => fileId = id, onError: (Object e) {
                        error = e;
                        return null;
                      }),
                      child: const Text('صورة'),
                    )
                  : const SizedBox(),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));

    final clock = Stopwatch()..start();
    var last = 0, worst = 0;
    final beat = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final now = clock.elapsedMilliseconds;
      if (now - last > worst) worst = now - last;
      last = now;
    });

    await tester.tap(find.text('صورة'));
    while (fileId == null && error == null && clock.elapsed < const Duration(seconds: 60)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    debugPrint('UPLOAD ${clock.elapsedMilliseconds} ms, worst UI stall $worst ms, error=$error');
    expect(error, isNull);
    expect(fileId, isNotNull);
    expect(worst, lessThan(1500));

    beat.cancel();
    final serverLog = File('${dir.path}/logs/server.log').readAsStringSync();
    expect(serverLog, isNot(contains('hijacked')));
    api.close();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
