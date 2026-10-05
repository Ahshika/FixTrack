import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'diagnostics.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status});
  final String message;
  final int? status;
  bool get isUnauthorized => status == 401;
  bool get isNetwork => status == null;
  @override
  String toString() => message;
}

const networkErrorMessage =
    'مش قادر أوصل لسيرفر المحل. اتأكد إن كمبيوتر المحل شغال والبرنامج مفتوح عليه، وإنك على نفس شبكة الواي فاي.';

/// بيكلم سيرفر المحل. كل الردود JSON، ورسايل الخطأ جاية من السيرفر بالعربي.
class ApiClient {
  ApiClient(this.baseUrl, {this.token, this.onUnauthorized});

  final String baseUrl;
  String? token;
  void Function()? onUnauthorized;
  final _http = http.Client();

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) => send('GET', path, query: query);
  Future<Map<String, dynamic>> post(String path, [Object? body]) => send('POST', path, body: body);
  Future<Map<String, dynamic>> patch(String path, [Object? body]) => send('PATCH', path, body: body);
  Future<Map<String, dynamic>> put(String path, [Object? body]) => send('PUT', path, body: body);
  Future<Map<String, dynamic>> delete(String path) => send('DELETE', path);

  Future<Map<String, dynamic>> send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final req = http.Request(method, uri)
      ..headers['accept'] = 'application/json'
      ..headers['content-type'] = 'application/json; charset=utf-8';
    if (token != null) req.headers['authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);

    FreezeWatchdog.action('$method $path');
    final sw = Stopwatch()..start();
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    } on SocketException catch (e) {
      DiagLog.app?.write('NET', '$method $path: مش قادر يوصل للسيرفر ($e)');
      throw ApiException(networkErrorMessage);
    } on TimeoutException {
      DiagLog.app?.write('NET', '$method $path: السيرفر ما ردّش في ${timeout.inSeconds} ثانية');
      throw ApiException(networkErrorMessage);
    } on http.ClientException catch (e) {
      DiagLog.app?.write('NET', '$method $path: $e');
      throw ApiException(networkErrorMessage);
    }
    if (sw.elapsedMilliseconds > 3000) DiagLog.app?.write('SLOW', '$method $path خد ${sw.elapsedMilliseconds} مللي ثانية');

    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      data = decoded is Map<String, dynamic> ? decoded : {'data': decoded};
    } catch (_) {
      data = {};
    }

    if (res.statusCode >= 400) {
      if (res.statusCode == 401 && token != null) onUnauthorized?.call();
      throw ApiException(data['error'] as String? ?? 'حصل خطأ غير متوقع (${res.statusCode})', status: res.statusCode);
    }
    return data;
  }

  Uri webSocketUri() {
    final base = Uri.parse(baseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/ws',
      queryParameters: {'token': ?token},
    );
  }

  void close() => _http.close();
}

/// يحوّل اللي المستخدم كتبه (IP أو IP:port أو URL كامل) لعنوان سيرفر.
String normalizeServerUrl(String input) {
  var v = input.trim();
  if (v.isEmpty) return v;
  if (!v.contains('://')) v = 'http://$v';
  final uri = Uri.parse(v);
  final port = uri.hasPort ? uri.port : 8743;
  return '${uri.scheme}://${uri.host}:$port';
}
