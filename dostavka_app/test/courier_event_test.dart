import 'package:flutter_test/flutter_test.dart';
import 'package:dostavka_app/utils/courier_event.dart';

void main() {
  test('courierEvent exposes order and status changes to the UI', () {
    expect(
      courierEvent('order_status_changed', {'id': 42, 'status': 'in_transit'}),
      {'type': 'order_status_changed', 'order_id': 42, 'status': 'in_transit'},
    );
  });

  test('courierEvent tolerates event payloads without an order', () {
    expect(courierEvent('heartbeat', const {}), {
      'type': 'heartbeat',
      'order_id': null,
      'status': null,
    });
  });
}
