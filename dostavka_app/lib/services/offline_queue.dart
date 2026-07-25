import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum OfflineOperationType { location, status }

enum ReplayDisposition { complete, retry, drop }

class OfflineOperation {
  const OfflineOperation({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.nextRetryAt,
  });

  final String id;
  final OfflineOperationType type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final DateTime? nextRetryAt;

  factory OfflineOperation.fromJson(Map<String, dynamic> json) {
    return OfflineOperation(
      id: json['id'] as String,
      type: OfflineOperationType.values.byName(json['type'] as String),
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      retryCount: json['retry_count'] as int? ?? 0,
      nextRetryAt: json['next_retry_at'] == null
          ? null
          : DateTime.parse(json['next_retry_at'] as String).toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'payload': payload,
    'created_at': createdAt.toUtc().toIso8601String(),
    'retry_count': retryCount,
    'next_retry_at': nextRetryAt?.toUtc().toIso8601String(),
  };

  OfflineOperation retried(DateTime now) {
    final count = retryCount + 1;
    return OfflineOperation(
      id: id,
      type: type,
      payload: payload,
      createdAt: createdAt,
      retryCount: count,
      nextRetryAt: now.add(OfflineQueuePolicy.retryDelay(count)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OfflineOperation &&
      id == other.id &&
      type == other.type &&
      jsonEncode(payload) == jsonEncode(other.payload) &&
      createdAt == other.createdAt &&
      retryCount == other.retryCount &&
      nextRetryAt == other.nextRetryAt;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    jsonEncode(payload),
    createdAt,
    retryCount,
    nextRetryAt,
  );
}

class OfflineQueuePolicy {
  static const int maxSize = 100;
  static const Duration maxAge = Duration(days: 7);

  static List<OfflineOperation> prune(
    Iterable<OfflineOperation> operations,
    DateTime now,
  ) {
    final kept =
        operations
            .where((item) => now.difference(item.createdAt) <= maxAge)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return kept.take(maxSize).toList();
  }

  static Duration retryDelay(int retryCount) {
    final seconds = 15 * (1 << retryCount.clamp(0, 6));
    return Duration(seconds: seconds > 900 ? 900 : seconds);
  }

  static bool shouldQueueStatus(int statusCode) =>
      statusCode == 408 || statusCode >= 500;

  static bool isSafeStatus(String status) =>
      status == 'in_transit' || status == 'delivered';

  static ReplayDisposition replayDisposition(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) {
      return ReplayDisposition.complete;
    }
    if (statusCode >= 400 && statusCode < 500 && statusCode != 408) {
      return ReplayDisposition.drop;
    }
    return ReplayDisposition.retry;
  }
}

class OfflineQueue {
  static const String storageKey = 'offline_operations';
  static Future<void> _pendingMutation = Future<void>.value();

  static String _storageKey(int courierId) => '${storageKey}_$courierId';

  static Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _pendingMutation.then((_) => action());
    _pendingMutation = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  static Future<List<OfflineOperation>> load(int courierId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _storageKey(courierId);
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return OfflineQueuePolicy.prune(
        decoded.map(
          (item) =>
              OfflineOperation.fromJson(Map<String, dynamic>.from(item as Map)),
        ),
        DateTime.now().toUtc(),
      );
    } catch (error) {
      print('Offline queue decode failed, clearing: $error');
      await prefs.remove(key);
      return [];
    }
  }

  static Future<int> count(int courierId) async =>
      (await load(courierId)).length;

  static Future<void> clear(int courierId) => _serialize(
    () async =>
        (await SharedPreferences.getInstance()).remove(_storageKey(courierId)),
  );

  static Future<void> enqueue(
    int courierId,
    OfflineOperationType type,
    Map<String, dynamic> payload,
  ) => _serialize(() async {
    final now = DateTime.now().toUtc();
    final operations = await load(courierId);
    if (type == OfflineOperationType.location) {
      operations.removeWhere((item) => item.type == type);
    }
    operations.add(
      OfflineOperation(
        id: '${now.microsecondsSinceEpoch}-${type.name}',
        type: type,
        payload: payload,
        createdAt: now,
      ),
    );
    await _save(courierId, OfflineQueuePolicy.prune(operations, now));
  });

  static Future<void> flush({
    required int courierId,
    required String baseUrl,
    required String token,
  }) => _serialize(() async {
    final now = DateTime.now().toUtc();
    final operations = await load(courierId);
    final remaining = <OfflineOperation>[];
    final blockedOrderIds = <int>{};
    for (final operation in operations.reversed) {
      final orderId = operation.type == OfflineOperationType.status
          ? operation.payload['order_id'] as int?
          : null;
      if (orderId != null && blockedOrderIds.contains(orderId)) {
        remaining.add(operation);
        continue;
      }
      if (operation.nextRetryAt?.isAfter(now) ?? false) {
        remaining.add(operation);
        if (orderId != null) blockedOrderIds.add(orderId);
        continue;
      }
      try {
        final response = await _send(operation, baseUrl, token);
        switch (OfflineQueuePolicy.replayDisposition(response.statusCode)) {
          case ReplayDisposition.complete:
            break;
          case ReplayDisposition.drop:
            print(
              'Dropping obsolete ${operation.type.name} operation '
              '${operation.id}: HTTP ${response.statusCode}',
            );
            break;
          case ReplayDisposition.retry:
            remaining.add(operation.retried(now));
            if (orderId != null) blockedOrderIds.add(orderId);
        }
      } on SocketException catch (error) {
        print('Offline queue network retry: $error');
        remaining.add(operation.retried(now));
        if (orderId != null) blockedOrderIds.add(orderId);
      } on http.ClientException catch (error) {
        print('Offline queue client retry: $error');
        remaining.add(operation.retried(now));
        if (orderId != null) blockedOrderIds.add(orderId);
      } on HttpException catch (error) {
        print('Offline queue HTTP retry: $error');
        remaining.add(operation.retried(now));
        if (orderId != null) blockedOrderIds.add(orderId);
      } on TimeoutException catch (error) {
        print('Offline queue timeout retry: $error');
        remaining.add(operation.retried(now));
        if (orderId != null) blockedOrderIds.add(orderId);
      }
    }
    await _save(courierId, OfflineQueuePolicy.prune(remaining, now));
  });

  static Future<http.Response> _send(
    OfflineOperation operation,
    String baseUrl,
    String token,
  ) {
    final path = operation.type == OfflineOperationType.location
        ? '/api/courier/location'
        : '/api/courier/orders/${operation.payload['order_id']}/status';
    final body = operation.type == OfflineOperationType.location
        ? operation.payload
        : {'status': operation.payload['status']};
    final request = operation.type == OfflineOperationType.location
        ? http.post
        : http.patch;
    return request(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));
  }

  static Future<void> _save(
    int courierId,
    List<OfflineOperation> operations,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey(courierId),
      jsonEncode(operations.map((item) => item.toJson()).toList()),
    );
  }
}

void print(Object? message) {
  if (!const bool.fromEnvironment('dart.vm.product')) {
    developer.log('$message', name: 'offline_queue');
  }
}
