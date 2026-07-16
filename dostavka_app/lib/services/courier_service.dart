import '../models/order.dart';
import 'api_service.dart';

class CourierService {
  final ApiService _api = ApiService();

  Future<List<Order>> getAvailableOrders() async {
    final data = await _api.getList('/api/courier/orders/available');
    return data
        .map((e) => Order.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> takeOrder(int orderId) async {
    await _api.post('/api/courier/orders/$orderId/take', {});
  }

  Future<void> updateOrderStatus(int orderId, String status) async {
    await _api.patch('/api/courier/orders/$orderId/status', {
      'status': status,
    });
  }

  Future<List<Order>> getMyOrders() async {
    final data = await _api.getList('/api/courier/orders/my');
    return data
        .map((e) => Order.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> getMyStats() async {
    return await _api.get('/api/courier/orders/my/stats');
  }

  Future<Map<String, dynamic>> getAdminPhone() async {
    return await _api.get('/api/courier/admin-phone');
  }

  Future<void> updateLocation(double lat, double lng, String token) async {
    await _api.postWithToken('/api/courier/location', {
      'latitude': lat,
      'longitude': lng,
    }, token);
  }
}
