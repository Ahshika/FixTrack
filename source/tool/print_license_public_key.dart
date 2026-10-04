// بيطبع المفتاح العام من المفتاح السري (عشان يتحط في البرنامج).
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

Future<void> main(List<String> args) async {
  final seed = base64.decode(File(args.isNotEmpty ? args.first : '../signing/license-private.key').readAsStringSync().trim());
  final pair = await Ed25519().newKeyPairFromSeed(seed);
  stdout.writeln(base64.encode((await pair.extractPublicKey()).bytes));
}
