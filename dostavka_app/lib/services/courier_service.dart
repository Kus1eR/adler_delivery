import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/order.dart';
import 'api_service.dart';
import 'offline_queue.dart';

class CourierService {
  CourierService({required this.courierId});

  final int courierId;
  final ApiService _api = ApiService();

  Future<List<Order>> getAvailableOrders() async {
    final data = await _api.getList('/api/courier/orders/available');
    return data.map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> takeOrder(int orderId) async {
    await _api.post('/api/courier/orders/$orderId/take', {});
  }

  Future<bool> updateOrderStatus(int orderId, String status) async {
    try {
      await _api.patch('/api/courier/orders/$orderId/status', {
        'status': status,
      });
      return false;
    } on ApiException catch (error) {
      if (!OfflineQueuePolicy.isSafeStatus(status) ||
          !OfflineQueuePolicy.shouldQueueStatus(error.statusCode)) {
        rethrow;
      }
    } on SocketException {
      if (!OfflineQueuePolicy.isSafeStatus(status)) rethrow;
    } on http.ClientException {
      if (!OfflineQueuePolicy.isSafeStatus(status)) rethrow;
    } on TimeoutException {
      if (!OfflineQueuePolicy.isSafeStatus(status)) rethrow;
    }
    await OfflineQueue.enqueue(courierId, OfflineOperationType.status, {
      'order_id': orderId,
      'status': status,
    });
    return true;
  }

  Future<List<Order>> getMyOrders() async {
    final data = await _api.getList('/api/courier/orders/my');
    return data.map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> getMyStats() async {
    return await _api.get('/api/courier/orders/my/stats');
  }

  Future<Map<String, dynamic>> getAdminPhone() async {
    return await _api.get('/api/courier/admin-phone');
  }
}
