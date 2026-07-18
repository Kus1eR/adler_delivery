import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/order.dart';
import '../services/auth_service.dart';
import '../services/courier_service.dart';
import '../services/foreground_service.dart';
import 'login_screen.dart';
import 'order_detail_screen.dart';

class CourierHomeScreen extends StatefulWidget {
  const CourierHomeScreen({super.key, this.courierId});

  final int? courierId;

  @override
  State<CourierHomeScreen> createState() => _CourierHomeScreenState();
}

class _CourierHomeScreenState extends State<CourierHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _courierService = CourierService();
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _startLocationUpdates();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startForegroundService());
  }

  Future<void> _startForegroundService() async {
    try {
      final authService = context.read<AuthService>();
      print('══════════════════════════════');
      print('🔑 STARTING foreground service');
      print('🔑 Token: ${authService.token?.substring(0, authService.token!.length < 10 ? authService.token!.length : 10)}...');
      print('🔑 Token null: ${authService.token == null}');
      print('🔑 Role: ${authService.role}');
      print('🔑 CourierId: ${authService.courierId}');
      print('══════════════════════════════');

      if (authService.token == null || authService.token!.isEmpty) {
        print('❌ Token is null/empty, skipping');
        return;
      }
      if (authService.courierId == null) {
        print('❌ CourierId is null, skipping');
        return;
      }

      await ForegroundServiceManager.start(
        authService.token!,
        'courier',
        courierId: authService.courierId,
      );
      print('✅ ForegroundServiceManager.start() COMPLETED');
    } catch (e, stack) {
      print('❌ ForegroundServiceManager.start() FAILED: $e');
      print('Stack: $stack');
    }
  }

  void _onMyOrderChanged() {
    setState(() => _refreshKey++);
  }

  Future<void> _startLocationUpdates() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50,
      ),
    ).listen((Position position) async {
      final authService = context.read<AuthService>();
      if (authService.token != null) {
        await _courierService.updateLocation(
          position.latitude,
          position.longitude,
          authService.token!,
        );
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Курьер'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await context.read<AuthService>().logout();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.local_shipping), text: 'Мои заказы'),
            Tab(icon: Icon(Icons.inventory_2), text: 'Доступные'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Статистика'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MyOrdersTab(key: const ValueKey('my'), courierService: _courierService, onOrderChanged: _onMyOrderChanged),
          _AvailableTab(key: const ValueKey('avail'), courierService: _courierService, refreshSignal: _refreshKey),
          _StatsTab(key: const ValueKey('stats'), courierService: _courierService),
        ],
      ),
    );
  }
}

class _AvailableTab extends StatefulWidget {
  const _AvailableTab({super.key, required this.courierService, this.refreshSignal});

  final CourierService courierService;
  final int? refreshSignal;

  @override
  State<_AvailableTab> createState() => _AvailableTabState();
}

class _AvailableTabState extends State<_AvailableTab> {
  List<Order>? _orders;
  bool _isLoading = true;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadOrders();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadOrders();
    });
  }

  @override
  void didUpdateWidget(_AvailableTab old) {
    super.didUpdateWidget(old);
    if (widget.refreshSignal != old.refreshSignal) {
      _loadOrders();
    }
  }

  Future<void> _loadOrders() async {
    if (_isLoading && _orders != null) return;
    try {
      final orders = await widget.courierService.getAvailableOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _takeOrder(Order order) async {
    try {
      await widget.courierService.takeOrder(order.id);
      if (!mounted) return;
      setState(() {
        _orders?.removeWhere((o) => o.id == order.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заказ взят')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _orders == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _orders == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text('Ошибка загрузки', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _loadOrders,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_orders == null || _orders!.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadOrders,
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.4,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'Нет доступных заказов',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Скоро появятся новые',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _orders!.length,
        itemBuilder: (context, index) {
          final order = _orders![index];
          return _OrderCard(
            key: ValueKey(order.id),
            order: order,
            actionLabel: 'Взять заказ',
            actionColor: Colors.green,
            onAction: () => _takeOrder(order),
            onTap: () => _openDetail(order),
          );
        },
      ),
    );
  }

  void _openDetail(Order order) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderDetailScreen(order: order),
      ),
    ).then((changed) {
      if (changed == true) _loadOrders();
    });
  }
}

class _MyOrdersTab extends StatefulWidget {
  const _MyOrdersTab({super.key, required this.courierService, this.onOrderChanged});

  final CourierService courierService;
  final VoidCallback? onOrderChanged;

  @override
  State<_MyOrdersTab> createState() => _MyOrdersTabState();
}

class _MyOrdersTabState extends State<_MyOrdersTab> {
  List<Order>? _orders;
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
      final orders = await widget.courierService.getMyOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders.where((o) => o.status != 'cancelled').toList();
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

