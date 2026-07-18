import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'foreground_service.dart';

class AuthService extends ChangeNotifier {
  final ApiService _api = ApiService();

  String? _token;
  String? _role;
  int? _courierId;
  bool _isLoading = false;

  String? get token => _token;
  String? get role => _role;
  int? get courierId => _courierId;
  bool get isLoggedIn => _token != null;
  bool get isLoading => _isLoading;

  Map<String, dynamic> _decodeJwt(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return {};
    final payload = parts[1];
    final normalized = base64.normalize(payload);
    final decoded = utf8.decode(base64.decode(normalized));
    return jsonDecode(decoded) as Map<String, dynamic>;
  }

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('access_token');
    _role = prefs.getString('role');
    _courierId = prefs.getInt('courier_id');
    notifyListeners();
  }

  Future<void> loginAdmin(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _api.loginAdmin(username, password);
      await _saveSession(data);
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> loginCourier(String phone) async {
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _api.loginCourier(phone);
      await _saveSession(data);
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _saveSession(Map<String, dynamic> data) async {
    final tokenStr = data['access_token'] as String?;

    Map<String, dynamic> jwtPayload = {};
    if (tokenStr != null) {
      jwtPayload = _decodeJwt(tokenStr);
    }

    _token = tokenStr;
    _role = (data['role'] ?? jwtPayload['role']) as String?;

    final rawUserId = data['user_id'] ?? jwtPayload['sub'];
    _courierId = rawUserId is int ? rawUserId : int.tryParse(rawUserId?.toString() ?? '');

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', _token ?? '');
    await prefs.setString('role', _role ?? '');
    if (_courierId != null) {
      await prefs.setInt('courier_id', _courierId!);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> logout() async {
    await ForegroundServiceManager.stop();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('role');
    await prefs.remove('courier_id');

    _token = null;
    _role = null;
    _courierId = null;
    notifyListeners();
  }
}
