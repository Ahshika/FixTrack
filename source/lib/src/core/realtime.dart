import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'session.dart';

/// اتصال لحظي بالسيرفر: أول ما أي جهاز يغيّر حاجة، كل الأجهزة التانية بتعرف وتحدّث الشاشة.
///
/// بيطلع اسم الحاجة اللي اتغيرت (مثلاً 'users')، والشاشات بتسمع على اللي يهمها.
final realtimeProvider = StreamProvider<RealtimeEvent>((ref) {
  final session = ref.watch(sessionProvider).value;
  final api = session?.api;
  if (session?.status != SessionStatus.ready || api == null) return const Stream.empty();

  final controller = StreamController<RealtimeEvent>();
  WebSocketChannel? channel;
  Timer? reconnect;
  var disposed = false;

  void connect() {
    if (disposed) return;
    channel = WebSocketChannel.connect(api.webSocketUri());
    channel!.stream.listen(
      (msg) {
        try {
          final data = jsonDecode(msg as String) as Map<String, dynamic>;
          if (data['type'] == 'changed') controller.add(RealtimeEvent(data['topic'] as String));
        } catch (_) {}
      },
      onDone: () => reconnect = Timer(const Duration(seconds: 3), connect),
      onError: (_) {},
      cancelOnError: false,
    );
  }

  connect();
  ref.onDispose(() {
    disposed = true;
    reconnect?.cancel();
    channel?.sink.close();
    controller.close();
  });
  return controller.stream;
});

/// بيعيد تحميل provider معين لما موضوع معين يتغير على السيرفر.
void refreshOn(Ref ref, String topic) {
  ref.listen(realtimeProvider, (_, next) {
    if (next.value?.topic == topic) ref.invalidateSelf();
  });
}

/// كل حدث object جديد (من غير ==) عشان Riverpod ما يتجاهلش حدثين ورا بعض لنفس الموضوع.
class RealtimeEvent {
  RealtimeEvent(this.topic);
  final String topic;
}
