import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:dostavka_app/services/api_service.dart';

void print(Object? message) {
  if (!const bool.fromEnvironment('dart.vm.product')) {
    developer.log('$message', name: 'websocket');
  }
}

class WebSocketService {
  WebSocketChannel? _channel;
  final String _token;
  bool _shouldReconnect = true;
  bool _connected = false;
  Timer? _reconnectTimer;
  Function(Map<String, dynamic>)? onMessage;
  void Function(bool connected)? onConnectionChanged;

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  WebSocketService({required this._token});

  void connect() {
    _shouldReconnect = true;
    _reconnectTimer?.cancel();
    final baseUrl = ApiService.baseUrl.replaceFirst('http', 'ws');
    final wsUrl = Uri.parse('$baseUrl/ws/admin');

    print('🟢 WS CONNECTING: $wsUrl');

    try {
      final channel = IOWebSocketChannel.connect(wsUrl, protocols: [_token]);
      _channel = channel;
      channel.ready.then((_) => _setConnected(true)).catchError((Object error) {
        print('🔴 WS READY ERROR: $error');
        _scheduleReconnect();
      });
    } catch (e) {
      print('🔴 WS CONNECT ERROR: $e');
      _scheduleReconnect();
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
        _setConnected(false);
        _scheduleReconnect();
      },
      onDone: () {
        print('🔴 WS DISCONNECTED');
        _setConnected(false);
        _scheduleReconnect();
      },
    );
    print('🟢 WS CONNECTED');
  }

  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _setConnected(false);
    _channel?.sink.close();
    _messageController.close();
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect || _reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer(const Duration(seconds: 5), connect);
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    onConnectionChanged?.call(value);
  }
}
