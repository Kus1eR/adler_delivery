import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'offline_queue.dart';
import '../utils/courier_event.dart';

const bool _serviceLogsEnabled = bool.fromEnvironment(
  'DOSTAVKA_SERVICE_LOGS',
  defaultValue: !bool.fromEnvironment('dart.vm.product'),
);

// Kept isolate-safe: dart:developer has no Flutter binding dependency.
void print(Object? message) {
  if (_serviceLogsEnabled) developer.log('$message', name: 'foreground');
}

class ForegroundServiceManager {
  static bool _isConfigured = false;
  static const String _channelId = 'dostavka_service';

  static Future<void> initialize() async {
    if (_isConfigured) return;
    _isConfigured = true;

    final FlutterLocalNotificationsPlugin flnp =
        FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await flnp.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: _handleNotificationTap,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    final launchDetails = await flnp.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      await _storePendingOrder(launchDetails?.notificationResponse?.payload);
    }

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin = flnp
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

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
    print('🟢 start() called with role=$role, courier=$courierId');

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

Future<void> _storePendingOrder(String? payload) async {
  final orderId = int.tryParse(payload ?? '');
  if (orderId == null) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('pending_order_id', orderId);
}

void _handleNotificationTap(NotificationResponse response) {
  _storePendingOrder(response.payload);
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  _storePendingOrder(response.payload);
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    await service.setForegroundNotificationInfo(
      title: 'Доставка',
      content: 'Сервис работает — ожидание заказов',
    );
  }

  print('═══════════════════════════════════');
  print('🟢 onStart() CALLED in background');
  print('═══════════════════════════════════');

  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('ws_token') ?? '';
  final courierId = prefs.getInt('ws_courier_id');

  print('🔑 Credentials loaded for courier=$courierId');

  if (token.isEmpty || courierId == null) {
    print('❌ onStart() — no token/courier, bailing');
    return;
  }

  final savedUrl = prefs.getString('server_url') ?? '';
  final baseUrl = savedUrl.isNotEmpty ? savedUrl : 'http://10.0.2.2:8000';
  final wsBase = baseUrl
      .replaceFirst('http://', 'ws://')
      .replaceFirst('https://', 'wss://');

  print('🌐 Server: $baseUrl, WS: $wsBase');

  print('✅ Foreground notification set');

  final FlutterLocalNotificationsPlugin flnPlugin =
      FlutterLocalNotificationsPlugin();
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

  final knownOrdersKey = 'known_order_ids_$courierId';
  final baselineKey = 'known_order_baseline_$courierId';
  final Set<int> knownOrderIds =
      (prefs.getStringList(knownOrdersKey) ?? const <String>[])
          .map(int.tryParse)
          .whereType<int>()
          .toSet();
  bool baselineInitialized = prefs.getBool(baselineKey) ?? false;
  int notificationId = 1;

  void recordOrder(dynamic orderId) {
    final parsed = orderId is int ? orderId : int.tryParse('$orderId');
    if (parsed == null) return;
    knownOrderIds.add(parsed);
    final retained = knownOrderIds.toList()..sort();
    prefs.setStringList(
      knownOrdersKey,
      retained.reversed.take(500).map((id) => '$id').toList(),
    );
  }

  bool isNewOrder(dynamic orderId) {
    final parsed = orderId is int ? orderId : int.tryParse('$orderId');
    return parsed != null && !knownOrderIds.contains(parsed);
  }

