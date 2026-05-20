import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

class SignalingClient {
  WebSocketChannel? _channel;

  void connect(String url, Function(Map<String, dynamic>) onMessage) {
    _channel = WebSocketChannel.connect(Uri.parse(url));

    _channel!.stream.listen(
      (data) {
        final decoded = jsonDecode(data);
        onMessage(decoded);
      },
      onError: (error) {
        print("WS Error: $error");
      },
      onDone: () {
        print("WS Connection Closed");
      },
    );
  }

  void send(String type, String from, String to, String data) {
    final payload = jsonEncode({
      "type": type,
      "from": from,
      "to": to,
      "data": data,
    });
    _channel!.sink.add(payload);
  }

  void close() {
    _channel!.sink.close(status.goingAway);
  }
}
