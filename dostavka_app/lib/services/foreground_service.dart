import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class ForegroundServiceManager {
  static bool _isConfigured = false;
  static const String _channelId = 'dostavka_service';

  static Future<void> initialize() async {
    if (_isConfigured) return;
    _isConfigured = true;

    final FlutterLocalNotificationsPlugin flnp = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await flnp.initialize(const InitializationSettings(android: androidInit));

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        flnp.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      'Доставка',
      description: 'Уведомления сервиса доставки',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );
    await androidPlugin?.createNotificationChannel(channel);
    print('✅ Foreground channel created');

    const AndroidNotificationChannel ordersChannel = AndroidNotificationChannel(
      'dostavka_orders',
      'Новые заказы',
      description: 'Уведомления о новых заказах',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );
    await androidPlugin?.createNotificationChannel(ordersChannel);
    print('✅ Orders channel created');

    await FlutterBackgroundService().configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: _channelId,
        foregroundServiceNotificationId: 888,
        initialNotificationTitle: 'Доставка',
        initialNotificationContent: 'Сервис запущен',
        foregroundServiceTypes: [
          AndroidForegroundType.dataSync,
          AndroidForegroundType.location,
        ],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    print('✅ Service configured');
  }

  static Future<void> start(String token, String role, {int? courierId}) async {
    print('🟢 start() called with role=$role, courier=$courierId, token=${token.isNotEmpty}');
    print('🟢 token.length=${token.length}, token empty: ${token.isEmpty}');

    if (role != 'courier') {
      print('⚠️ Not courier (role=$role), skipping foreground service');
      return;
    }

    if (token.isEmpty) {
      print('❌ Token is empty, aborting');
      return;
    }

    if (courierId == null) {
      print('❌ CourierId is null, aborting');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      print('📝 Got SharedPreferences');

      await prefs.setString('ws_token', token);
      await prefs.setString('ws_role', role);
      await prefs.setInt('ws_courier_id', courierId);
      print('✅ Credentials saved. Starting service...');

      final service = FlutterBackgroundService();

      final isRunning = await service.isRunning();
      print('📊 Service isRunning: $isRunning');

      if (isRunning) {
        print('🔄 Service already running, stopping first...');
        service.invoke('stop');
        await Future.delayed(const Duration(milliseconds: 1000));
        print('🛑 Stopped, waiting...');
      }

      print('⏳ Waiting 500ms before start...');
      await Future.delayed(const Duration(milliseconds: 500));
      await service.startService();
      print('🚀 startService() called — done');

      final isRunningAfter = await service.isRunning();
      print('📊 Service isRunning after start: $isRunningAfter');
    } catch (e, stack) {
      print('❌ start() CRASHED: $e');
      print('Stack trace: $stack');
      rethrow;
    }
  }

  static Future<void> stop() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ws_token');
    await prefs.remove('ws_role');
    await prefs.remove('ws_courier_id');
    FlutterBackgroundService().invoke('stop');
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  print('═══════════════════════════════════');
  print('🟢 onStart() CALLED in background');
  print('═══════════════════════════════════');

  service.on('stop').listen((event) {
    print('🔴 onStart() — stop signal');
    service.stopSelf();
  });

  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('ws_token') ?? '';
  final courierId = prefs.getInt('ws_courier_id');

  print('🔑 Token: ${token.isNotEmpty} (${token.length} chars), Courier: $courierId');

  if (token.isEmpty || courierId == null) {
    print('❌ onStart() — no token/courier, bailing');
    return;
  }

  final savedUrl = prefs.getString('server_url') ?? '';
  final baseUrl = savedUrl.isNotEmpty ? savedUrl : 'http://10.0.2.2:8000';
  final wsBase = baseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');

  print('🌐 Server: $baseUrl, WS: $wsBase');

  if (service is AndroidServiceInstance) {
    await service.setForegroundNotificationInfo(
      title: 'Доставка',
      content: 'Сервис работает — ожидание заказов',
    );
    print('✅ Foreground notification set');
  }

  final FlutterLocalNotificationsPlugin flnPlugin = FlutterLocalNotificationsPlugin();
  await flnPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  const NotificationDetails pushDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'dostavka_orders',
      'Новые заказы',
      channelDescription: 'Уведомления о новых заказах',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      ongoing: false,
      autoCancel: true,
    ),
  );

  final Set<dynamic> knownOrderIds = {};
  int _notificationId = 1;

  void recordOrder(dynamic orderId) {
    knownOrderIds.add(orderId);
  }

  bool isNewOrder(dynamic orderId) => !knownOrderIds.contains(orderId);

  Future<void> showOrderPush(String title, String body) async {
    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: title,
        content: body,
      );

      final notifId = _notificationId++;
      try {
        await flnPlugin.show(notifId, title, body, pushDetails);
        print('✅ PUSH SHOWN (#$notifId)');
      } catch (e, stack) {
        print('❌ PUSH FAILED: $e');
        print('Stack: $stack');
      }

      Future.delayed(const Duration(seconds: 15), () async {
        await service.setForegroundNotificationInfo(
          title: 'Доставка',
          content: 'Сервис работает',
        );
      });
    }
  }

  // ======= WebSocket =======
  final wsUrl = '$wsBase/ws/courier/$courierId?token=$token';
  print('🔌 WS connecting: $wsUrl');

  Future<void> connectWs() async {
    try {
      final ws = await WebSocket.connect(wsUrl);
      print('🟢 WS CONNECTED');

      ws.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            final type = msg['event'] as String?;
            final payload =
                (msg['data'] as Map<String, dynamic>?) ?? msg;

            print('📨 WS event: $type');

            if (type == 'new_order' && payload['id'] != null) {
              final orderId = payload['id'];
              if (isNewOrder(orderId)) {
                recordOrder(orderId);
                final orderNumber = payload['order_number'] ?? orderId;
                print('🆕 NEW ORDER #$orderNumber (source: ws)');
                showOrderPush('🛵 Новый заказ!', 'Заказ №$orderNumber');
              }
            }
          } catch (e) {
            print('❌ WS decode error: $e');
          }
        },
        onError: (e) {
          print('🔴 WS error: $e');
          Future.delayed(const Duration(seconds: 5), connectWs);
        },
        onDone: () {
          print('🔴 WS closed — reconnecting in 5s');
          Future.delayed(const Duration(seconds: 5), connectWs);
        },
      );
    } catch (e) {
      print('🔴 WS connect failed: $e — retrying in 5s');
      Future.delayed(const Duration(seconds: 5), connectWs);
    }
  }

  connectWs();

  // ======= Location sender =======
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      await http.post(
        Uri.parse('$baseUrl/api/courier/location'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'latitude': pos.latitude,
          'longitude': pos.longitude,
        }),
      );
      print('📍 Location sent OK');
    } catch (e) {
      print('📍 Location err: $e');
    }
  });

  // ======= Poll fallback =======
  Timer.periodic(const Duration(seconds: 15), (_) async {
    try {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/courier/orders/available'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (resp.statusCode == 200) {
        final List<dynamic> orders = json.decode(resp.body);
        final knownBefore = knownOrderIds.length;

        final List<Map<String, dynamic>> newOrders = [];
        for (final o in orders) {
          final order = o as Map<String, dynamic>;
          if (isNewOrder(order['id'])) {
            recordOrder(order['id']);
            newOrders.add(order);
          }
        }

        if (newOrders.isNotEmpty) {
          if (newOrders.length == 1) {
            final order = newOrders.first;
            final orderNumber = order['order_number'] ?? order['id'];
            print('🆕 NEW ORDER #$orderNumber (source: poll)');
            await showOrderPush('🛵 Новый заказ!', 'Заказ №$orderNumber');
          } else {
            print('🆕 ${newOrders.length} NEW ORDERS (source: poll)');
            await showOrderPush('🛵 Новые заказы!', 'Поступило ${newOrders.length} новых заказов');
          }
        }

        print('📡 Poll: ${orders.length} orders, known: $knownBefore → detected: ${newOrders.length} new');
      } else {
        print('📡 Poll: HTTP ${resp.statusCode}');
      }
    } catch (e) {
      print('📡 Poll err: $e');
    }
  });
}