// بيعمل مفتاحين لتوقيع أكواد التفعيل (مرة واحدة بس).
// المفتاح السري بيتحفظ في فولدر signing (خد منه نسخة احتياطية!)، والعام بيتحط في البرنامج.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

Future<void> main(List<String> args) async {
  final out = File(args.isNotEmpty ? args.first : '../signing/license-private.key');
  if (out.existsSync()) {
    stderr.writeln('المفتاح موجود بالفعل: ${out.path}. مش هعمل واحد جديد عشان الأكواد القديمة تفضل شغالة.');
    exit(1);
  }
  final pair = await Ed25519().newKeyPair();
  final seed = await pair.extractPrivateKeyBytes();
  final pub = await pair.extractPublicKey();
  out.writeAsStringSync(base64.encode(seed));
  stdout.writeln(base64.encode(pub.bytes));
}
