import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/courier.dart';
import '../models/order.dart';
import '../services/admin_service.dart';
import '../services/auth_service.dart';
import '../services/foreground_service.dart';
import '../services/websocket_service.dart';
import '../utils/date_format.dart';
import '../utils/pagination.dart';
import 'courier_detail_screen.dart';
import 'login_screen.dart';
import 'map_screen.dart';
import 'order_detail_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _currentIndex = 0;
  WebSocketService? _wsService;
  final _ordersRefreshSignal = ValueNotifier<int>(0);
  final _ordersTabKey = GlobalKey<_OrdersTabState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _initWebSocket();
        _startForegroundService();
        _requestNotificationPermission();
      } catch (e) {
        debugPrint('❌ AdminHomeScreen init error: $e');
      }
    });
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final androidPlugin = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlugin != null) {
        final granted = await androidPlugin.requestNotificationsPermission();
        debugPrint('📱 POST_NOTIFICATIONS permission granted: $granted');
      }
    } catch (e) {
      debugPrint('❌ Notification permission error: $e');
    }
  }

  void _startForegroundService() {
    try {
      final authService = context.read<AuthService>();
      if (authService.token != null) {
        ForegroundServiceManager.start(authService.token!, 'admin');
      }
    } catch (e) {
      debugPrint('❌ Foreground service error: $e');
    }
  }

  void _initWebSocket() {
    try {
      final authService = context.read<AuthService>();
      if (authService.token != null) {
        _wsService = WebSocketService(token: authService.token!);
        _wsService!.onMessage = (payload) {
          if (!mounted) return;
          final type = payload['type'] as String?;
          if (type == 'order_taken' ||
              type == 'order_status_changed' ||
              type == 'order_cancelled') {
            _ordersTabKey.currentState?.handleWsUpdate(payload);
            return;
          }
          if (type == 'order_updated') {
            _ordersRefreshSignal.value++;
            return;
          }
          _ordersRefreshSignal.value++;
        };
        _wsService!.connect();
      }
    } catch (e) {
      debugPrint('❌ WebSocket init error: $e');
    }
  }

  @override
  void dispose() {
    _wsService?.disconnect();
    _ordersRefreshSignal.dispose();
    super.dispose();
  }

  Widget _buildCurrentTab() {
    switch (_currentIndex) {
      case 0:
        return _OrdersTab(
          key: _ordersTabKey,
          refreshSignal: _ordersRefreshSignal,
        );
      case 1:
        return const _CouriersTab(key: ValueKey('couriers'));
      case 2:
        return const _StatsTab(key: ValueKey('stats'));
      case 3:
        return const MapScreen();
      default:
        return _OrdersTab(
          key: _ordersTabKey,
          refreshSignal: _ordersRefreshSignal,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Админ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              try {
                await context.read<AuthService>().logout();
                if (!context.mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              } catch (e) {
                debugPrint('❌ Logout error: $e');
              }
            },
          ),
        ],
      ),
      body: _buildCurrentTab(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Заказы',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Курьеры',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Статистика',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Карта',
          ),
        ],
      ),
    );
  }
}

// ── Tab 1: Orders ──────────────────────────────────────────────────────────────

class _OrdersTab extends StatefulWidget {
  const _OrdersTab({super.key, required this.refreshSignal});

  final ValueNotifier<int> refreshSignal;

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  final _adminService = AdminService();
  List<Order> _orders = [];
  bool _isLoading = true;
  String _activeFilter = 'all';
  String? _error;
  int _page = 1;
  int _total = 0;
  int _pages = 1;

  final _searchCtrl = TextEditingController();
  Timer? _debounceTimer;
  String _searchQuery = '';

