import 'package:flutter/material.dart';
import '../models/courier.dart';
import '../models/order.dart';
import '../services/admin_service.dart';
import '../utils/date_format.dart';
import 'order_detail_screen.dart';

class CourierDetailScreen extends StatefulWidget {
  final Courier courier;

  const CourierDetailScreen({super.key, required this.courier});

  @override
  State<CourierDetailScreen> createState() => _CourierDetailScreenState();
}

class _CourierDetailScreenState extends State<CourierDetailScreen> {
  final _adminService = AdminService();
  List<Order> _orders = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final orders = await _adminService.fetchAllOrders(
        courierId: widget.courier.id,
      );
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'available':
        return Colors.green;
      case 'taken':
        return Colors.orange;
      case 'in_transit':
        return Colors.blue;
      case 'delivered':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final courier = widget.courier;
    final totalOrders = _orders.length;
    final deliveredOrders = _orders
        .where((o) => o.status == 'delivered')
        .length;
    final totalEarned = _orders
        .where((o) => o.status == 'delivered')
        .fold<double>(0, (sum, o) => sum + o.courierFee);

    return Scaffold(
      appBar: AppBar(title: Text(courier.name)),
      body: RefreshIndicator(
        onRefresh: _loadOrders,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: courier.isActive
                              ? Colors.green.shade100
                              : Colors.red.shade100,
                          child: Icon(
                            Icons.person,
                            size: 32,
                            color: courier.isActive
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                courier.name,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                courier.phone,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: courier.isActive
                                ? Colors.green.withValues(alpha: 0.15)
                                : Colors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            courier.statusLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: courier.isActive
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Статистика', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _statCard(
                    'Всего заказов',
                    '$totalOrders',
                    Icons.receipt_long,
                    Colors.blue,
                    theme,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statCard(
                    'Доставлено',
                    '$deliveredOrders',
                    Icons.check_circle,
                    Colors.green,
                    theme,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _statCard(
              'Заработано',
              '${totalEarned.toStringAsFixed(0)} ₽',
              Icons.account_balance_wallet,
              Colors.indigo,
              theme,
            ),
            const SizedBox(height: 24),
            Text('Заказы курьера', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                  ],
                ),
              )
            else if (_orders.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Нет заказов',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ),
              )
            else
              ..._orders.map(
                (order) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      order.orderNumber,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${order.address} · ${formatOrderDate(order.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor(
                              order.status,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            order.statusLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: _statusColor(order.status),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${order.price.toStringAsFixed(0)} ₽',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderDetailScreen(order: order),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(
    String label,
    String value,
    IconData icon,
    MaterialColor color,
    ThemeData theme,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color.shade400, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
