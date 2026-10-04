import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';

/// حفظ ملف: على الكمبيوتر بيسأل تحفظه فين، وعلى الموبايل بيفتح المشاركة (واتساب، Drive، ...).
/// بيرجع مكان الملف لو اتحفظ على الكمبيوتر.
Future<String?> saveOrShareFile(Uint8List bytes, String fileName, String mimeType) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, name: fileName, mimeType: mimeType)], fileNameOverrides: [fileName]));
    return null;
  }
  final ext = fileName.split('.').last;
  final location = await getSaveLocation(
    suggestedName: fileName,
    acceptedTypeGroups: [XTypeGroup(label: ext.toUpperCase(), extensions: [ext])],
  );
  if (location == null) return null;
  await File(location.path).writeAsBytes(bytes);
  return location.path;
}
