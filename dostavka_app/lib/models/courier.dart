class Courier {
  final int id;
  final String name;
  final String phone;
  final String status;
  final String createdAt;

  const Courier({
    required this.id,
    required this.name,
    required this.phone,
    required this.status,
    required this.createdAt,
  });

  factory Courier.fromJson(Map<String, dynamic> json) {
    return Courier(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      createdAt: json['created_at'] as String? ?? '',
    );
  }

  bool get isBlocked => status == 'blocked';
  bool get isActive => status == 'active';

  String get statusLabel => isBlocked ? 'Заблокирован' : 'Активен';
}
