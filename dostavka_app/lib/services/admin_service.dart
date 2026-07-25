import '../models/courier.dart';
import '../models/order.dart';
import 'api_service.dart';
import '../utils/pagination.dart';

class AdminService {
  final ApiService _api = ApiService();

  Future<List<Courier>> getCouriers() async {
    final data = await _api.getList('/api/admin/couriers');
    return data
        .map((e) => Courier.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createCourier(String name, String phone, String password) async {
    await _api.post('/api/admin/couriers', {
      'name': name,
      'phone': phone,
      'password': password,
    });
  }

  Future<void> blockCourier(int id) async {
    await _api.patch('/api/admin/couriers/$id/block', {});
  }

  Future<PageResult<Order>> getOrdersPage({
    String? status,
    String? search,
    int page = 1,
    int perPage = 50,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (status != null && status != 'all') {
      params['status'] = status;
    }
    if (search != null && search.isNotEmpty) {
      params['search'] = search;
    }

    final queryString = params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');

    final data = await _api.get('/api/admin/orders?$queryString');
    final items = (data['items'] as List<dynamic>)
        .map((e) => Order.fromJson(e as Map<String, dynamic>))
        .toList();
    return PageResult<Order>(
      items: items,
      total: data['total'] as int,
      page: data['page'] as int,
      pages: data['pages'] as int,
    );
  }

  Future<List<Order>> fetchAllOrders({
    String? status,
    String? search,
    int? courierId,
    int maxPages = 10,
    int maxItems = 1000,
  }) {
    return fetchAllPages<Order>(
      maxPages: maxPages,
      maxItems: maxItems,
      fetchPage: (page) async {
        if (courierId == null) {
          return getOrdersPage(
            status: status,
            search: search,
            page: page,
            perPage: 100,
          );
        }
        final data = await _api.get(
          '/api/admin/orders?courier_id=$courierId&page=$page&per_page=100',
        );
        return PageResult<Order>(
          items: (data['items'] as List<dynamic>)
              .map((e) => Order.fromJson(e as Map<String, dynamic>))
              .toList(),
          total: data['total'] as int,
          page: data['page'] as int,
          pages: data['pages'] as int,
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> fetchAllOrderData({
    int maxPages = 10,
    int maxItems = 1000,
  }) {
    return fetchAllPages<Map<String, dynamic>>(
      maxPages: maxPages,
      maxItems: maxItems,
      fetchPage: (page) async {
        final data = await _api.get(
          '/api/admin/orders?page=$page&per_page=100',
        );
        return PageResult<Map<String, dynamic>>(
          items: (data['items'] as List<dynamic>).cast<Map<String, dynamic>>(),
          total: data['total'] as int,
          page: data['page'] as int,
          pages: data['pages'] as int,
        );
      },
    );
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

  Future<void> updateOrder(int id, Map<String, dynamic> fields) async {
    await _api.patch('/api/admin/orders/$id', fields);
  }

  Future<void> deleteOrder(int id) async {
    await _api.delete('/api/admin/orders/$id');
  }

  Future<void> cancelOrder(int id, String reason) async {
    final encodedReason = Uri.encodeQueryComponent(reason);
    await _api.patch(
      '/api/v1/admin/orders/$id/cancel?reason=$encodedReason',
      {},
    );
  }

  Future<Map<String, dynamic>> getStats() async {
    return await _api.get('/api/admin/orders/stats');
  }

  Future<List<Map<String, dynamic>>> getCourierLocations(String token) async {
    final data = await _api.getListWithToken(
      '/api/admin/couriers/locations',
      token,
    );
    return data.cast<Map<String, dynamic>>();
  }
}
