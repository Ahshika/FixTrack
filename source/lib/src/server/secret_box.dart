import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'passwords.dart';

/// تشفير البيانات الحساسة (زي رمز فتح الشاشة) قبل تخزينها في قاعدة البيانات.
///
/// التشفير: HMAC-SHA256 في وضع العدّاد (CTR) مع nonce عشوائي، وبعده MAC للتأكد إن البيانات ما اتلعبش فيها.
/// المفتاح متخزن في إعدادات السيرفر، فده بيحمي من إن حد يفتح ملف قاعدة البيانات أو نسخة احتياطية ويقرأ الرموز على طول.
class SecretBox {
  SecretBox(List<int> key)
      : _encKey = Hmac(sha256, key).convert(utf8.encode('fixtrack-enc')).bytes,
        _macKey = Hmac(sha256, key).convert(utf8.encode('fixtrack-mac')).bytes;

  final List<int> _encKey;
  final List<int> _macKey;

  String seal(String plain) {
    final nonce = randomBytes(16);
    final data = utf8.encode(plain);
    final cipher = _xor(data, nonce);
    final mac = Hmac(sha256, _macKey).convert([...nonce, ...cipher]).bytes.sublist(0, 16);
    return base64.encode([...nonce, ...cipher, ...mac]);
  }

  String? open(String sealed) {
    try {
      final all = base64.decode(sealed);
      if (all.length < 32) return null;
      final nonce = all.sublist(0, 16);
      final cipher = all.sublist(16, all.length - 16);
      final mac = all.sublist(all.length - 16);
      final expected = Hmac(sha256, _macKey).convert([...nonce, ...cipher]).bytes.sublist(0, 16);
      var diff = 0;
      for (var i = 0; i < 16; i++) {
        diff |= mac[i] ^ expected[i];
      }
      if (diff != 0) return null;
      return utf8.decode(_xor(cipher, nonce));
    } catch (_) {
      return null;
    }
  }

  Uint8List _xor(List<int> data, List<int> nonce) {
    final out = Uint8List(data.length);
    final hmac = Hmac(sha256, _encKey);
    for (var block = 0; block * 32 < data.length; block++) {
      final ks = hmac.convert([...nonce, block >> 24 & 255, block >> 16 & 255, block >> 8 & 255, block & 255]).bytes;
      for (var i = 0; i < 32 && block * 32 + i < data.length; i++) {
        out[block * 32 + i] = data[block * 32 + i] ^ ks[i];
      }
    }
    return out;
  }
}
