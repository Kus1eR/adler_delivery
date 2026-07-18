import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/order.dart';
import '../services/auth_service.dart';
import '../services/courier_service.dart';
import 'login_screen.dart';

String formatOrderDate(String isoDate) {
  final date = DateTime.parse(isoDate);
  final months = ['янв','фев','мар','апр','май','июн','июл','авг','сен','окт','ноя','дек'];
  return '${date.day} ${months[date.month - 1]}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key, required this.order});

  final Order order;

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

  String _actionLabel(String status) {
    switch (status) {
      case 'available':
        return 'Взять заказ';
      case 'taken':
        return 'В пути';
      case 'in_transit':
        return 'Доставил';
      default:
        return '';
    }
  }

  String? _nextStatus(String status) {
    switch (status) {
      case 'available':
        return null;
      case 'taken':
        return 'in_transit';
      case 'in_transit':
        return 'delivered';
      default:
        return null;
    }
  }

  Future<void> _handleAction(BuildContext context) async {
    final courierService = CourierService();
    final nextStatus = _nextStatus(order.status);
    final scaffold = ScaffoldMessenger.of(context);

    try {
      if (order.status == 'available') {
        await courierService.takeOrder(order.id);
        if (!context.mounted) return;
        scaffold.showSnackBar(
          const SnackBar(content: Text('Заказ взят')),
        );
      } else if (nextStatus != null) {
        await courierService.updateOrderStatus(order.id, nextStatus);
        if (!context.mounted) return;
        scaffold.showSnackBar(
          SnackBar(content: Text('Статус изменён на "${order.statusLabel}"')),
        );
      }
      if (context.mounted) {
        Navigator.pop(context, true);
      }
    } on Exception catch (e) {
      if (!context.mounted) return;
      scaffold.showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade700),
      );
    } catch (e) {
      if (!context.mounted) return;
      scaffold.showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Future<void> _openYandexMaps(String address) async {
    final encoded = Uri.encodeComponent(address);
    final appUrl = Uri.parse('yandexmaps://maps.yandex.ru/?text=$encoded');
    if (await canLaunchUrl(appUrl)) {
      await launchUrl(appUrl, mode: LaunchMode.externalApplication);
      return;
    }
    final webUrl = Uri.parse('https://maps.yandex.ru/?text=$encoded');
    await launchUrl(webUrl, mode: LaunchMode.externalApplication);
  }

  void _showCallDialog(BuildContext context, String title, String phone) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Позвонить $title'),
        content: Text('Номер: $phone\n\nНажмите "Позвонить", чтобы скопировать номер в буфер обмена и позвонить через телефонную книгу.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Позвонить'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: phone));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Номер $phone скопирован в буфер обмена')),
              );
            },
          ),
        ],
      ),
    );
  }

  void _callAdmin(BuildContext context) {
    _showCallDialog(context, 'администратору', order.adminPhone);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canAct = order.status != 'delivered';
    final actionLabel = _actionLabel(order.status);

    return Scaffold(
      appBar: AppBar(
        title: Text('Заказ ${order.orderNumber}'),
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order.orderNumber,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '+${order.courierFee.toStringAsFixed(0)} ₽',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.green.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor(order.status).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                order.statusLabel,
                style: TextStyle(
                  color: _statusColor(order.status),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _infoRow(
              theme, Icons.location_on, 'Адрес', order.address,
              onTap: () => _openYandexMaps(order.address),
            ),
            if (order.recipientPhone.isNotEmpty) ...[
              const SizedBox(height: 16),
              _infoRow(
                theme, Icons.phone, 'Телефон получателя', order.recipientPhone,
                onTap: () => Clipboard.setData(ClipboardData(text: order.recipientPhone)),
              ),
            ],
            const SizedBox(height: 16),
            _infoRow(theme, Icons.attach_money, 'Сумма заказа',
                '${order.price.toStringAsFixed(0)} ₽'),
            if (order.description.isNotEmpty) ...[
              const SizedBox(height: 16),
              _infoRow(theme, Icons.comment, 'Комментарий курьеру', order.description),
            ],
            const SizedBox(height: 16),
            _infoRow(theme, Icons.access_time, 'Создан', formatOrderDate(order.createdAt)),
            const SizedBox(height: 32),
            if (canAct)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => _handleAction(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                  ),
                  child: Text(actionLabel, style: const TextStyle(fontSize: 18)),
                ),
              ),
            if (order.recipientPhone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.support_agent),
                    label: const Text('📞 Связаться с администратором'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade50,
                      foregroundColor: Colors.blue.shade800,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => _callAdmin(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(ThemeData theme, IconData icon, String label, String value, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: onTap != null ? Colors.blue.shade600 : theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: onTap != null ? Colors.blue.shade700 : null,
                      decoration: onTap != null ? TextDecoration.underline : null,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.open_in_new, size: 16, color: Colors.blue.shade400),
          ],
        ),
      ),
    );
  }
}
