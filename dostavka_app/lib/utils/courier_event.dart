Map<String, dynamic> courierEvent(String? type, Map<String, dynamic> payload) =>
    {'type': type, 'order_id': payload['id'], 'status': payload['status']};
