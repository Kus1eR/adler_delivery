import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String _emulatorUrl = 'http://10.0.2.2:8000';
  static String _customUrl = '';

  static String get baseUrl {
    if (_customUrl.isNotEmpty) return _customUrl;
    return _emulatorUrl;
  }

  static Future<void> setServerUrl(String url) async {
    _customUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);
  }

  static Future<void> loadSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    _customUrl = prefs.getString('server_url') ?? '';
  }

  static String get currentUrl => baseUrl;

  Future<Map<String, dynamic>> loginAdmin(
    String username,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw ApiException.fromStatusCode(response.statusCode, response.body);
  }

  Future<Map<String, dynamic>> loginCourier(String phone) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/courier/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw ApiException.fromStatusCode(response.statusCode, response.body);
  }

  Future<Map<String, String>> _authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<List<dynamic>> getList(String path) async {
    final headers = await _authHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw ApiException.fromStatusCode(response.statusCode, response.body);
  }

  Future<Map<String, dynamic>> get(String path) async {
    final headers = await _authHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw ApiException.fromStatusCode(response.statusCode, response.body);
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final headers = await _authHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw ApiException.fromStatusCode(response.statusCode, response.body);
  }

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    final headers = await _authHeaders();
    final response = await http.patch(
      Uri.parse('$baseUrl$path'),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw ApiException.fromStatusCode(response.statusCode, response.body);
  }

  Future<void> delete(String path) async {
    final headers = await _authHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl$path'),
      headers: headers,
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw ApiException.fromStatusCode(response.statusCode, response.body);
    }
  }

  Future<Map<String, dynamic>> postWithToken(
    String path,
    Map<String, dynamic> body,
    String token,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw ApiException.fromStatusCode(response.statusCode, response.body);
  }

  Future<List<dynamic>> getListWithToken(String path, String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw ApiException.fromStatusCode(response.statusCode, response.body);
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  factory ApiException.fromStatusCode(int statusCode, String body) {
    String message;
    try {
      final decoded = jsonDecode(body);
      message = decoded['detail'] ?? decoded['message'] ?? body;
    } catch (_) {
      message = body.isNotEmpty ? body : 'Unknown error';
    }
    return ApiException(statusCode, message);
  }

  @override
  String toString() => message;
}
