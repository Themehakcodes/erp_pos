import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ApiService {
  static String baseUrl = 'http://192.168.1.150:8080/api/v1';
  // Default timeout for all network calls — prevents any hanging
  static const Duration _timeout = Duration(seconds: 30);

  static Future<void> initBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('api_base_url');
    if (saved != null && saved.isNotEmpty) {
      baseUrl = saved;
    }
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', url);
    baseUrl = url;
  }

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
    final storeParam = storeId.isNotEmpty ? '&store_id=$storeId' : '';
    final res = await http.get(
      Uri.parse('$baseUrl/pos/products/search?page=$page&limit=$limit$storeParam'),
      headers: await getAuthHeaders(),
    ).timeout(const Duration(seconds: 20));
    if (res.statusCode == 200) {
      return jsonDecode(res.body)['data'];
    }
    throw Exception(_extractError(res.body));
  }

  /// Searches products matching name, barcode, or SKU with fallback to catalog
  Future<List<Map<String, dynamic>>> searchProducts(String query, {int limit = 50, int page = 1}) async {
    final cleanQuery = query.trim();
    final prefs = await SharedPreferences.getInstance();
    final storeId = prefs.getString('store_id') ?? '';
    final headers = await getAuthHeaders();
    final storeParam = storeId.isNotEmpty ? '&store_id=$storeId' : '';

    List<Map<String, dynamic>> parseList(dynamic rawData) {
      if (rawData == null) return [];
      if (rawData is List) {
        return rawData.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
      if (rawData is Map) {
        if (rawData['data'] is List) {
          return (rawData['data'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
        if (rawData['items'] is List) {
          return (rawData['items'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
      return [];
    }

    // 1. First search active POS products
    try {
      final qParam = cleanQuery.isNotEmpty ? '&search=${Uri.encodeComponent(cleanQuery)}' : '';
      final url = '$baseUrl/pos/products/search?limit=$limit&page=$page&ignore_code=true$storeParam$qParam';
      final res = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final list = parseList(decoded['data']);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    // 2. Fallback to full master product catalog (in case store stock is 0 or unassigned)
    try {
      final qParam = cleanQuery.isNotEmpty ? '&search=${Uri.encodeComponent(cleanQuery)}' : '';
      final url = '$baseUrl/products?limit=$limit&page=$page$storeParam$qParam';
      final res = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final list = parseList(decoded['data']);
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    return [];
  }

  /// Looks up a product by exact barcode, SKU/code, or query with full catalog fallbacks
  Future<Map<String, dynamic>?> getProductByBarcode(String barcode) async {
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final storeId = prefs.getString('store_id') ?? '';
    final headers = await getAuthHeaders();
    final storeParam = storeId.isNotEmpty ? '?store_id=$storeId' : '';
    final lowerTarget = cleanBarcode.toLowerCase();

    bool isExactMatch(Map<String, dynamic> item) {
      final b = (item['stock_barcode'] ?? item['barcode'] ?? '').toString().trim().toLowerCase();
      final c = (item['product_code'] ?? item['sku'] ?? '').toString().trim().toLowerCase();
      if (b == lowerTarget || c == lowerTarget) return true;

      if (item['stocks'] is List) {
        for (final s in (item['stocks'] as List)) {
          if (s is Map) {
            // Only match barcodes that belong to THIS store
            final sStore = (s['store_id'] ?? s['storeId'] ?? '').toString().trim().toLowerCase();
            if (storeId.isNotEmpty && sStore.isNotEmpty && sStore != storeId.toLowerCase()) {
              continue;
            }
            final sb = (s['stock_barcode'] ?? '').toString().trim().toLowerCase();
            if (sb == lowerTarget) return true;
          }
        }
      }
      return false;
    }

    // 1. Try dedicated barcode endpoint
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/pos/products/barcode/${Uri.encodeComponent(cleanBarcode)}$storeParam'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final data = decoded['data'];
        if (data is Map<String, dynamic>) {
          if (data['data'] is List && (data['data'] as List).isNotEmpty) {
            final list = (data['data'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
            final exact = list.firstWhere((it) => isExactMatch(it), orElse: () => list.first);
            return exact;
          }
          return data;
        } else if (data is List && data.isNotEmpty) {
          final list = data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          final exact = list.firstWhere((it) => isExactMatch(it), orElse: () => list.first);
          return exact;
        }
      }
    } catch (_) {}

    // 2. Search POS products and look for exact barcode or code match
    final posResults = await searchProducts(cleanBarcode, limit: 20);
    for (final it in posResults) {
      if (isExactMatch(it)) return it;
    }
    if (posResults.isNotEmpty) {
      return posResults.first;
    }

    // 3. Fallback to master catalog for exact barcode lookup
    try {
      final storeParamAmp = storeId.isNotEmpty ? '&store_id=$storeId' : '';
      final res = await http.get(
        Uri.parse('$baseUrl/products?search=${Uri.encodeComponent(cleanBarcode)}&limit=10&page=1$storeParamAmp'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final data = decoded['data'];
        List<Map<String, dynamic>> list = [];
        if (data is Map && data['data'] is List) {
          list = (data['data'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        } else if (data is List) {
          list = data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
        for (final it in list) {
          if (isExactMatch(it)) return it;
        }
        if (list.isNotEmpty) return list.first;
      }
    } catch (_) {}

    return null;
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
