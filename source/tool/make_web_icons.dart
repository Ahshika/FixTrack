// أيقونات صفحة التتبع من أيقونة البرنامج.
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final src = img.decodePng(File('assets/icon/app_icon.png').readAsBytesSync())!;
  for (final s in [32, 180, 192, 512]) {
    File('firebase/public/icon-$s.png').writeAsBytesSync(img.encodePng(img.copyResize(src, width: s, height: s, interpolation: img.Interpolation.average)));
  }
}
