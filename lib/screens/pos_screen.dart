import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import '../api_service.dart';
import '../models/models.dart';
import '../printer_helper.dart';
import 'bill_history_screen.dart';
import 'login_screen.dart';

class PosScreen extends StatefulWidget {
  final Function(String method, double amount) onSaleCompleted;
  final SelectedPrinter? selectedPrinter;

  const PosScreen({
    super.key,
    required this.onSaleCompleted,
    this.selectedPrinter,
  });

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final List<CartItem> _cart = [];
  final ValueNotifier<int> _cartNotifier = ValueNotifier<int>(0);
  List<Product> _products = [];
  List<Product> _displayedProducts = [];
  bool _isLoading = true;
  bool _isCartVisible = true;
  String _userId = "Cashier";
  int _estCounter = 1;
  bool _isProcessing = false; // guard against double-tap checkout
  bool _isBottomSheetOpen = false;

  // Real-time Search & Barcode Scanner Controllers
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _searchDebounceTimer;
  bool _isSearchingBackend = false;
  String _lastScannedBarcode = '';
  DateTime _lastScanTime = DateTime.fromMillisecondsSinceEpoch(0);
  int _offlineCount = 0;
  String? _currentShiftId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _cartNotifier.dispose();
    super.dispose();
  }

  Future<void> _updateOfflineCount() async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getStringList('offline_sales') ?? []).length;
    if (mounted && _offlineCount != count) {
      setState(() => _offlineCount = count);
    }
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final storeId = prefs.getString('store_id') ?? '';
    _currentShiftId = prefs.getString('shift_id');
    _updateOfflineCount();
    setState(() {
      _userId = prefs.getString('user_name') ?? 'Cashier';
      _estCounter = prefs.getInt('est_counter') ?? 1;
    });
    try {
      final dynamic data = await ApiService().getProducts(limit: 200);
      List itemsList = [];
      if (data is List) {
        itemsList = data;
      } else if (data is Map) {
        if (data['items'] != null) {
          itemsList = data['items'];
        } else if (data['products'] != null) {
          itemsList = data['products'];
        } else if (data['data'] != null) {
          itemsList = data['data'];
        }
      }
      final parsed = itemsList
          .map(
            (e) => Product.fromJson(
              e as Map<String, dynamic>,
              targetStoreId: storeId,
            ),
          )
          .toList();
      setState(() {
        _products = parsed;
        _displayedProducts = parsed;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounceTimer?.cancel();
    final cleanQuery = query.trim().toLowerCase();

    if (cleanQuery.isEmpty) {
      setState(() {
        _displayedProducts = _products;
      });
      return;
    }

    // 1. Instant local filter
    final localMatches = _products.where((p) {
      return p.name.toLowerCase().contains(cleanQuery) ||
          p.barcode.toLowerCase().contains(cleanQuery) ||
          p.productCode.toLowerCase().contains(cleanQuery);
    }).toList();

    setState(() {
      _displayedProducts = localMatches;
    });

    // 2. Debounced query to backend if >= 2 characters to discover full catalog
    if (cleanQuery.length >= 2) {
      _searchDebounceTimer = Timer(const Duration(milliseconds: 350), () async {
        if (!mounted || cleanQuery.isEmpty) return;
        try {
          setState(() => _isSearchingBackend = true);
          final results = await ApiService().searchProducts(cleanQuery, limit: 30);
          if (!mounted) return;
          final prefs = await SharedPreferences.getInstance();
          final storeId = prefs.getString('store_id') ?? '';
          final remoteProducts = results
              .map((e) => Product.fromJson(e, targetStoreId: storeId))
              .toList();

          final existingIds = localMatches.map((p) => p.id).toSet();
          final combined = List<Product>.from(localMatches);
          for (final rp in remoteProducts) {
            if (!existingIds.contains(rp.id)) {
              combined.add(rp);
              existingIds.add(rp.id);
            }
          }

          if (mounted && _searchCtrl.text.trim().toLowerCase() == cleanQuery) {
            setState(() {
              _displayedProducts = combined;
              _isSearchingBackend = false;
            });
          }
        } catch (_) {
          if (mounted) setState(() => _isSearchingBackend = false);
        }
      });
    }
  }

  Future<void> _handleBarcodeScan(String rawBarcode) async {
    final barcode = rawBarcode.trim();
    if (barcode.isEmpty) return;

    // Deduplicate rapid barcode scanner bounces (within 350ms)
    final now = DateTime.now();
    if (_lastScannedBarcode == barcode &&
        now.difference(_lastScanTime).inMilliseconds < 350) {
      return;
    }
    _lastScannedBarcode = barcode;
    _lastScanTime = now;

    // 1. Check in already loaded products
    final lower = barcode.toLowerCase();
    Product? found;
    for (final p in _products) {
      if (p.barcode.toLowerCase() == lower || p.productCode.toLowerCase() == lower) {
        found = p;
        break;
      }
      for (final s in p.stocks) {
        if ((s['stock_barcode'] ?? '').toString().toLowerCase() == lower) {
          found = p.copyWithBatch(s);
          break;
        }
      }
      if (found != null) break;
    }

    if (found != null) {
      _addToCart(found);
      HapticFeedback.lightImpact();
      _searchCtrl.clear();
      setState(() => _displayedProducts = _products);
      if (mounted) {
        _searchFocus.unfocus();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "${found.name}" to cart'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // 2. Fetch from backend via dedicated barcode lookup
    try {
      final data = await ApiService().getProductByBarcode(barcode);
      if (data != null) {
        final prefs = await SharedPreferences.getInstance();
        final storeId = prefs.getString('store_id') ?? '';
        final newProduct = Product.fromJson(data, targetStoreId: storeId);

        if (!_products.any((p) => p.id == newProduct.id)) {
          _products.add(newProduct);
        }

        _addToCart(newProduct);
        HapticFeedback.lightImpact();
        _searchCtrl.clear();
        setState(() => _displayedProducts = _products);
        if (mounted) {
          _searchFocus.unfocus();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added "${newProduct.name}" to cart'),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Product not found for barcode: $barcode'),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _searchCtrl.clear();
      _searchFocus.unfocus();
    }
  }

  void _openCameraScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _PosCameraScannerSheet(
        onBarcodeDetected: (scanned) {
          Navigator.pop(ctx);
          _handleBarcodeScan(scanned);
        },
      ),
    );
  }

  void _clearCart() {
    if (_cart.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Clear Order?'),
          ],
        ),
        content: const Text(
          'Are you sure you want to remove all items from this order?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _cart.clear());
              _cartNotifier.value++;
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('shift_id');
    await prefs.remove('terminal_id');
    await prefs.remove('store_id');
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  void _addToCart(Product p) {
    final index = _cart.indexWhere((item) => item.product.id == p.id);
    if (index >= 0) {
      _increment(index);
    } else {
      setState(() => _cart.add(CartItem(p, 1)));
      _cartNotifier.value++;
    }
  }

  void _increment(int index) {
    setState(() {
      _cart[index].quantity++;
    });
    _cartNotifier.value++;
  }

  void _decrement(int index) {
    if (_cart[index].quantity > 1) {
      setState(() {
        _cart[index].quantity--;
      });
    } else {
      setState(() {
        _cart.removeAt(index);
      });
    }
    _cartNotifier.value++;
  }

  void _setQuantity(int index, int newQty) {
    if (newQty > 0) {
      setState(() {
        _cart[index].quantity = newQty;
      });
      _cartNotifier.value++;
    }
  }

  double get _subtotal {
    final sum = _cart.fold(
      0.0,
      (acc, item) => acc + (item.product.price * item.quantity),
    );
    return double.parse(sum.toStringAsFixed(2));
  }

  double get _roundOffAmount {
    if (_cart.isEmpty) return 0.0;
    final rounded = _subtotal.roundToDouble();
    return double.parse((rounded - _subtotal).toStringAsFixed(2));
  }

  double get _totalAmount {
    if (_cart.isEmpty) return 0.0;
    return _subtotal.roundToDouble();
  }

  Widget _buildQuantityButton({
    required IconData icon,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: iconColor),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      color: const Color(0xFFF5F7FA),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          autofocus: false,
          onChanged: _onSearchChanged,
          onSubmitted: _handleBarcodeScan,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Scan Barcode or Search Products (Name / Code)...',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: Icon(
              Icons.qr_code_scanner,
              color: Theme.of(context).colorScheme.primary,
            ),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isSearchingBackend)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                if (_searchCtrl.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                    onPressed: () {
                      _searchCtrl.clear();
                      _onSearchChanged('');
                      _searchFocus.unfocus();
                      FocusScope.of(context).unfocus();
                    },
                  ),
                IconButton(
                  icon: const Icon(
                    Icons.camera_alt_outlined,
                    color: Colors.blue,
                  ),
                  tooltip: 'Camera Barcode Scanner',
                  onPressed: _openCameraScanner,
                ),
              ],
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductSection({bool isMobile = false}) {
    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: _buildProductGrid(bottomPadding: isMobile ? 90.0 : 24.0),
        ),
      ],
    );
  }

  Widget _buildProductGrid({double bottomPadding = 24.0}) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 3),
            const SizedBox(height: 16),
            Text(
              'Fetching Products...',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    if (_displayedProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _searchCtrl.text.isNotEmpty
                  ? Icons.search_off_rounded
                  : Icons.inventory_2_outlined,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              _searchCtrl.text.isNotEmpty
                  ? 'No products matching "${_searchCtrl.text}"'
                  : 'No products available.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (_searchCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  _searchCtrl.clear();
                  _onSearchChanged('');
                },
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('Clear Search'),
              ),
            ],
          ],
        ),
      );
    }
    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = 4;
    if (screenWidth < 600) {
      crossAxisCount = 2;
    } else if (screenWidth < 900) {
      crossAxisCount = 3;
    }

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(24, 8, 24, bottomPadding),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: screenWidth < 600 ? 0.75 : 0.8,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: _displayedProducts.length,
      itemBuilder: (context, index) {
        final p = _displayedProducts[index];
        final List<Color> colors = [
          Colors.blue.shade50,
          Colors.purple.shade50,
          Colors.orange.shade50,
          Colors.teal.shade50,
          Colors.pink.shade50,
          Colors.indigo.shade50,
          Colors.green.shade50,
          Colors.amber.shade50,
        ];
        final List<Color> iconColors = [
          Colors.blue.shade400,
          Colors.purple.shade400,
          Colors.orange.shade400,
          Colors.teal.shade400,
          Colors.pink.shade400,
          Colors.indigo.shade400,
          Colors.green.shade400,
          Colors.amber.shade400,
        ];

        final bgColor = colors[index % colors.length];
        final iconColor = iconColors[index % iconColors.length];

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 15,
                offset: Offset(0, 8),
              ),
            ],
            border: Border.all(color: Colors.grey.shade100, width: 1.5),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: () => _addToCart(p),
              borderRadius: BorderRadius.circular(20),
              splashColor: iconColor.withValues(alpha: 0.2),
              highlightColor: iconColor.withValues(alpha: 0.1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: Container(
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(18),
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.shopping_bag_outlined,
                          size: 48,
                          color: iconColor,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              p.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                letterSpacing: -0.3,
                                color: Colors.black87,
                                height: 1.1,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '₹${p.price.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showNumpadDialog(int index) async {
    int currentQty = _cart[index].quantity;
    String input = currentQty.toString();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void onKey(String val) {
              setDialogState(() {
                if (val == 'C') {
                  input = "";
                } else if (val == '<') {
                  if (input.isNotEmpty) {
                    input = input.substring(0, input.length - 1);
                  }
                } else {
                  if (input.length < 5) {
                    input += val;
                  }
                }
              });
            }

            Widget buildKey(String val) {
              return Expanded(
                child: InkWell(
                  onTap: () => onKey(val),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      val == '<' ? '⌫' : val,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: (val == 'C' || val == '<')
                            ? FontWeight.normal
                            : FontWeight.bold,
                        color: val == 'C' ? Colors.redAccent : Colors.black87,
                      ),
                    ),
                  ),
                ),
              );
            }

            return AlertDialog(
              title: const Text('Enter Quantity'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.blue),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      input.isEmpty ? '0' : input,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Column(
                    children: [
                      Row(
                        children: [buildKey('1'), buildKey('2'), buildKey('3')],
                      ),
                      Row(
                        children: [buildKey('4'), buildKey('5'), buildKey('6')],
                      ),
                      Row(
                        children: [buildKey('7'), buildKey('8'), buildKey('9')],
                      ),
                      Row(
                        children: [buildKey('C'), buildKey('0'), buildKey('<')],
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    int parsed = int.tryParse(input) ?? 0;
                    if (parsed > 0) {
                      _setQuantity(index, parsed);
                    }
                    Navigator.pop(context);
                  },
                  child: const Text('Set'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _ensureShiftIsOpen() async {
    final prefs = await SharedPreferences.getInstance();
    var shiftId = prefs.getString('shift_id');
    if (shiftId != null && shiftId.isNotEmpty) {
      if (_currentShiftId != shiftId) {
        setState(() => _currentShiftId = shiftId);
      }
      return true;
    }

    // Check if backend has an open shift for this terminal
    final terminalId = prefs.getString('terminal_id');
    if (terminalId != null && terminalId.isNotEmpty) {
      try {
        final activeShift = await ApiService().getActiveShift(terminalId);
        if (activeShift != null && activeShift['id'] != null) {
          shiftId = activeShift['id'].toString();
          await prefs.setString('shift_id', shiftId);
          if (mounted) {
            setState(() => _currentShiftId = shiftId);
          }
          return true;
        }
      } catch (_) {}
    }

    // No active shift found -> Prompt cashier to open shift before billing
    if (!mounted) return false;
    return await _showOpenShiftDialog(isMandatoryForCheckout: true);
  }

  Future<bool> _showOpenShiftDialog({
    bool isMandatoryForCheckout = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final storeId = prefs.getString('store_id');
    final terminalId = prefs.getString('terminal_id');

    if (storeId == null || terminalId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Terminal not configured. Please check settings.'),
          ),
        );
      }
      return false;
    }

    final txt = TextEditingController(text: '0.00');
    bool isSubmitting = false;

    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: !isMandatoryForCheckout,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.lock_open,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Open Shift',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isMandatoryForCheckout)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange.shade900,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Please open a shift before completing this bill.',
                              style: TextStyle(
                                color: Colors.orange.shade900,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Text(
                    'Opening Cash In Drawer (Rs)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: txt,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.currency_rupee),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.pop(dialogCtx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          final balance = double.tryParse(txt.text) ?? 0.0;
                          try {
                            final existingShift = await ApiService()
                                .getActiveShift(terminalId);
                            if (existingShift != null) {
                              final sId = existingShift['id'].toString();
                              await prefs.setString('shift_id', sId);
                              if (mounted) {
                                setState(() => _currentShiftId = sId);
                              }
                              if (dialogCtx.mounted) {
                                Navigator.pop(dialogCtx, true);
                              }
                              return;
                            }

                            final shift = await ApiService().openShift(
                              storeId,
                              terminalId,
                              balance,
                            );
                            final sId = shift['id'].toString();
                            await prefs.setString('shift_id', sId);
                            if (mounted) {
                              setState(() => _currentShiftId = sId);
                            }

                            try {
                              await PrinterHelper.printShiftReceipt(
                                widget.selectedPrinter,
                                true,
                                balance,
                                storeId,
                                terminalId,
                              );
                            } catch (e) {
                              debugPrint('Error printing open receipt: $e');
                            }

                            if (dialogCtx.mounted) {
                              Navigator.pop(dialogCtx, true);
                            }
                          } catch (e) {
                            if (dialogCtx.mounted) {
                              setDialogState(() => isSubmitting = false);
                              ScaffoldMessenger.of(dialogCtx).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to open shift: $e'),
                                ),
                              );
                            }
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Confirm Open Shift'),
                ),
              ],
            );
          },
        );
      },
    );

    return result ?? false;
  }

  void _checkout() async {
    if (_isProcessing || _cart.isEmpty) return; // block if already processing or empty

    // Automatically ensure shift is open before completing any bill
    final isShiftOpen = await _ensureShiftIsOpen();
    if (!isShiftOpen) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: !_isProcessing,
      builder: (context) {
        return SplitPaymentDialog(
          totalAmount: _totalAmount,
          subtotal: _subtotal,
          roundOff: _roundOffAmount,
          onConfirm: (cash, upi) {
            Navigator.pop(context);
            _processSplitPayment(cash, upi);
          },
        );
      },
    );
  }

  Future<void> _processSplitPayment(double cashAmount, double upiAmount) async {
    if (_isProcessing) return; // prevent double-tap duplicate bills
    setState(() => _isProcessing = true);
    final subtotal = _subtotal;
    final roundOff = _roundOffAmount;
    final amountToCharge = _totalAmount;

    String method = '';
    if (cashAmount > 0 && upiAmount > 0) {
      method = 'Split (Cash & UPI)';
    } else if (cashAmount > 0) {
      method = 'Cash';
    } else {
      method = 'UPI';
    }

    final clientSaleId = const Uuid().v4();
    final currentEstNo = 'EST${_estCounter.toString().padLeft(4, "0")}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: const Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 24),
            Text('Processing Payment...', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
    await Future.delayed(
      const Duration(milliseconds: 100),
    ); // allow UI to render loading modal

    try {
      final prefs = await SharedPreferences.getInstance();
      final storeId = prefs.getString('store_id');
      final shiftId = prefs.getString('shift_id');
      final financialYearId = prefs.getString('financial_year_id');

      // Dynamically fetch Payment Methods to ensure valid UUIDs for the Tenant
      final paymentMethods = await ApiService().getPaymentMethods();
      String cashId =
          "e0000000-0000-0000-0000-000000000001"; // Fallbacks just in case
      String upiId = "e0000000-0000-0000-0000-000000000003";

      if (paymentMethods.isNotEmpty) {
        final cashMethod = paymentMethods.firstWhere(
          (p) => p['method_name'].toString().toLowerCase().contains('cash'),
          orElse: () => paymentMethods.first,
        );
        final upiMethod = paymentMethods.firstWhere(
          (p) => p['method_name'].toString().toLowerCase().contains('upi'),
          orElse: () => cashMethod,
        );
        cashId = cashMethod['id'];
        upiId = upiMethod['id'];
      }

      final items = _cart
          .map(
            (c) => {
              "product_id": c.product.id,
              "product_stock_id": c.product.stockId.isEmpty
                  ? "00000000-0000-0000-0000-000000000000"
                  : c.product.stockId,
              "product_name": c.product.name,
              "barcode": c.product.barcode,
              "hsn_code": "",
              "quantity": c.quantity,
              "mrp": c.product.price,
              "sale_rate": c.product.price,
              "cost_price": c.product.price,
              "taxable_amount": double.parse(
                (c.product.price * c.quantity).toStringAsFixed(2),
              ),
              "cgst_percent": 0.0,
              "cgst_amount": 0.0,
              "sgst_percent": 0.0,
              "sgst_amount": 0.0,
              "igst_percent": 0.0,
              "igst_amount": 0.0,
              "tax_amount": 0.0,
              "line_total": double.parse(
                (c.product.price * c.quantity).toStringAsFixed(2),
              ),
            },
          )
          .toList();

      final saleData = {
        "client_sale_id": clientSaleId,
        "offline_invoice_no": currentEstNo,
        "store_id": storeId,
        "shift_id": shiftId,
        "financial_year_id": financialYearId,
        "invoice_date": DateTime.now().toUtc().toIso8601String(),
        "invoice_status": "completed",
        "bill_type": "pos",
        "is_gst_bill": false,
        "total_items": _cart.length,
        "total_quantity": _cart.fold(0.0, (sum, item) => sum + item.quantity),
        "subtotal_amount": subtotal,
        "discount_amount": 0.0,
        "taxable_amount": subtotal,
        "cgst_amount": 0.0,
        "sgst_amount": 0.0,
        "igst_amount": 0.0,
        "round_off_amount": roundOff,
        "net_amount": amountToCharge,
        "gross_profit_amount": 0.0,
        "remarks": "Flutter POS Terminal",
        "items": items,
        "payments": [
          if (cashAmount > 0)
            {
              "payment_method_id": cashId,
              "amount_received": cashAmount,
              "amount_applied": cashAmount,
              "change_returned": 0.0,
              "amount": cashAmount,
              "reference_number": "",
            },
          if (upiAmount > 0)
            {
              "payment_method_id": upiId,
              "amount_received": upiAmount,
              "amount_applied": upiAmount,
              "change_returned": 0.0,
              "amount": upiAmount,
              "reference_number": "",
            },
        ],
      };

      // Hard 12s timeout - can never hang forever
      final invoiceNo = await ApiService()
          .postSale(saleData)
          .timeout(const Duration(seconds: 12), onTimeout: () => null);

      // Close the dialog IMMEDIATELY - don't wait for printer
      if (mounted) Navigator.pop(context);

      // Determine the final invoice number to display and print
      final displayNo = invoiceNo ?? currentEstNo;

      // Increment EST counter and persist
      final nextCounter = _estCounter + 1;
      final prefs2 = await SharedPreferences.getInstance();
      await prefs2.setInt('est_counter', nextCounter);

      final cartSnapshot = List<CartItem>.from(_cart);

      final billRecord = BillReceiptData(
        id: clientSaleId,
        invoiceNo: displayNo,
        dateStr: DateTime.now().toString().substring(0, 16),
        items: cartSnapshot
            .map(
              (c) => BillReceiptItem(
                name: c.product.name,
                quantity: c.quantity.toDouble(),
                price: c.product.price,
                lineTotal: double.parse(
                  (c.product.price * c.quantity).toStringAsFixed(2),
                ),
              ),
            )
            .toList(),
        subtotal: subtotal,
        roundOff: roundOff,
        totalAmount: amountToCharge,
        method: method,
        isOffline: (invoiceNo == null),
        shiftId: shiftId ?? '',
      );

      // Save to local shift history cache so ANY bill can be reprinted anytime
      unawaited(ApiService.saveBillToLocalShiftHistory(billRecord));

      widget.onSaleCompleted(method, amountToCharge);
      if (mounted && _isBottomSheetOpen) {
        Navigator.pop(context);
        _isBottomSheetOpen = false;
      }

      setState(() {
        _cart.clear();
        _isCartVisible = false;
        _estCounter = nextCounter;
      });
      _cartNotifier.value++;
      _updateOfflineCount();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bill saved! Invoice: $displayNo'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // Print asynchronously after UI has completely updated and rendered
      Future.delayed(
        const Duration(milliseconds: 500),
        () => _printReceipt(
          method,
          cartSnapshot,
          amountToCharge,
          displayNo,
          billRecord: billRecord,
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed: ${e.toString().replaceAll("Exception: ", "")}',
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            margin: const EdgeInsets.only(bottom: 600, left: 16, right: 16),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _printReceipt(
    String method,
    List<CartItem> cartSnapshot,
    double totalAmount,
    String invoiceNo, {
    BillReceiptData? billRecord,
  }) async {
    final record =
        billRecord ??
        BillReceiptData(
          invoiceNo: invoiceNo,
          dateStr: DateTime.now().toString().substring(0, 16),
          items: cartSnapshot
              .map(
                (c) => BillReceiptItem(
                  name: c.product.name,
                  quantity: c.quantity.toDouble(),
                  price: c.product.price,
                  lineTotal: c.product.price * c.quantity,
                ),
              )
              .toList(),
          totalAmount: totalAmount,
          method: method,
        );

    await PrinterHelper.printBillReceipt(
      widget.selectedPrinter,
      record,
      isReprint: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Premium light gray background
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.storefront,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'ESTIMATE',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                fontSize: 18,
              ),
            ),
          ],
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        shadowColor: const Color(0x0D000000),
        surfaceTintColor: Colors.transparent,
        actions: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 18,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _userId,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_long,
                    size: 18,
                    color: Colors.blue.shade700,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'No: ${_estCounter.toString().padLeft(4, "0")}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_offlineCount > 0) ...[
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Material(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Syncing $_offlineCount offline bills to cloud...',
                        ),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    final synced = await ApiService().syncOfflineSales();
                    await _updateOfflineCount();
                    if (context.mounted && synced > 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Synced $synced bills to cloud successfully!',
                          ),
                          backgroundColor: Colors.green,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_upload,
                          size: 16,
                          color: Colors.amber.shade900,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$_offlineCount Offline',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.receipt_long, color: Colors.green.shade800),
              tooltip: 'Shift Bills & Reprint',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => BillHistoryScreen(
                      selectedPrinter: widget.selectedPrinter,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: (_currentShiftId == null || _currentShiftId!.isEmpty)
                  ? Colors.blue.shade50
                  : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(
                (_currentShiftId == null || _currentShiftId!.isEmpty)
                    ? Icons.lock_open
                    : Icons.lock_clock,
                color: (_currentShiftId == null || _currentShiftId!.isEmpty)
                    ? Colors.blue.shade800
                    : Colors.orange.shade800,
              ),
              tooltip: (_currentShiftId == null || _currentShiftId!.isEmpty)
                  ? 'Open Shift'
                  : 'Close Shift',
              onPressed: () async {
                if (_currentShiftId == null || _currentShiftId!.isEmpty) {
                  await _showOpenShiftDialog(isMandatoryForCheckout: false);
                  return;
                }
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final prefs = await SharedPreferences.getInstance();
                final shiftId = _currentShiftId ?? prefs.getString('shift_id');
                if (shiftId == null) return;
                if (!context.mounted) return;

                double closingCash = 0;
                final res = await showDialog<bool>(
                  context: context,
                  builder: (dialogCtx) {
                    final txt = TextEditingController();
                    return AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      title: const Row(
                        children: [
                          Icon(Icons.lock_clock, color: Colors.orange),
                          SizedBox(width: 8),
                          Text(
                            'Close Shift',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      content: TextField(
                        autofocus: true,

                        controller: txt,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Closing Cash Amount (Rs)',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.currency_rupee),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogCtx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () {
                            closingCash = double.tryParse(txt.text) ?? 0;
                            Navigator.pop(dialogCtx, true);
                          },
                          child: const Text('Confirm Close'),
                        ),
                      ],
                    );
                  },
                );

                if (res == true) {
                  try {
                    await ApiService().closeShift(shiftId, closingCash);
                    try {
                      final p = await SharedPreferences.getInstance();
                      final storeId = p.getString('store_id') ?? '';
                      final terminalId = p.getString('terminal_id') ?? '';
                      await PrinterHelper.printShiftReceipt(
                        widget.selectedPrinter,
                        false,
                        closingCash,
                        storeId,
                        terminalId,
                      );
                    } catch (e) {
                      debugPrint('Error printing close receipt: $e');
                    }
                    await prefs.remove('shift_id');
                    if (mounted) {
                      setState(() => _currentShiftId = null);
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Shift closed successfully. You can open a new shift anytime.',
                          ),
                          backgroundColor: Colors.orange,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  } catch (e) {
                    if (!mounted) return;
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          e.toString().replaceAll('Exception: ', ''),
                        ),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 5),
                        margin: const EdgeInsets.only(
                          bottom: 600,
                          left: 16,
                          right: 16,
                        ),
                      ),
                    );
                  }
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.logout, color: Colors.red.shade800),
              tooltip: 'Logout',
              onPressed: _logout,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: LayoutBuilder(
          builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 800;

          if (isMobile) {
            return Stack(
              children: [
                _buildProductSection(isMobile: true),
                if (_cart.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1A000000),
                            blurRadius: 10,
                            offset: Offset(0, -5),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: SafeArea(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${_cart.length} items',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '₹${_totalAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            ElevatedButton(
                              onPressed: () {
                                _isBottomSheetOpen = true;
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (context) =>
                                      ValueListenableBuilder<int>(
                                        valueListenable: _cartNotifier,
                                        builder: (context, _, child) {
                                          return Container(
                                            height:
                                                MediaQuery.of(
                                                  context,
                                                ).size.height *
                                                0.85,
                                            margin: EdgeInsets.only(
                                              top: MediaQuery.of(
                                                context,
                                              ).padding.top,
                                            ),
                                            decoration: const BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.vertical(
                                                    top: Radius.circular(24),
                                                  ),
                                            ),
                                            child: _buildCartUI(context),
                                          );
                                        },
                                      ),
                                ).whenComplete(
                                  () => _isBottomSheetOpen = false,
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.shopping_cart,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'View Cart',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                flex: _isCartVisible ? 9 : 14,
                child: _buildProductSection(isMobile: false),
              ),
              if (_isCartVisible)
                Expanded(flex: 5, child: _buildCartUI(context)),
            ],
          );
        },
      ),
    ),
  );
  }

  Widget _buildCartUI(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 24, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade100, width: 2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.shopping_cart_outlined,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Current Order',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  if (_cart.isNotEmpty) ...[
                    IconButton(
                      icon: Icon(
                        Icons.delete_sweep_outlined,
                        color: Colors.red.shade400,
                        size: 22,
                      ),
                      tooltip: 'Clear Order',
                      onPressed: _clearCart,
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_cart.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _cart.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shopping_basket_outlined,
                            size: 80,
                            color: Colors.grey.shade200,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "Cart is empty",
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey.shade400,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20.0),
                      itemCount: _cart.length,
                      separatorBuilder: (context, index) =>
                          Divider(color: Colors.grey.shade100, height: 24),
                      itemBuilder: (context, index) {
                        final item = _cart[index];
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.product.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '₹${item.product.price.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade200),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  _buildQuantityButton(
                                    icon: Icons.remove,
                                    color: Colors.transparent,
                                    iconColor: Colors.red.shade400,
                                    onTap: () => _decrement(index),
                                  ),
                                  InkWell(
                                    onTap: () => _showNumpadDialog(index),
                                    child: Container(
                                      width: 40,
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${item.quantity}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  _buildQuantityButton(
                                    icon: Icons.add,
                                    color: Colors.transparent,
                                    iconColor: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    onTap: () => _increment(index),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 85,
                              child: Text(
                                '₹${(item.product.price * item.quantity).toStringAsFixed(2)}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Column(
                children: [
                  if (_roundOffAmount.abs() > 0.001) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Subtotal',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          '₹${_subtotal.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Round Off',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          '${_roundOffAmount > 0 ? '+' : ''}₹${_roundOffAmount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _roundOffAmount > 0
                                ? Colors.green.shade700
                                : Colors.orange.shade800,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Amount',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        '₹${_totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: ElevatedButton(
                      onPressed: (_cart.isEmpty || _isProcessing) ? null : _checkout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Checkout',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded),
                        ],
                      ),
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

class SplitPaymentDialog extends StatefulWidget {
  final double totalAmount;
  final double? subtotal;
  final double? roundOff;
  final Function(double cashAmount, double upiAmount) onConfirm;

  const SplitPaymentDialog({
    super.key,
    required this.totalAmount,
    this.subtotal,
    this.roundOff,
    required this.onConfirm,
  });

  @override
  State<SplitPaymentDialog> createState() => _SplitPaymentDialogState();
}

class _SplitPaymentDialogState extends State<SplitPaymentDialog> {
  final TextEditingController _cashCtrl = TextEditingController();
  final TextEditingController _upiCtrl = TextEditingController();
  bool _isAutoUpdating = false;
  bool _isSubmitting = false; // Prevents duplicate payment clicks

  @override
  void initState() {
    super.initState();
    // Default to full cash
    _cashCtrl.text = widget.totalAmount.toStringAsFixed(2);
    _upiCtrl.text = "0.00";
  }

  void _onCashChanged(String val) {
    if (_isAutoUpdating) return;
    _isAutoUpdating = true;
    double cash = double.tryParse(val) ?? 0;
    if (cash > widget.totalAmount) {
      cash = widget.totalAmount;
      _cashCtrl.text = cash.toStringAsFixed(2);
      _cashCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _cashCtrl.text.length),
      );
    }
    double upi = widget.totalAmount - cash;
    _upiCtrl.text = upi.toStringAsFixed(2);
    _isAutoUpdating = false;
    setState(() {}); // Update summary
  }

  void _onUpiChanged(String val) {
    if (_isAutoUpdating) return;
    _isAutoUpdating = true;
    double upi = double.tryParse(val) ?? 0;
    if (upi > widget.totalAmount) {
      upi = widget.totalAmount;
      _upiCtrl.text = upi.toStringAsFixed(2);
      _upiCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _upiCtrl.text.length),
      );
    }
    double cash = widget.totalAmount - upi;
    _cashCtrl.text = cash.toStringAsFixed(2);
    _isAutoUpdating = false;
    setState(() {}); // Update summary
  }

  void _setFullCash() {
    _isAutoUpdating = true;
    _cashCtrl.text = widget.totalAmount.toStringAsFixed(2);
    _upiCtrl.text = "0.00";
    _isAutoUpdating = false;
    setState(() {}); // Update summary
  }

  void _setFullUpi() {
    _isAutoUpdating = true;
    _upiCtrl.text = widget.totalAmount.toStringAsFixed(2);
    _cashCtrl.text = "0.00";
    _isAutoUpdating = false;
    setState(() {}); // Update summary
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine a dynamic width (e.g. tablet vs phone)
    final width = MediaQuery.of(context).size.width > 600
        ? 500.0
        : MediaQuery.of(context).size.width * 0.9;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Complete Payment',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: width,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200, width: 2),
                ),
                child: Column(
                  children: [
                    if (widget.roundOff != null &&
                        widget.roundOff!.abs() > 0.001) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Subtotal:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade700,
                            ),
                          ),
                          Text(
                            'Rs ${(widget.subtotal ?? (widget.totalAmount - widget.roundOff!)).toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Round Off:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade700,
                            ),
                          ),
                          Text(
                            '${widget.roundOff! > 0 ? '+' : ''}Rs ${widget.roundOff!.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: widget.roundOff! > 0
                                  ? Colors.green.shade800
                                  : Colors.orange.shade900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TOTAL DUE:',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        Text(
                          'Rs ${widget.totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const Divider(
                      height: 24,
                      thickness: 1.5,
                      color: Colors.blue,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CASH',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                            Text(
                              'Rs ${double.tryParse(_cashCtrl.text)?.toStringAsFixed(2) ?? "0.00"}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Colors.green.shade800,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'UPI',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade700,
                              ),
                            ),
                            Text(
                              'Rs ${double.tryParse(_upiCtrl.text)?.toStringAsFixed(2) ?? "0.00"}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Colors.purple.shade800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _setFullCash,
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('Full Cash'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _setFullUpi,
                      icon: const Icon(Icons.qr_code_scanner, size: 18),
                      label: const Text('Full UPI'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Cash Amount',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _cashCtrl,
                enabled: !_isSubmitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: _onCashChanged,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.money, color: Colors.green),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'UPI Amount',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _upiCtrl,
                enabled: !_isSubmitting,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: _onUpiChanged,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.qr_code, color: Colors.purple),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(fontSize: 16)),
        ),
        ElevatedButton(
          onPressed: _isSubmitting
              ? null
              : () {
                  double cash = double.tryParse(_cashCtrl.text) ?? 0;
                  double upi = double.tryParse(_upiCtrl.text) ?? 0;
                  if ((cash + upi - widget.totalAmount).abs() > 0.01) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Total split amounts must equal Total Due'),
                      ),
                    );
                    return;
                  }
                  setState(() => _isSubmitting = true);
                  widget.onConfirm(cash, upi);
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Complete Payment',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }
}

/// Phone / Tablet Camera Barcode Scanner Sheet for POS
class _PosCameraScannerSheet extends StatefulWidget {
  final Function(String barcode) onBarcodeDetected;

  const _PosCameraScannerSheet({required this.onBarcodeDetected});

  @override
  State<_PosCameraScannerSheet> createState() => _PosCameraScannerSheetState();
}

class _PosCameraScannerSheetState extends State<_PosCameraScannerSheet> {
  MobileScannerController? _controller;
  bool _isReady = false;
  bool _isScanned = false;
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller = MobileScannerController(
          autoStart: true,
          detectionSpeed: DetectionSpeed.normal,
          facing: CameraFacing.back,
        );
        setState(() => _isReady = true);
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: _isReady && _controller != null
                ? MobileScanner(
                    controller: _controller!,
                    fit: BoxFit.cover,
                    onDetect: (capture) {
                      if (_isScanned) return;
                      for (final barcode in capture.barcodes) {
                        final raw = barcode.rawValue;
                        if (raw != null && raw.trim().isNotEmpty) {
                          _isScanned = true;
                          widget.onBarcodeDetected(raw.trim());
                          break;
                        }
                      }
                    },
                  )
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.qr_code_scanner, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Point at Barcode',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _torchOn ? Icons.flash_on : Icons.flash_off,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() => _torchOn = !_torchOn);
                        _controller?.toggleTorch();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
