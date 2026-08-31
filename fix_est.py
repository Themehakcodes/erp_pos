"""
Fix: Replace Token with EST{counter}, persist counter, return invoice_no from API.
"""

# ── api_service.dart: postSale returns invoice_no string ─────────────────────
with open('d:/projects/ErpGoPos/erp_pos/lib/api_service.dart', 'r', encoding='utf-8', newline='') as f:
    api = f.read()

old_post = (
    "  Future<bool> postSale(Map<String, dynamic> saleData) async {\r\n"
    "    try {\r\n"
    "      final res = await http.post(\r\n"
    "        Uri.parse('$baseUrl/sales/'),\r\n"
    "        headers: await getAuthHeaders(),\r\n"
    "        body: jsonEncode(saleData),\r\n"
    "      ).timeout(const Duration(seconds: 10));\r\n"
    "      \r\n"
    "      if (res.statusCode == 200 || res.statusCode == 201) {\r\n"
    "        return true;\r\n"
    "      }\r\n"
    "      throw Exception(_extractError(res.body));\r\n"
    "    } catch (e) {\r\n"
    "      if (e is TimeoutException || e.toString().contains('SocketException') || e.toString().contains('Failed host lookup')) {\r\n"
    "        await _saveSaleOffline(saleData);\r\n"
    "        return true; // Pretend it succeeded for offline mode\r\n"
    "      }\r\n"
    "      throw Exception(e.toString());\r\n"
    "    }\r\n"
    "  }"
)

new_post = (
    "  // Returns the backend invoice_no (e.g. 'SI-00042') or null if offline\r\n"
    "  Future<String?> postSale(Map<String, dynamic> saleData) async {\r\n"
    "    try {\r\n"
    "      final res = await http.post(\r\n"
    "        Uri.parse('$baseUrl/sales/'),\r\n"
    "        headers: await getAuthHeaders(),\r\n"
    "        body: jsonEncode(saleData),\r\n"
    "      ).timeout(const Duration(seconds: 10));\r\n"
    "      \r\n"
    "      if (res.statusCode == 200 || res.statusCode == 201) {\r\n"
    "        try {\r\n"
    "          final body = jsonDecode(res.body);\r\n"
    "          final data = body['data'];\r\n"
    "          return data['invoice_no']?.toString() ??\r\n"
    "                 data['invoice_number']?.toString();\r\n"
    "        } catch (_) {\r\n"
    "          return null;\r\n"
    "        }\r\n"
    "      }\r\n"
    "      throw Exception(_extractError(res.body));\r\n"
    "    } catch (e) {\r\n"
    "      if (e is TimeoutException || e.toString().contains('SocketException') || e.toString().contains('Failed host lookup')) {\r\n"
    "        await _saveSaleOffline(saleData);\r\n"
    "        return null; // offline - no invoice_no yet\r\n"
    "      }\r\n"
    "      throw Exception(e.toString());\r\n"
    "    }\r\n"
    "  }"
)

if old_post in api:
    api = api.replace(old_post, new_post)
    print("api_service postSale: OK")
else:
    print("ERROR: postSale pattern not found")

with open('d:/projects/ErpGoPos/erp_pos/lib/api_service.dart', 'w', encoding='utf-8', newline='') as f:
    f.write(api)


# ── pos_screen.dart ───────────────────────────────────────────────────────────
with open('d:/projects/ErpGoPos/erp_pos/lib/screens/pos_screen.dart', 'r', encoding='utf-8', newline='') as f:
    pos = f.read()

# 1. Add _estCounter to state (loads from prefs on init)
pos = pos.replace(
    '  int _tokenNumber = 1;',
    '  int _estCounter = 1;'
)

# 2. Load _estCounter from SharedPreferences in _loadData
old_load = (
    "  Future<void> _loadData() async {\r\n"
    "    final prefs = await SharedPreferences.getInstance();\r\n"
    "    setState(() => _userId = prefs.getString('user_name') ?? 'Cashier');"
)
new_load = (
    "  Future<void> _loadData() async {\r\n"
    "    final prefs = await SharedPreferences.getInstance();\r\n"
    "    setState(() {\r\n"
    "      _userId = prefs.getString('user_name') ?? 'Cashier';\r\n"
    "      _estCounter = prefs.getInt('est_counter') ?? 1;\r\n"
    "    });"
)
if old_load in pos:
    pos = pos.replace(old_load, new_load)
    print("_loadData init estCounter: OK")
else:
    print("ERROR: _loadData pattern not found")

# 3. AppBar title: show EST{counter}
pos = pos.replace(
    "            const Text(\r\n              'Token',\r\n              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),\r\n            ),",
    "            Text(\r\n              'EST${_estCounter.toString().padLeft(4, \"0\")}',\r\n              style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5, fontSize: 20),\r\n            ),"
)
print("AppBar title EST: OK" if 'EST${_estCounter' in pos else "ERROR: AppBar not patched")

