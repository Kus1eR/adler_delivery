import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

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
    final prefs = await SharedPreferences.getInstance();
    _token = data['access_token'] as String?;
    _role = data['role'] as String?;
    _courierId = data['courier_id'] as int?;

    await prefs.setString('access_token', _token ?? '');
    await prefs.setString('role', _role ?? '');
    if (_courierId != null) {
      await prefs.setInt('courier_id', _courierId!);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> logout() async {
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
