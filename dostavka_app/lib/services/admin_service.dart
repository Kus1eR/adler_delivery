import '../models/courier.dart';
import '../models/order.dart';
import 'api_service.dart';

class AdminService {
  final ApiService _api = ApiService();

  Future<List<Courier>> getCouriers() async {
    final data = await _api.getList('/api/admin/couriers');
    return data
        .map((e) => Courier.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createCourier(String name, String phone) async {
    await _api.post('/api/admin/couriers', {
      'name': name,
      'phone': phone,
    });
  }

  Future<void> blockCourier(int id) async {
    await _api.patch('/api/admin/couriers/$id/block', {});
  }

  Future<List<Order>> getAllOrders({String? status}) async {
    String path = '/api/admin/orders';
    if (status != null && status != 'all') {
      path += '?status=$status';
    }
    final data = await _api.getList(path);
    return data
        .map((e) => Order.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Order>> getOrdersByCourier(int courierId) async {
    final data = await _api.getList('/api/admin/orders?courier_id=$courierId');
    return data
        .map((e) => Order.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createOrder(
    String orderNumber,
    String address,
    double price,
    double courierFee,
    String description,
    String recipientPhone, {
    String adminPhone = '+79000000000',
  }) async {
    await _api.post('/api/admin/orders', {
      'order_number': orderNumber,
      'address': address,
      'price': price,
      'courier_fee': courierFee,
      'description': description,
      'recipient_phone': recipientPhone,
      'admin_phone': adminPhone,
    });
  }

  Future<void> deleteOrder(int id) async {
    await _api.delete('/api/admin/orders/$id');
  }

  Future<Map<String, dynamic>> getStats() async {
    return await _api.get('/api/admin/orders/stats');
  }

  Future<List<Map<String, dynamic>>> getCourierLocations(String token) async {
    final data = await _api.getListWithToken('/api/admin/couriers/locations', token);
    return data.cast<Map<String, dynamic>>();
  }
}
