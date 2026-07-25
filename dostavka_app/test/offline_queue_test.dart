import 'package:dostavka_app/services/offline_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('operation JSON round trip preserves fields', () {
    final created = DateTime.utc(2026, 7, 25, 12);
    final operation = OfflineOperation(
      id: 'op-1',
      type: OfflineOperationType.status,
      payload: {'order_id': 7, 'status': 'in_transit'},
      createdAt: created,
      retryCount: 2,
      nextRetryAt: created.add(const Duration(minutes: 1)),
    );

    expect(OfflineOperation.fromJson(operation.toJson()), operation);
  });

  test('prune removes expired items and keeps newest 100', () {
    final now = DateTime.utc(2026, 7, 25);
    final operations =
        List.generate(
          105,
          (index) => OfflineOperation(
            id: '$index',
            type: OfflineOperationType.location,
            payload: {'latitude': index, 'longitude': index},
            createdAt: now.subtract(Duration(hours: index)),
          ),
        )..add(
          OfflineOperation(
            id: 'expired',
            type: OfflineOperationType.location,
            payload: const {'latitude': 0, 'longitude': 0},
            createdAt: now.subtract(const Duration(days: 8)),
          ),
        );

    final pruned = OfflineQueuePolicy.prune(operations, now);

    expect(pruned, hasLength(100));
    expect(pruned.any((item) => item.id == 'expired'), isFalse);
    expect(pruned.first.id, '0');
  });

  test('retry delay is exponential and capped at 15 minutes', () {
    expect(OfflineQueuePolicy.retryDelay(0), const Duration(seconds: 15));
    expect(OfflineQueuePolicy.retryDelay(3), const Duration(minutes: 2));
    expect(OfflineQueuePolicy.retryDelay(20), const Duration(minutes: 15));
  });

  test('only retryable failures queue and obsolete replay is dropped', () {
    expect(OfflineQueuePolicy.shouldQueueStatus(500), isTrue);
    expect(OfflineQueuePolicy.shouldQueueStatus(408), isTrue);
    expect(OfflineQueuePolicy.shouldQueueStatus(400), isFalse);
    expect(OfflineQueuePolicy.replayDisposition(409), ReplayDisposition.drop);
    expect(OfflineQueuePolicy.replayDisposition(400), ReplayDisposition.drop);
    expect(OfflineQueuePolicy.replayDisposition(401), ReplayDisposition.drop);
    expect(OfflineQueuePolicy.replayDisposition(503), ReplayDisposition.retry);
    expect(
      OfflineQueuePolicy.replayDisposition(200),
      ReplayDisposition.complete,
    );
  });

  test('only monotonic status transitions are queue-safe', () {
    expect(OfflineQueuePolicy.isSafeStatus('in_transit'), isTrue);
    expect(OfflineQueuePolicy.isSafeStatus('delivered'), isTrue);
    expect(OfflineQueuePolicy.isSafeStatus('taken'), isFalse);
    expect(OfflineQueuePolicy.isSafeStatus('available'), isFalse);
  });

  test(
    'queue is isolated per courier and concurrent enqueues are preserved',
    () async {
      SharedPreferences.setMockInitialValues({});

      await Future.wait([
        OfflineQueue.enqueue(11, OfflineOperationType.status, {
          'order_id': 1,
          'status': 'in_transit',
        }),
        OfflineQueue.enqueue(11, OfflineOperationType.status, {
          'order_id': 2,
          'status': 'in_transit',
        }),
        OfflineQueue.enqueue(22, OfflineOperationType.status, {
          'order_id': 3,
          'status': 'in_transit',
        }),
      ]);

      expect(await OfflineQueue.count(11), 2);
      expect(await OfflineQueue.count(22), 1);
      await OfflineQueue.clear(11);
      expect(await OfflineQueue.count(11), 0);
      expect(await OfflineQueue.count(22), 1);
    },
  );
}
