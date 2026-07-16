import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:dostavka_app/services/auth_service.dart';
import 'package:dostavka_app/services/api_service.dart';
import 'package:dostavka_app/utils/map_utils.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _couriers = [];
  bool _loading = true;
  String? _token;
  Map<String, dynamic>? _selectedOrder;
  Map<String, dynamic>? _selectedCourier;
  List<Map<String, dynamic>> _searchResults = [];
  LatLng? _droppedMarker;

  @override
  void initState() {
    super.initState();
    _token = context.read<AuthService>().token;
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final ordersRes = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/admin/orders'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      final courierRes = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/admin/couriers/locations'),
        headers: {'Authorization': 'Bearer $_token'},
      );

      final allOrders = jsonDecode(ordersRes.body) as List;
      setState(() {
        _orders = allOrders.where((o) => o['status'] != 'delivered').cast<Map<String, dynamic>>().toList();
        _couriers = (jsonDecode(courierRes.body) as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Color _orderColor(String status) {
    switch (status) {
      case 'available':
        return MapUtils.orderAvailable;
      case 'taken':
        return MapUtils.orderTaken;
      case 'in_transit':
        return MapUtils.orderInTransit;
      default:
        return Colors.grey;
    }
  }

  Future<List<Map<String, dynamic>>> searchAddress(String query) async {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=${Uri.encodeComponent('$query, Сочи')}'
      '&format=json'
      '&limit=5'
      '&bounded=1'
      '&viewbox=39.5,43.8,40.0,43.3'
      '&addressdetails=1',
    );
    try {
      final response = await http.get(url, headers: {'User-Agent': 'DostavkaApp/1.0'});
      return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  void _onSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    final results = await searchAddress(query);
    if (mounted) {
      setState(() => _searchResults = results);
    }
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: ListView.builder(
        itemCount: _searchResults.length,
        itemBuilder: (ctx, i) {
          final result = _searchResults[i];
          return ListTile(
            leading: const Icon(Icons.location_on),
            title: Text(result['display_name']?.toString().split(',').take(3).join(',') ?? ''),
            subtitle: Text(result['type']?.toString() ?? ''),
            onTap: () {
              final lat = double.parse(result['lat']);
              final lon = double.parse(result['lon']);
              _mapController.move(LatLng(lat, lon), 16);
              setState(() => _searchResults = []);
            },
          );
        },
      ),
    );
  }

  void _addMarker(LatLng point) {
    setState(() {
      _droppedMarker = point;
    });
    _showMarkerInfo(point);
  }

  void _showMarkerInfo(LatLng point) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая точка'),
        content: Text(
          'Широта: ${point.latitude.toStringAsFixed(6)}\n'
          'Долгота: ${point.longitude.toStringAsFixed(6)}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _droppedMarker = null);
              Navigator.pop(ctx);
            },
            child: const Text('Удалить'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Карта'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(43.5855, 39.7231),
                    initialZoom: 12,
                    onLongPress: (tapPosition, point) {
                      _addMarker(point);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.dostavka_app',
                    ),
                    MarkerLayer(
                      markers: [
                        if (_droppedMarker != null)
                          Marker(
                            point: _droppedMarker!,
                            child: const Icon(Icons.push_pin, color: Colors.red, size: 40),
                          ),
                        ..._orders.map((order) => Marker(
                          point: LatLng(
                            (order['latitude'] as num).toDouble(),
                            (order['longitude'] as num).toDouble(),
                          ),
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _selectedOrder = order;
                              _selectedCourier = null;
                            }),
                            child: Icon(
                              Icons.room,
                              color: _orderColor(order['status']),
                              size: MapUtils.markerSize,
                            ),
                          ),
                        )),
                      ],
                    ),
                    MarkerLayer(
                      markers: _couriers.map((courier) => Marker(
                        point: LatLng(
                          (courier['latitude'] as num).toDouble(),
                          (courier['longitude'] as num).toDouble(),
                        ),
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _selectedCourier = courier;
                            _selectedOrder = null;
                          }),
                          child: const Icon(Icons.delivery_dining, color: MapUtils.courierColor, size: 40),
                        ),
                      )).toList(),
                    ),
                  ],
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Поиск адреса...',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onChanged: _onSearch,
                      ),
                      _buildSearchResults(),
                    ],
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 120,
                  child: FloatingActionButton.small(
                    onPressed: () {
                      if (_orders.isNotEmpty) {
                        _mapController.move(
                          LatLng(
                            (_orders.last['latitude'] as num).toDouble(),
                            (_orders.last['longitude'] as num).toDouble(),
                          ),
                          14,
                        );
                      }
                    },
                    child: const Icon(Icons.my_location),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: _buildInfoPanel(),
                ),
              ],
            ),
    );
  }

  Widget _buildInfoPanel() {
    if (_selectedOrder != null) {
      return Card(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Заказ ${_selectedOrder!['order_number']}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text('Адрес: ${_selectedOrder!['address']}'),
              Text('Статус: ${_selectedOrder!['status']}'),
              if (_selectedOrder!['price'] != null)
                Text('Цена: ${_selectedOrder!['price']} ₽'),
              if (_selectedOrder!['recipient_phone'] != null &&
                  (_selectedOrder!['recipient_phone'] as String).isNotEmpty)
                Text('Тел.: ${_selectedOrder!['recipient_phone']}'),
            ],
          ),
        ),
      );
    }
    if (_selectedCourier != null) {
      return Card(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Курьер: ${_selectedCourier!['name'] ?? _selectedCourier!['courier_name'] ?? 'Неизвестно'}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text('Статус: ${_selectedCourier!['status'] ?? 'активен'}'),
            ],
          ),
        ),
      );
    }
    return _buildLegend();
  }

  Widget _buildLegend() {
    return Card(
      color: Colors.white.withAlpha(230),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _legendItem(Icons.room, MapUtils.orderAvailable, 'Доступен'),
            _legendItem(Icons.room, MapUtils.orderTaken, 'Взят'),
            _legendItem(Icons.room, MapUtils.orderInTransit, 'В пути'),
            _legendItem(Icons.delivery_dining, MapUtils.courierColor, 'Курьер'),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(IconData icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
