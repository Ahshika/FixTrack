// سيرفر FixTrack لاختبار الضغط: فولدر مؤقت، من غير مزامنة سحابية، عمره ما بيلمس بيانات حقيقية.
import 'dart:io';
import 'package:fixtrack/src/server/api_server.dart';

Future<void> main(List<String> args) async {
  final dir = args.isNotEmpty ? args[0] : (await Directory.systemTemp.createTemp('fixtrack_load')).path;
  final port = args.length > 1 ? int.parse(args[1]) : 18790;
  final server = FixTrackServer(dataDir: dir, requestedPort: port, cloudSync: false);
  await server.start();
  stdout.writeln('READY port=${server.port} dir=$dir');
}
