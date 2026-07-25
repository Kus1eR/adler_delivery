import 'package:dostavka_app/models/order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses cancellation reason', () {
    final order = Order.fromJson({
      'id': 1,
      'order_number': 'ORDER-1',
      'address': 'Address',
      'price': 100,
      'courier_fee': 10,
      'description': null,
      'cancel_reason': 'Получатель отказался',
      'status': 'cancelled',
      'latitude': 1,
      'longitude': 2,
      'created_at': '2026-07-25T10:00:00',
    });

    expect(order.cancelReason, 'Получатель отказался');
  });
}