  Future<void> _updateStatus(Order order, String newStatus) async {
    try {
      await widget.courierService.updateOrderStatus(order.id, newStatus);
      if (!mounted) return;
      setState(() {
        final idx = _orders?.indexWhere((o) => o.id == order.id);
        if (idx != null && idx >= 0 && _orders != null) {
          _orders![idx] = Order(
            id: order.id,
            orderNumber: order.orderNumber,
            address: order.address,
            price: order.price,
            courierFee: order.courierFee,
            description: order.description,
            status: newStatus,
            latitude: order.latitude,
            longitude: order.longitude,
            createdAt: order.createdAt,
          );
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Статус обновлён')),
      );
      widget.onOrderChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text('Ошибка загрузки', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _loadOrders,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    final active = _orders?.where((o) => o.isActive).toList() ?? [];
    final delivered = _orders?.where((o) => o.status == 'delivered').toList() ?? [];

    if (_orders == null || _orders!.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadOrders,
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.4,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_shipping, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'Нет заказов',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (active.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Активные (${active.length})',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.orange.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...active.map((order) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _OrderCard(
                key: ValueKey('${order.id}-${order.status}'),
                order: order,
                actionLabel: order.status == 'taken' ? 'В пути' : 'Доставил',
                actionColor: order.status == 'taken' ? Colors.orange : Colors.blue,
                onAction: () => _updateStatus(
                  order,
                  order.status == 'taken' ? 'in_transit' : 'delivered',
                ),
                onTap: () => _openDetail(order),
              ),
            )),
            const SizedBox(height: 16),
          ],
          if (delivered.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Доставленные (${delivered.length})',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...delivered.map((order) => _OrderCard(
              key: ValueKey('${order.id}-${order.status}'),
              order: order,
              onTap: () => _openDetail(order),
            )),
          ],
        ],
      ),
    );
  }

  void _openDetail(Order order) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderDetailScreen(order: order),
      ),
    ).then((changed) {
      if (changed == true) _loadOrders();
    });
  }
}

class _StatsTab extends StatefulWidget {
  const _StatsTab({super.key, required this.courierService});

  final CourierService courierService;

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  Map<String, dynamic>? _stats;
  List<Order>? _deliveredOrders;
  bool _isLoading = true;
  bool _isLoadingHistory = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final stats = await widget.courierService.getMyStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
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

  Future<void> _showHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final orders = await widget.courierService.getMyOrders();
      if (!mounted) return;
      setState(() {
        _deliveredOrders = orders.where((o) => o.status == 'delivered').toList();
        _isLoadingHistory = false;
      });
      if (!mounted) return;
      _showHistoryDialog();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingHistory = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  void _showHistoryDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: _deliveredOrders == null || _deliveredOrders!.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text('История доставок пуста'),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'История доставок',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _deliveredOrders!.length,
                      itemBuilder: (context, index) {
                        final o = _deliveredOrders![index];
                        return ListTile(
                          title: Text(o.orderNumber),
                          subtitle: Text(o.address),
                          trailing: Text('${o.price.toStringAsFixed(0)} ₽'),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Закрыть'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text('Ошибка загрузки', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _loadStats,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    final totalOrders = _stats?['total_orders'] ?? 0;
    final totalEarned = (_stats?['total_earned'] as num?)?.toDouble() ?? 0.0;
    final todayOrders = _stats?['today_orders'] ?? 0;
    final todayEarned = (_stats?['today_earned'] as num?)?.toDouble() ?? 0.0;

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatCard(
            icon: Icons.inventory_2,
            label: 'Всего заказов',
            value: '$totalOrders',
            color: Colors.blue,
          ),
          const SizedBox(height: 12),
          _StatCard(
            icon: Icons.account_balance_wallet,
            label: 'Заработано всего',
            value: '${totalEarned.toStringAsFixed(0)} ₽',
            color: Colors.green,
          ),
          const SizedBox(height: 12),
          _StatCard(
            icon: Icons.today,
            label: 'Сегодня заказов',
            value: '$todayOrders',
            color: Colors.orange,
          ),
          const SizedBox(height: 12),
          _StatCard(
            icon: Icons.payments,
            label: 'Сегодня заработано',
            value: '${todayEarned.toStringAsFixed(0)} ₽',
            color: Colors.purple,
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _isLoadingHistory ? null : _showHistory,
              icon: _isLoadingHistory
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.history),
              label: const Text('История доставок'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openMap(String address) async {
  final encoded = Uri.encodeComponent(address);
  final url = Uri.parse('https://maps.google.com/?q=$encoded');
  await launchUrl(url, mode: LaunchMode.externalApplication);
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    super.key,
    required this.order,
    this.actionLabel,
    this.actionColor,
    this.onAction,
    required this.onTap,
  });

  final Order order;
  final String? actionLabel;
  final Color? actionColor;
  final VoidCallback? onAction;
  final VoidCallback onTap;

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
    final statusColor = _statusColor(order.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${order.orderNumber} · +${order.courierFee.toStringAsFixed(0)} ₽',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      order.statusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _openMap(order.address),
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  children: [
                    Icon(Icons.location_on, size: 16, color: Colors.blue.shade500),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        order.address,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.blue.shade700,
                          decoration: TextDecoration.underline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.attach_money, size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    'Сумма заказа: ${order.price.toStringAsFixed(0)} ₽',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              if (order.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  order.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton(
                    onPressed: onAction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: actionColor,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(actionLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}