  Future<void> showOrderPush(int orderId, String title, String body) async {
    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(title: title, content: body);

      final notifId = notificationId++;
      try {
        await flnPlugin.show(
          notifId,
          title,
          body,
          pushDetails,
          payload: '$orderId',
        );
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
  final wsUrl = '$wsBase/ws/courier/$courierId';
  print('🔌 WS connecting: $wsUrl');

  WebSocket? activeWs;
  Timer? reconnectTimer;
  Timer? pollTimer;
  Timer? locationTimer;
  bool wsConnected = false;
  bool stopped = false;
  Position? lastSentPosition;

  Future<void> publishState() async {
    service.invoke('courier_state', {
      'ws_connected': wsConnected,
      'pending_count': await OfflineQueue.count(courierId),
    });
  }

  Future<void> flushQueue() async {
    await OfflineQueue.flush(
      courierId: courierId,
      baseUrl: baseUrl,
      token: token,
    );
    await publishState();
  }

  Future<void> pollOrders() async {
    if (stopped) return;
    try {
      final resp = await http
          .get(
            Uri.parse('$baseUrl/api/courier/orders/available'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final orders = json.decode(resp.body) as List<dynamic>;
        if (!baselineInitialized) {
          for (final item in orders) {
            recordOrder((item as Map<String, dynamic>)['id']);
          }
          baselineInitialized = true;
          await prefs.setBool(baselineKey, true);
          print('📡 Poll baseline initialized: ${orders.length} orders');
        } else {
          final newOrders = <Map<String, dynamic>>[];
          for (final item in orders) {
            final order = item as Map<String, dynamic>;
            if (isNewOrder(order['id'])) {
              recordOrder(order['id']);
              newOrders.add(order);
            }
          }
          for (final order in newOrders) {
            final orderId = order['id'] as int;
            final orderNumber = order['order_number'] ?? orderId;
            service.invoke('courier_event', courierEvent('new_order', order));
            await showOrderPush(
              orderId,
              '🛵 Новый заказ!',
              'Заказ №$orderNumber',
            );
          }
          print('📡 Poll: ${orders.length}, new: ${newOrders.length}');
        }
      } else {
        print('📡 Poll: HTTP ${resp.statusCode}');
      }
    } catch (error) {
      print('📡 Poll err: $error');
    } finally {
      await flushQueue();
      if (!stopped) {
        pollTimer?.cancel();
        pollTimer = Timer(Duration(seconds: wsConnected ? 90 : 15), pollOrders);
      }
    }
  }

  void reschedulePoll() {
    pollTimer?.cancel();
    pollTimer = Timer(Duration(seconds: wsConnected ? 90 : 15), pollOrders);
  }

  void scheduleReconnect(void Function() connect) {
    if (stopped || reconnectTimer?.isActive == true) return;
    reconnectTimer = Timer(const Duration(seconds: 5), connect);
  }

  Future<void> connectWs() async {
    if (stopped) return;
    try {
      final ws = await WebSocket.connect(wsUrl, protocols: [token]);
      activeWs = ws;
      wsConnected = true;
      reschedulePoll();
      await flushQueue();
      print('🟢 WS CONNECTED');

      ws.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            final type = msg['event'] as String?;
            final payload = (msg['data'] as Map<String, dynamic>?) ?? msg;

            service.invoke('courier_event', courierEvent(type, payload));

            print('📨 WS event: $type');

            if ((type == 'new_order' || type == 'order_created') &&
                payload['id'] != null) {
              final orderId = payload['id'];
              if (isNewOrder(orderId)) {
                recordOrder(orderId);
                final orderNumber = payload['order_number'] ?? orderId;
                print('🆕 NEW ORDER #$orderNumber (source: ws)');
                showOrderPush(
                  orderId as int,
                  '🛵 Новый заказ!',
                  'Заказ №$orderNumber',
                );
              }
            }
          } catch (e) {
            print('❌ WS decode error: $e');
          }
        },
        onError: (e) {
          print('🔴 WS error: $e');
          wsConnected = false;
          publishState();
          reschedulePoll();
          scheduleReconnect(connectWs);
        },
        onDone: () {
          print('🔴 WS closed — reconnecting in 5s');
          wsConnected = false;
          publishState();
          reschedulePoll();
          scheduleReconnect(connectWs);
        },
        cancelOnError: true,
      );
    } catch (e) {
      print('🔴 WS connect failed: $e — retrying in 5s');
      wsConnected = false;
      await publishState();
      reschedulePoll();
      scheduleReconnect(connectWs);
    }
  }

  Future<void> sendLocation() async {
    if (stopped) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      final moved =
          lastSentPosition == null ||
          Geolocator.distanceBetween(
                lastSentPosition!.latitude,
                lastSentPosition!.longitude,
                pos.latitude,
                pos.longitude,
              ) >=
              50;
      if (moved) {
        final payload = {'latitude': pos.latitude, 'longitude': pos.longitude};
        try {
          final response = await http
              .post(
                Uri.parse('$baseUrl/api/courier/location'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $token',
                },
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 15));
          if (response.statusCode >= 200 && response.statusCode < 300) {
            lastSentPosition = pos;
            print('📍 Location sent OK');
          } else if (OfflineQueuePolicy.shouldQueueStatus(
            response.statusCode,
          )) {
            await OfflineQueue.enqueue(
              courierId,
              OfflineOperationType.location,
              payload,
            );
          } else {
            print('📍 Location rejected: HTTP ${response.statusCode}');
          }
        } on SocketException catch (error) {
          print('📍 Location queued: $error');
          await OfflineQueue.enqueue(
            courierId,
            OfflineOperationType.location,
            payload,
          );
        } on http.ClientException catch (error) {
          print('📍 Location queued: $error');
          await OfflineQueue.enqueue(
            courierId,
            OfflineOperationType.location,
            payload,
          );
        } on TimeoutException catch (error) {
          print('📍 Location queued: $error');
          await OfflineQueue.enqueue(
            courierId,
            OfflineOperationType.location,
            payload,
          );
        }
      }
    } catch (e) {
      print('📍 Location err: $e');
    } finally {
      await publishState();
      if (!stopped) {
        locationTimer?.cancel();
        locationTimer = Timer(const Duration(seconds: 60), sendLocation);
      }
    }
  }

  service.on('flush_queue').listen((_) => flushQueue());
  service.on('stop').listen((event) {
    stopped = true;
    reconnectTimer?.cancel();
    pollTimer?.cancel();
    locationTimer?.cancel();
    activeWs?.close();
    service.stopSelf();
  });

  unawaited(connectWs());
  await flushQueue();
  await pollOrders();
  locationTimer = Timer(Duration.zero, sendLocation);
}
