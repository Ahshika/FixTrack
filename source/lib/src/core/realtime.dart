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
  var connectedBefore = false;

  void connect() {
    if (disposed) return;
    channel = WebSocketChannel.connect(api.webSocketUri());
    // أول ما الاتصال يرجع بعد ما قطع (السيرفر رجع، أو الواي فاي رجع): كل الشاشات تتحدّث
    channel!.ready.then((_) {
      if (connectedBefore && !disposed) controller.add(RealtimeEvent('*'));
      connectedBefore = true;
    }, onError: (_) {});
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
void refreshOn(Ref ref, String topic) => refreshOnTopics(ref, {topic});

/// بيستنى ربع ثانية بعد آخر حدث قبل ما يعيد التحميل: لو أجهزة كتير بتغيّر حاجات في نفس اللحظة،
/// الشاشة بتتحدّث مرة واحدة بدل عشر مرات.
void refreshOnTopics(Ref ref, Set<String> topics) {
  Timer? pending;
  ref.onDispose(() => pending?.cancel());
  ref.listen(realtimeProvider, (_, next) {
    final t = next.value?.topic;
    if (t == null || (t != '*' && !topics.contains(t))) return;
    pending?.cancel();
    pending = Timer(const Duration(milliseconds: 250), ref.invalidateSelf);
  });
}

/// كل حدث object جديد (من غير ==) عشان Riverpod ما يتجاهلش حدثين ورا بعض لنفس الموضوع.
class RealtimeEvent {
  RealtimeEvent(this.topic);
  final String topic;
}
