import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('cost of shrinking a 12MP phone photo in Dart', () {
    final big = img.Image(width: 4000, height: 3000);
    for (var y = 0; y < 3000; y += 7) {
      for (var x = 0; x < 4000; x += 5) {
        big.setPixelRgb(x, y, x % 255, y % 255, (x + y) % 255);
      }
    }
    final jpg = img.encodeJpg(big, quality: 90);
    final sw = Stopwatch()..start();
    final decoded = img.decodeImage(jpg)!;
    final resized = img.copyResize(decoded, width: 1400);
    img.encodeJpg(resized, quality: 75);
    // ignore: avoid_print
    print('12MP photo: ${(jpg.length / 1024 / 1024).toStringAsFixed(1)} MB, decode+resize+encode = ${sw.elapsedMilliseconds} ms');
  });
}