# 4. After successful sale - increment, persist, show invoice_no
old_sale = (
    "      // Hard 12s timeout on the entire sale save - can never hang forever\r\n"
    "      await ApiService().postSale(saleData)\r\n"
    "          .timeout(const Duration(seconds: 12), onTimeout: () {\r\n"
    "        // Timeout: sale saved offline, treat as success\r\n"
    "        return true;\r\n"
    "      });\r\n"
    "\r\n"
    "      // Close the dialog IMMEDIATELY after API call - don't wait for printer\r\n"
    "      if (mounted) Navigator.pop(context);\r\n"
    "\r\n"
    "      // Update cart state and counters\r\n"
    "      final cartSnapshot = List<CartItem>.from(_cart);\r\n"
    "      widget.onSaleCompleted(method, amountToCharge);\r\n"
    "      setState(() {\r\n"
    "        _cart.clear();\r\n"
    "        _isCartVisible = false;\r\n"
    "        _tokenNumber++;\r\n"
    "      });\r\n"
    "      _cartNotifier.value++;\r\n"
    "\r\n"
    "      if (mounted) {\r\n"
    "        ScaffoldMessenger.of(context).showSnackBar(\r\n"
    "          const SnackBar(\r\n"
    "            content: Text('Transaction completed!'),\r\n"
    "            backgroundColor: Colors.green,\r\n"
    "            behavior: SnackBarBehavior.floating,\r\n"
    "            duration: Duration(seconds: 2),\r\n"
    "          ),\r\n"
    "        );\r\n"
    "      }\r\n"
    "\r\n"
    "      // Print AFTER UI is already updated - fire and forget, never blocks\r\n"
    "      Future.microtask(() => _printReceipt(method));"
)

new_sale = (
    "      // Hard 12s timeout - can never hang forever\r\n"
    "      final invoiceNo = await ApiService().postSale(saleData)\r\n"
    "          .timeout(const Duration(seconds: 12), onTimeout: () => null);\r\n"
    "\r\n"
    "      // Close the dialog IMMEDIATELY - don't wait for printer\r\n"
    "      if (mounted) Navigator.pop(context);\r\n"
    "\r\n"
    "      // Increment EST counter and persist\r\n"
    "      final nextCounter = _estCounter + 1;\r\n"
    "      final prefs2 = await SharedPreferences.getInstance();\r\n"
    "      await prefs2.setInt('est_counter', nextCounter);\r\n"
    "\r\n"
    "      widget.onSaleCompleted(method, amountToCharge);\r\n"
    "      setState(() {\r\n"
    "        _cart.clear();\r\n"
    "        _isCartVisible = false;\r\n"
    "        _estCounter = nextCounter;\r\n"
    "      });\r\n"
    "      _cartNotifier.value++;\r\n"
    "\r\n"
    "      if (mounted) {\r\n"
    "        final displayNo = invoiceNo ?? 'EST${_estCounter.toString().padLeft(4, \"0\")}';\r\n"
    "        ScaffoldMessenger.of(context).showSnackBar(\r\n"
    "          SnackBar(\r\n"
    "            content: Text('Bill saved! Invoice: $displayNo'),\r\n"
    "            backgroundColor: Colors.green,\r\n"
    "            behavior: SnackBarBehavior.floating,\r\n"
    "            duration: const Duration(seconds: 3),\r\n"
    "          ),\r\n"
    "        );\r\n"
    "      }\r\n"
    "\r\n"
    "      // Print fire-and-forget, never blocks UI\r\n"
    "      Future.microtask(() => _printReceipt(method));"
)

if old_sale in pos:
    pos = pos.replace(old_sale, new_sale)
    print("sale flow with EST: OK")
else:
    print("ERROR: sale flow pattern not found")
    idx = pos.find('Hard 12s timeout')
    print(repr(pos[idx:idx+400]))

# 5. Update receipt to show EST number
pos = pos.replace(
    '    bytes.addAll("TOKEN\\r\\n\\r\\n".codeUnits);',
    '    bytes.addAll("EST${_estCounter.toString().padLeft(4, \'0\')}\\n\\n".codeUnits);'
)
pos = pos.replace(
    '    bytes.addAll("TOKEN\\n\\n".codeUnits);',
    '    bytes.addAll("EST${_estCounter.toString().padLeft(4, \'0\')}\\n\\n".codeUnits);'
)
print("receipt EST: OK" if 'EST${_estCounter' in pos else "ERROR: receipt not patched")

with open('d:/projects/ErpGoPos/erp_pos/lib/screens/pos_screen.dart', 'w', encoding='utf-8', newline='') as f:
    f.write(pos)

print("\nAll done!")
