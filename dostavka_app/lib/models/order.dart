class Order {
  final int id;
  final String orderNumber;
  final String address;
  final double price;
  final double courierFee;
  final String description;
  final String recipientPhone;
  final String adminPhone;
  final String status;
  final double latitude;
  final double longitude;
  final String createdAt;

  const Order({
    required this.id,
    required this.orderNumber,
    required this.address,
    required this.price,
    this.courierFee = 0.0,
    required this.description,
    this.recipientPhone = '',
    this.adminPhone = '+79000000000',
    required this.status,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'] as int,
      orderNumber: json['order_number'] as String? ?? '',
      address: json['address'] as String? ?? '',
      price: (json['price'] as num).toDouble(),
      courierFee: (json['courier_fee'] as num?)?.toDouble() ?? 0.0,
      description: json['description'] as String? ?? '',
      recipientPhone: json['recipient_phone'] as String? ?? '',
      adminPhone: json['admin_phone'] as String? ?? '+79000000000',
      status: json['status'] as String? ?? 'available',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      createdAt: json['created_at'] as String? ?? '',
    );
  }

  String get statusLabel {
    switch (status) {
      case 'available':
        return 'Доступен';
      case 'taken':
        return 'Взят';
      case 'in_transit':
        return 'В пути';
      case 'delivered':
        return 'Доставлен';
      case 'cancelled':
        return 'Отменён';
      default:
        return status;
    }
  }

  bool get isActive => status == 'taken' || status == 'in_transit';
}
