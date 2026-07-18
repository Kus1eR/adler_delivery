import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:dostavka_app/services/api_service.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  final String _token;
  final String _role;
  final int? _courierId;
  bool _shouldReconnect = true;
  Function(Map<String, dynamic>)? onMessage;

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  WebSocketService({
    required String token,
    required String role,
    int? courierId,
  }) : _token = token,
       _role = role,
       _courierId = courierId;

  void connect() {
    _shouldReconnect = true;
    final baseUrl = ApiService.baseUrl.replaceFirst('http', 'ws');
    String url;

    if (_role == 'admin') {
      url = '$baseUrl/ws/admin';
    } else {
      url = '$baseUrl/ws/courier/$_courierId';
    }

    url += '?token=$_token';

    print('🟢 WS CONNECTING: $url');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
    } catch (e) {
      print('🔴 WS CONNECT ERROR: $e');
      return;
    }

    _channel!.stream.listen(
      (data) {
        try {
          print('🟢 WS MESSAGE: $data');
          final message = jsonDecode(data as String) as Map<String, dynamic>;
          final type = message['event'] as String?;
          final payload = (message['data'] as Map<String, dynamic>?) ?? message;
          if (type != null) {
            payload['type'] = type;
          }
          _messageController.add(payload);
          onMessage?.call(payload);
        } catch (e) {
          print('🔴 WS DECODE ERROR: $e');
        }
      },
      onError: (error) {
        print('🔴 WS ERROR: $error');
        if (_shouldReconnect) {
          Future.delayed(const Duration(seconds: 5), connect);
        }
      },
      onDone: () {
        print('🔴 WS DISCONNECTED');
        if (_shouldReconnect) {
          Future.delayed(const Duration(seconds: 3), connect);
        }
      },
    );
    print('🟢 WS CONNECTED');
  }

  void disconnect() {
    _shouldReconnect = false;
    _channel?.sink.close();
    _messageController.close();
  }
}