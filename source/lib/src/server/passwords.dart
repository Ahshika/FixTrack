import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _iterations = 60000;
final _random = Random.secure();

List<int> randomBytes(int length) => List<int>.generate(length, (_) => _random.nextInt(256));

String randomToken() => base64Url.encode(randomBytes(32)).replaceAll('=', '');

String sha256Hex(String input) => sha256.convert(utf8.encode(input)).toString();

/// بيرجع النص بالشكل ده: `pbkdf2$iterations$salt$hash`
String hashPassword(String password) {
  final salt = randomBytes(16);
  final hash = _pbkdf2(utf8.encode(password), salt, _iterations);
  return 'pbkdf2\$$_iterations\$${base64.encode(salt)}\$${base64.encode(hash)}';
}

bool verifyPassword(String password, String stored) {
  final parts = stored.split(r'$');
  if (parts.length != 4 || parts[0] != 'pbkdf2') return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null) return false;
  final expected = base64.decode(parts[3]);
  final actual = _pbkdf2(utf8.encode(password), base64.decode(parts[2]), iterations);
  return _constantTimeEquals(expected, actual);
}

/// PBKDF2-HMAC-SHA256 بطول 32 بايت (بلوك واحد).
Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, password);
  var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final out = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return out;
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