  final _numberCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _courierFeeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _recipientPhoneCtrl = TextEditingController();
  final _adminPhoneCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOrders());
    widget.refreshSignal.addListener(_loadOrders);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    widget.refreshSignal.removeListener(_loadOrders);
    _searchCtrl.dispose();
    _numberCtrl.dispose();
    _addressCtrl.dispose();
    _priceCtrl.dispose();
    _courierFeeCtrl.dispose();
    _descCtrl.dispose();
    _recipientPhoneCtrl.dispose();
    _adminPhoneCtrl.dispose();
    super.dispose();
  }

  void handleWsUpdate(Map<String, dynamic> payload) {
    final type = payload['type'] as String?;
    final orderId = payload['id'] as int?;
    if (orderId == null) return;

    final String newStatus;
    if (type == 'order_taken') {
      newStatus = 'taken';
    } else if (type == 'order_status_changed') {
      final s = payload['status'] as String?;
      if (s == null) return;
      newStatus = s;
    } else if (type == 'order_cancelled') {
      newStatus = 'cancelled';
    } else {
      return;
    }

    setState(() {
      final idx = _orders.indexWhere((o) => o.id == orderId);
      if (idx != -1) {
        _orders[idx] = Order(
          id: orderId,
          orderNumber: _orders[idx].orderNumber,
          address: _orders[idx].address,
          price: _orders[idx].price,
          courierFee: _orders[idx].courierFee,
          description: _orders[idx].description,
          cancelReason: _orders[idx].cancelReason,
          recipientPhone: _orders[idx].recipientPhone,
          adminPhone: _orders[idx].adminPhone,
          status: newStatus,
          latitude: _orders[idx].latitude,
          longitude: _orders[idx].longitude,
          createdAt: _orders[idx].createdAt,
        );
      }
    });
  }

  Future<void> _loadOrders({int? page}) async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      final targetPage = page ?? _page;
      final PageResult<Order> result = await _adminService.getOrdersPage(
        status: _activeFilter == 'all' ? null : _activeFilter,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        page: targetPage,
        perPage: 50,
      );
      if (!mounted) return;
      setState(() {
        _orders = result.items;
        _page = result.page;
        _total = result.total;
        _pages = result.pages == 0 ? 1 : result.pages;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ _loadOrders error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _searchQuery = value.trim();
      _loadOrders(page: 1);
    });
  }

  Color statusColor(String status) {
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

  Future<void> _showCreateDialog() async {
    _numberCtrl.clear();
    _addressCtrl.clear();
    _priceCtrl.clear();
    _courierFeeCtrl.clear();
    _descCtrl.clear();
    _recipientPhoneCtrl.clear();
    _adminPhoneCtrl.clear();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Создать заказ'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _numberCtrl,
                keyboardType: TextInputType.text,
                inputFormatters: [],
                decoration: const InputDecoration(
                  labelText: 'Номер заказа',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressCtrl,
                keyboardType: TextInputType.text,
                inputFormatters: [],
                decoration: const InputDecoration(
                  labelText: 'Адрес',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Сумма заказа',
                  border: OutlineInputBorder(),
                  suffixText: '₽',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _courierFeeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Сумма курьеру',
                  border: OutlineInputBorder(),
                  suffixText: '₽',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                maxLines: 3,
                keyboardType: TextInputType.text,
                inputFormatters: [],
                decoration: const InputDecoration(
                  labelText: 'Комментарий курьеру',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _recipientPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Телефон получателя',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _adminPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Телефон администратора',
                  hintText: 'По умолчанию: +79000000000',
                  prefixIcon: Icon(Icons.support_agent),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              final number = _numberCtrl.text.trim();
              final address = _addressCtrl.text.trim();
              final price = double.tryParse(_priceCtrl.text.trim());
              final courierFee =
                  double.tryParse(_courierFeeCtrl.text.trim()) ?? 0;

              if (number.isEmpty || address.isEmpty || price == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Заполните обязательные поля')),
                );
                return;
              }

              try {
                await _adminService.createOrder(
                  number,
                  address,
                  price,
                  courierFee,
                  _descCtrl.text.trim(),
                  _recipientPhoneCtrl.text.trim(),
                  adminPhone: _adminPhoneCtrl.text.trim().isEmpty
                      ? '+79000000000'
                      : _adminPhoneCtrl.text.trim(),
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx, true);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );

    if (result == true) {
      _loadOrders();
    }
  }

  Future<void> _confirmDelete(Order order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить заказ'),
        content: Text('Удалить заказ ${order.orderNumber}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _adminService.deleteOrder(order.id);
        _loadOrders();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _showEditDialog(Order order) async {
    _numberCtrl.text = order.orderNumber;
    _addressCtrl.text = order.address;
    _priceCtrl.text = order.price.toString();
    _courierFeeCtrl.text = order.courierFee.toString();
    _descCtrl.text = order.description;
    _recipientPhoneCtrl.text = order.recipientPhone;
    _adminPhoneCtrl.text = order.adminPhone;
    final latitudeCtrl = TextEditingController(text: order.latitude.toString());
    final longitudeCtrl = TextEditingController(
      text: order.longitude.toString(),
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Редактировать ${order.orderNumber}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _numberCtrl,
                decoration: const InputDecoration(
                  labelText: 'Номер заказа',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Адрес',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Сумма заказа',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _courierFeeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Курьеру',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Комментарий',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _recipientPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Телефон получателя',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _adminPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Телефон администратора',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: latitudeCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Широта',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: longitudeCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Долгота',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              final price = double.tryParse(_priceCtrl.text.trim());
              final courierFee = double.tryParse(_courierFeeCtrl.text.trim());
              final latitude = double.tryParse(latitudeCtrl.text.trim());
              final longitude = double.tryParse(longitudeCtrl.text.trim());
              if (_numberCtrl.text.trim().isEmpty ||
                  _addressCtrl.text.trim().isEmpty ||
                  price == null ||
                  price <= 0 ||
                  courierFee == null ||
                  courierFee < 0 ||
                  latitude == null ||
                  longitude == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Проверьте введённые значения')),
                );
                return;
              }
              try {
                await _adminService.updateOrder(order.id, {
                  'order_number': _numberCtrl.text.trim(),
                  'address': _addressCtrl.text.trim(),
                  'price': price,
                  'courier_fee': courierFee,
                  'description': _descCtrl.text.trim(),
                  'recipient_phone': _recipientPhoneCtrl.text.trim(),
                  'admin_phone': _adminPhoneCtrl.text.trim(),
                  'latitude': latitude,
                  'longitude': longitude,
                });
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    latitudeCtrl.dispose();
    longitudeCtrl.dispose();
    if (result == true) {
      await _loadOrders();
    }
  }

  Future<void> _confirmCancel(Order order) async {
    final reasonController = TextEditingController();
    String? validationError;
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Отменить заказ?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Заказ ${order.orderNumber} будет отменён.'),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                minLines: 3,
                maxLines: 5,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: 'Причина отмены',
                  hintText: 'От 3 до 500 символов',
                  errorText: validationError,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Нет'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                final value = reasonController.text.trim();
                if (value.length < 3) {
                  setDialogState(
                    () => validationError = 'Введите минимум 3 символа',
                  );
                  return;
                }
                Navigator.pop(ctx, value);
              },
              child: const Text(
                'Да, отменить',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();

    if (reason != null) {
      try {
        await _adminService.cancelOrder(order.id, reason);
        _loadOrders();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Заказ ${order.orderNumber} отменён')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Поиск по номеру или адресу',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('Все', 'all'),
                      const SizedBox(width: 8),
                      _filterChip('Доступны', 'available'),
                      const SizedBox(width: 8),
                      _filterChip('Взяты', 'taken'),
                      const SizedBox(width: 8),
                      _filterChip('Доставлены', 'delivered'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _showCreateDialog,
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Создать заказ'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildOrderList(theme)),
      ],
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _activeFilter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _activeFilter = value);
        _loadOrders(page: 1);
      },
    );
  }

  Widget _buildOrderList(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _loadOrders,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'Нет заказов',
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final filteredOrders = _orders;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text('Показано ${filteredOrders.length} из $_total'),
              const Spacer(),
              IconButton(
                tooltip: 'Предыдущая страница',
                onPressed: _page > 1
                    ? () => _loadOrders(page: _page - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('$_page / $_pages'),
              IconButton(
                tooltip: 'Следующая страница',
                onPressed: _page < _pages
                    ? () => _loadOrders(page: _page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadOrders(page: _page),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filteredOrders.length,
              itemBuilder: (context, index) {
                final order = filteredOrders[index];
                final canDelete = order.status == 'available';

                return Dismissible(
                  key: ValueKey(order.id),
                  direction: canDelete
                      ? DismissDirection.endToStart
                      : DismissDirection.none,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) async {
                    await _confirmDelete(order);
                    return false;
                  },
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrderDetailScreen(order: order),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    order.orderNumber,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    order.address,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${order.price.toStringAsFixed(0)} ₽',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor(
                                      order.status,
                                    ).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    order.statusLabel,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: statusColor(order.status),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (order.status == 'available' ||
                                    order.status == 'taken') ...[
                                  const SizedBox(height: 2),
                                  SizedBox(
                                    height: 22,
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        foregroundColor: Colors.red,
                                      ),
                                      onPressed: () => _confirmCancel(order),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.cancel, size: 12),
                                          SizedBox(width: 2),
                                          Text(
                                            'Отменить',
                                            style: TextStyle(fontSize: 9),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                SizedBox(
                                  height: 22,
                                  child: TextButton.icon(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () => _showEditDialog(order),
                                    icon: const Icon(Icons.edit, size: 12),
                                    label: const Text(
                                      'Редактировать',
                                      style: TextStyle(fontSize: 9),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ── Tab 2: Couriers ────────────────────────────────────────────────────────────

class _CouriersTab extends StatefulWidget {
  const _CouriersTab({super.key});

  @override
  State<_CouriersTab> createState() => _CouriersTabState();
}

class _CouriersTabState extends State<_CouriersTab> {
  final _adminService = AdminService();
  List<Courier> _couriers = [];
  bool _isLoading = true;
  String? _error;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCouriers();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCouriers() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      final couriers = await _adminService.getCouriers();
      if (!mounted) return;
      setState(() {
        _couriers = couriers;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ _loadCouriers error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddDialog() async {
    _nameCtrl.clear();
    _phoneCtrl.clear();
    _passwordCtrl.clear();
    var obscurePassword = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Добавить курьера'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameCtrl,
                keyboardType: TextInputType.text,
                inputFormatters: [],
                decoration: const InputDecoration(
                  labelText: 'Имя',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Телефон',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordCtrl,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Пароль',
                  helperText: 'Минимум 6 символов',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () => setDialogState(
                      () => obscurePassword = !obscurePassword,
                    ),
                    icon: Icon(
                      obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    tooltip: obscurePassword
                        ? 'Показать пароль'
                        : 'Скрыть пароль',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                final name = _nameCtrl.text.trim();
                final phone = _phoneCtrl.text.trim();
                final password = _passwordCtrl.text;

                if (name.isEmpty || phone.isEmpty || password.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Заполните все поля')),
                  );
                  return;
                }
                if (password.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Пароль должен содержать минимум 6 символов',
                      ),
                    ),
                  );
                  return;
                }

                try {
                  await _adminService.createCourier(name, phone, password);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx, true);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(e.toString())));
                }
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      _loadCouriers();
    }
  }

  Future<void> _toggleBlock(Courier courier) async {
    try {
      await _adminService.blockCourier(courier.id);
      if (!mounted) return;
      setState(() {
        final index = _couriers.indexWhere((c) => c.id == courier.id);
        if (index != -1) {
          _couriers[index] = Courier(
            id: courier.id,
            name: courier.name,
            phone: courier.phone,
            status: courier.status == 'active' ? 'blocked' : 'active',
            createdAt: courier.createdAt,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Text('Курьеры', style: theme.textTheme.titleLarge),
              const Spacer(),
              FilledButton.icon(
                onPressed: _showAddDialog,
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Добавить курьера'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildCourierList(theme)),
      ],
    );
  }

  Widget _buildCourierList(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _loadCouriers,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_couriers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'Нет курьеров',
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCouriers,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _couriers.length,
        itemBuilder: (context, index) {
          final courier = _couriers[index];

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CourierDetailScreen(courier: courier),
                ),
              ),
              leading: CircleAvatar(
                backgroundColor: courier.isActive
                    ? Colors.green.shade100
                    : Colors.red.shade100,
                child: Icon(
                  Icons.person,
                  color: courier.isActive
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                ),
              ),
              title: Text(
                courier.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(courier.phone),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: courier.isActive
                          ? Colors.green.withValues(alpha: 0.15)
                          : Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      courier.statusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: courier.isActive
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 24,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: courier.isActive
                            ? Colors.red.shade700
                            : Colors.green.shade700,
                        backgroundColor: courier.isActive
                            ? Colors.red.shade50
                            : Colors.green.shade50,
                      ),
                      onPressed: () => _toggleBlock(courier),
                      child: Text(
                        courier.isActive ? 'Блок.' : 'Разблок.',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Tab 3: Stats ───────────────────────────────────────────────────────────────

class _StatsTab extends StatefulWidget {
  const _StatsTab({super.key});

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  final _adminService = AdminService();
  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
  }

  Future<void> _loadStats() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      final stats = await _adminService.getStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ _loadStats error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _loadStats,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    final totalOrders = _stats?['total_orders'] ?? 0;
    final activeOrders = _stats?['active_orders'] ?? 0;
    final deliveredOrders = _stats?['delivered_orders'] ?? 0;
    final totalRevenue = (_stats?['total_revenue'] ?? 0).toDouble();
    final recentOrders =
        (_stats?['recent_orders'] as List<dynamic>?)
            ?.map((e) => Order.fromJson(e as Map<String, dynamic>))
            .toList() ??
        <Order>[];

    Color statusColor(String status) {
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

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Статистика', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _statCard(
                  theme,
                  'Всего заказов',
                  '$totalOrders',
                  Icons.receipt_long,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  theme,
                  'Активных',
                  '$activeOrders',
                  Icons.trending_up,
                  Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _statCard(
                  theme,
                  'Доставлено',
                  '$deliveredOrders',
                  Icons.check_circle,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  theme,
                  'Доход',
                  '${totalRevenue.toStringAsFixed(0)} ₽',
                  Icons.payments,
                  Colors.indigo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Последние заказы', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (recentOrders.isEmpty)
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
            ...recentOrders.map(
              (order) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(
                    order.orderNumber,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(formatOrderDateOrOriginal(order.createdAt)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor(
                            order.status,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          order.statusLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: statusColor(order.status),
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
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statCard(
    ThemeData theme,
    String label,
    String value,
    IconData icon,
    MaterialColor color,
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
