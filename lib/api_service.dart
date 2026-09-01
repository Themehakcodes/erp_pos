import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ApiService {
  static const String baseUrl = 'http://192.168.1.150:8080/api/v1';
  // Default timeout for all network calls — prevents any hanging
  static const Duration _timeout = Duration(seconds: 30);

  Future<Map<String, String>> getAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token') ?? '';
    final companyId = prefs.getString('company_id') ?? '';
    final fyId = prefs.getString('financial_year_id') ?? '';
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      if (companyId.isNotEmpty) 'X-Company-ID': companyId,
      if (fyId.isNotEmpty) 'X-Financial-Year-ID': fyId,
    };
  }

  Future<String> getDeviceIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('device_identifier');
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString('device_identifier', deviceId);
    }
    return deviceId;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim(), 'password': password}),
    ).timeout(const Duration(seconds: 20));

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body)['data'];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', data['token']['access_token']);
      await prefs.setString('user_id', data['user']['id']);
      await prefs.setString('user_name', data['user']['name'] ?? 'Cashier');
      await prefs.setString('company_id', data['user']['company_id']);
      return data;
    }
    throw Exception(_extractError(res.body));
  }

  Future<Map<String, dynamic>> checkTerminal(String deviceId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/terminals/device/$deviceId'),
      headers: await getAuthHeaders(),
    ).timeout(_timeout);
    if (res.statusCode == 200) {
      return jsonDecode(res.body)['data'];
    }
    throw Exception(_extractError(res.body));
  }

  Future<void> heartbeat() async {
    try {
      await http.post(
        Uri.parse('$baseUrl/auth/heartbeat'),
        headers: await getAuthHeaders(),
      ).timeout(const Duration(seconds: 10));
      await syncOfflineSales();
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> getActiveShift(String terminalId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/shifts/terminal/$terminalId/open'),
      headers: await getAuthHeaders(),
    ).timeout(_timeout);
    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      return decoded['data'];
    }
    if (res.statusCode == 401) {
      throw Exception('Session expired');
    }
    return null;
  }

  Future<Map<String, dynamic>> openShift(
      String storeId, String terminalId, double openingCash) async {
    final res = await http.post(
      Uri.parse('$baseUrl/shifts/open'),
      headers: await getAuthHeaders(),
      body: jsonEncode({
        'store_id': storeId,
        'terminal_id': terminalId,
        'opening_cash': openingCash,
        'opening_remarks': 'Flutter POS Start',
      }),
    ).timeout(_timeout);
    if (res.statusCode == 200 || res.statusCode == 201) {
      return jsonDecode(res.body)['data'];
    }
    throw Exception(_extractError(res.body));
  }

  Future<void> closeShift(String shiftId, double closingCash) async {
    final res = await http.post(
      Uri.parse('$baseUrl/shifts/$shiftId/close'),
      headers: await getAuthHeaders(),
      body: jsonEncode({'closing_cash': closingCash}),
    ).timeout(_timeout);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_extractError(res.body));
    }
  }

  Future<dynamic> getProducts({int page = 1, int limit = 100}) async {
    final prefs = await SharedPreferences.getInstance();
    final storeId = prefs.getString('store_id') ?? '';
    final res = await http.get(
      Uri.parse(
          '$baseUrl/pos/products/search?store_id=$storeId&page=$page&limit=$limit'),
      headers: await getAuthHeaders(),
    ).timeout(const Duration(seconds: 20));
    if (res.statusCode == 200) {
      return jsonDecode(res.body)['data'];
    }
    throw Exception(_extractError(res.body));
  }

  /// Returns the backend invoice_no or null if offline
  Future<String?> postSale(Map<String, dynamic> saleData) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/sales/'),
        headers: await getAuthHeaders(),
        body: jsonEncode(saleData),
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200 || res.statusCode == 201) {
        try {
          final body = jsonDecode(res.body);
          final data = body['data'];
          return data['invoice_no']?.toString() ??
              data['invoice_number']?.toString();
        } catch (_) {
          return null;
        }
      }
      throw Exception(_extractError(res.body));
    } catch (e) {
      if (e is TimeoutException ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup')) {
        await _saveSaleOffline(saleData);
        return null;
      }
      rethrow;
    }
  }

  Future<void> _saveSaleOffline(Map<String, dynamic> saleData) async {
    final prefs = await SharedPreferences.getInstance();
    final offlineSales = prefs.getStringList('offline_sales') ?? [];
    offlineSales.add(jsonEncode(saleData));
    await prefs.setStringList('offline_sales', offlineSales);
  }

  static bool _isSyncing = false;

  Future<void> syncOfflineSales() async {
    if (_isSyncing) return;
    
    final prefs = await SharedPreferences.getInstance();
    final offlineSales = prefs.getStringList('offline_sales') ?? [];
    if (offlineSales.isEmpty) return;

    _isSyncing = true;
    try {
      final List<String> failedSales = [];
      // Cache headers once instead of fetching from disk per sale
      final headers = await getAuthHeaders();
      
      for (var saleStr in offlineSales) {
        try {
          final res = await http.post(
            Uri.parse('$baseUrl/sales/'),
            headers: headers,
            body: saleStr,
          ).timeout(const Duration(seconds: 10)); // shorter timeout for background tasks

          if (res.statusCode != 200 && res.statusCode != 201) {
            failedSales.add(saleStr);
          }
        } catch (e) {
          failedSales.add(saleStr);
        }
        // Small delay between requests to prevent flooding the event loop
        await Future.delayed(const Duration(milliseconds: 100));
      }
      await prefs.setStringList('offline_sales', failedSales);
    } finally {
      _isSyncing = false;
    }
  }

  Future<List<dynamic>> getStores() async {
    final res = await http.get(
      Uri.parse('$baseUrl/stores'),
      headers: await getAuthHeaders(),
    ).timeout(_timeout);
    if (res.statusCode == 200) {
      return jsonDecode(res.body)['data'];
    }
    throw Exception(_extractError(res.body));
  }

  Future<String> getActiveFinancialYear() async {
    final res = await http.get(
      Uri.parse('$baseUrl/financial-years'),
      headers: await getAuthHeaders(),
    ).timeout(_timeout);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body)['data'] as List;
      for (var fy in data) {
        if (fy['is_current'] == true) {
          return fy['id'];
        }
      }
    }
    throw Exception('No active financial year found');
  }

  Future<void> registerTerminal(String storeId, String deviceId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/terminals'),
      headers: await getAuthHeaders(),
      body: jsonEncode({
        "store_id": storeId,
        "terminal_code": "POS-${deviceId.substring(0, 6)}",
        "terminal_name": "Tablet ${deviceId.substring(0, 6)}",
        "device_identifier": deviceId,
        "terminal_status": "active"
      }),
    ).timeout(_timeout);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_extractError(res.body));
    }
  }

  Future<void> updateTerminal(
      String terminalId, String storeId, String deviceId) async {
    final res = await http.put(
      Uri.parse('$baseUrl/terminals/$terminalId'),
      headers: await getAuthHeaders(),
      body: jsonEncode({
        "store_id": storeId,
        "terminal_code": "POS-${deviceId.substring(0, 6)}",
        "terminal_name": "Tablet ${deviceId.substring(0, 6)}",
        "device_identifier": deviceId,
        "terminal_status": "active"
      }),
    ).timeout(_timeout);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_extractError(res.body));
    }
  }

  Future<List<dynamic>> getPaymentMethods() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/payment-methods'),
        headers: await getAuthHeaders(),
      ).timeout(_timeout);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json['success'] == true && json['data'] != null) {
          return json['data'];
        }
      }
    } catch (_) {}
    return [];
  }

  String _extractError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded['error'] != null) {
        if (decoded['error'] is Map) {
          return decoded['error']['message'] ?? decoded['error'].toString();
        }
        return decoded['error'].toString();
      }
      if (decoded['message'] != null) return decoded['message'].toString();
      return body;
    } catch (e) {
      return body;
    }
  }
}
