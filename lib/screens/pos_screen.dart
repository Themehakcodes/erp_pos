import 'package:flutter/material.dart';
import 'login_screen.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import '../api_service.dart';
import '../models/models.dart';

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
  // Native MethodChannel for internal Atpos 1008 printer — bypasses Bluetooth/USB plugin entirely
  static const _printerChannel = MethodChannel('pos_printer');

  final List<CartItem> _cart = [];
  final ValueNotifier<int> _cartNotifier = ValueNotifier<int>(0);
  List<Product> _products = [];
  bool _isLoading = true;
  bool _isCartVisible = true;
  String _userId = "Cashier";
  int _estCounter = 1;
  bool _isBottomSheetOpen = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userId = prefs.getString('user_name') ?? 'Cashier';
      _estCounter = prefs.getInt('est_counter') ?? 1;
    });
    try {
      final dynamic data = await ApiService().getProducts(limit: 100);
      setState(() {
        List itemsList = [];
        if (data is List) {
          itemsList = data;
        } else if (data is Map) {
          if (data['items'] != null)
            itemsList = data['items'];
          else if (data['products'] != null)
            itemsList = data['products'];
          else if (data['data'] != null)
            itemsList = data['data'];
        }
        _products = itemsList
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
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

  double get _totalAmount {
    return _cart.fold(
      0.0,
      (sum, item) => sum + (item.product.price * item.quantity),
    );
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

  Widget _buildProductGrid() {
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
    if (_products.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No products available.',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = 4;
    if (screenWidth < 600)
      crossAxisCount = 2;
    else if (screenWidth < 900)
      crossAxisCount = 3;

    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: screenWidth < 600 ? 0.75 : 0.8,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: _products.length,
      itemBuilder: (context, index) {
        final p = _products[index];
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
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 15,
                offset: const Offset(0, 8),
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
              splashColor: iconColor.withOpacity(0.2),
              highlightColor: iconColor.withOpacity(0.1),
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

  void _checkout() {
    showDialog(
      context: context,
      builder: (context) {
        return SplitPaymentDialog(
          totalAmount: _totalAmount,
          onConfirm: (cash, upi) {
            Navigator.pop(context);
            _processSplitPayment(cash, upi);
          },
        );
      },
    );
  }

  Future<void> _processSplitPayment(double cashAmount, double upiAmount) async {
    final amountToCharge = _totalAmount;

    String method = '';
    if (cashAmount > 0 && upiAmount > 0) {
      method = 'Split (Cash & UPI)';
    } else if (cashAmount > 0) {
      method = 'Cash';
    } else {
      method = 'UPI';
    }

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
              "taxable_amount": c.product.price * c.quantity,
              "cgst_percent": 0.0,
              "cgst_amount": 0.0,
              "sgst_percent": 0.0,
              "sgst_amount": 0.0,
              "igst_percent": 0.0,
              "igst_amount": 0.0,
              "tax_amount": 0.0,
              "line_total": c.product.price * c.quantity,
            },
          )
          .toList();

      final saleData = {
        "store_id": storeId,
        "shift_id": shiftId,
        "financial_year_id": financialYearId,
        "invoice_date": DateTime.now().toUtc().toIso8601String(),
        "invoice_status": "completed",
        "bill_type": "pos",
        "is_gst_bill": false,
        "total_items": _cart.length,
        "total_quantity": _cart.fold(0.0, (sum, item) => sum + item.quantity),
        "subtotal_amount": amountToCharge,
        "discount_amount": 0.0,
        "taxable_amount": amountToCharge,
        "cgst_amount": 0.0,
        "sgst_amount": 0.0,
        "igst_amount": 0.0,
        "round_off_amount": 0.0,
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
      final displayNo =
          invoiceNo ?? 'EST${_estCounter.toString().padLeft(4, "0")}';

      // Increment EST counter and persist
      final nextCounter = _estCounter + 1;
      final prefs2 = await SharedPreferences.getInstance();
      await prefs2.setInt('est_counter', nextCounter);

      final cartSnapshot = List<CartItem>.from(_cart);
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
        () => _printReceipt(method, cartSnapshot, amountToCharge, displayNo),
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
    }
  }

  Future<List<int>> _generateReceiptBytes(
    String method,
    List<CartItem> cartSnapshot,
    double totalAmount,
    String invoiceNo,
  ) async {
    final List<int> bytes = [];
    bytes.addAll([0x1B, 0x40]);
    bytes.addAll([0x1B, 0x61, 0x01]);
    bytes.addAll([0x1B, 0x45, 0x01]);
    bytes.addAll([0x1D, 0x21, 0x11]);

    // Print the actual server invoice no (SI-XXXX) or local ESTXXXX
    bytes.addAll("$invoiceNo\n\n".codeUnits);
    bytes.addAll([0x1D, 0x21, 0x00]);
    bytes.addAll([0x1B, 0x45, 0x00]);
    bytes.addAll(
      "Date: ${DateTime.now().toString().substring(0, 16)}\n".codeUnits,
    );
    bytes.addAll([0x1B, 0x61, 0x00]);
    bytes.addAll("--------------------------------\n".codeUnits);

    for (var item in cartSnapshot) {
      String nameLine = "${item.product.name} x${item.quantity}";
      String priceLine =
          "Rs ${(item.product.price * item.quantity).toStringAsFixed(2)}";
      int paddingSize = 32 - nameLine.length - priceLine.length;
      if (paddingSize < 1) paddingSize = 1;
      String padding = " " * paddingSize;
      bytes.addAll("$nameLine$padding$priceLine\n".codeUnits);
    }

    bytes.addAll("--------------------------------\n".codeUnits);
    bytes.addAll([0x1B, 0x45, 0x01]);
    String totalTitle = "TOTAL";
    String totalValue = "Rs ${totalAmount.toStringAsFixed(2)}";
    int pad1 = 32 - totalTitle.length - totalValue.length;
    bytes.addAll(
      "$totalTitle${" " * (pad1 > 0 ? pad1 : 1)}$totalValue\n".codeUnits,
    );
    bytes.addAll([0x1B, 0x45, 0x00]);
    String methodTitle = "METHOD";
    int pad2 = 32 - methodTitle.length - method.length;
    bytes.addAll(
      "$methodTitle${" " * (pad2 > 0 ? pad2 : 1)}$method\n".codeUnits,
    );
    bytes.addAll("--------------------------------\n".codeUnits);
    bytes.addAll([0x1B, 0x61, 0x01]);
    bytes.addAll([0x1B, 0x45, 0x01]);
    bytes.addAll("Thank You!\n".codeUnits);
    bytes.addAll([0x1B, 0x45, 0x00]);
    bytes.addAll("Please visit again\n\n\n\n".codeUnits);
    bytes.addAll([0x1D, 0x56, 0x41, 0x00]);
    return bytes;
  }

  Future<void> _printReceipt(
    String method,
    List<CartItem> cartSnapshot,
    double totalAmount,
    String invoiceNo,
  ) async {
    // Generate ESC/POS bytes first (pure Dart — no hardware)
    final List<int> receiptBytes = await _generateReceiptBytes(
      method,
      cartSnapshot,
      totalAmount,
      invoiceNo,
    );
    final Uint8List bytes = Uint8List.fromList(receiptBytes);

    // If no printer is selected, skip
    if (widget.selectedPrinter == null) {
      debugPrint('No printer selected. Skipping print.');
      return;
    }

    // 1. If internal printer is explicitly selected
    if (widget.selectedPrinter!.isInternal) {
      try {
        final result = await _printerChannel.invokeMethod<bool>('printBytes', {
          'bytes': bytes,
        });
        if (result == true) {
          debugPrint(
            'Printed via internal serial port (${bytes.length} bytes)',
          );
          return;
        } else {
          debugPrint('Internal printer failed to print (no valid port).');
        }
      } catch (e) {
        debugPrint('Internal printer error: $e');
      }
      return; // Do not fallback to bluetooth if they explicitly chose Internal
    }

    // 2. Otherwise, use selected Bluetooth or USB printer
    try {
      var printerManager = PrinterManager.instance;
      final device = widget.selectedPrinter!.device!;
      final type = widget.selectedPrinter!.type!;

      var inputParams;
      if (type == PrinterType.usb) {
        inputParams = UsbPrinterInput(
          name: device.name,
          vendorId: device.vendorId,
          productId: device.productId,
        );
      } else if (type == PrinterType.bluetooth) {
        inputParams = BluetoothPrinterInput(
          name: device.name,
          address: device.address!,
          isBle: false,
          autoConnect: false,
        );
      } else {
        return;
      }

      // Explicitly INITIALIZE fresh state right before printing (as requested)
      try {
        await printerManager.disconnect(type: type);
      } catch (_) {}
      await Future.delayed(
        const Duration(milliseconds: 300),
      ); // allow native thread to release

      bool isConnected = false;
      try {
        final result = await printerManager.connect(
          type: type,
          model: inputParams,
        );
        isConnected = (result == true);
      } catch (e) {
        debugPrint('Connection exception: $e');
      }

      if (isConnected) {
        await printerManager.send(type: type, bytes: receiptBytes);
        // Wait for physical print buffer to clear
        await Future.delayed(const Duration(seconds: 3));
      } else {
        debugPrint('Failed to initialize connection to printer.');
      }

      // Always clean up after
      try {
        await printerManager.disconnect(type: type);
      } catch (_) {}

      debugPrint('Finished Bluetooth/USB print cycle.');
    } catch (e) {
      debugPrint('Bluetooth/USB print error: $e');
    }
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
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
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
        shadowColor: Colors.black.withOpacity(0.05),
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
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.lock_clock, color: Colors.orange.shade800),
              tooltip: 'Close Shift',
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final shiftId = prefs.getString('shift_id');
                if (shiftId == null) return;

                double closingCash = 0;
                final res = await showDialog<bool>(
                  context: context,
                  builder: (context) {
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
                          onPressed: () => Navigator.pop(context, false),
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
                            Navigator.pop(context, true);
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
                    _logout();
                  } catch (e) {
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 800;

          if (isMobile) {
            return Stack(
              children: [
                _buildProductGrid(),
                if (_cart.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, -5),
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
                                        builder: (context, _, __) {
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
                child: _buildProductGrid(),
              ),
              if (_isCartVisible)
                Expanded(flex: 5, child: _buildCartUI(context)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCartUI(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 24, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
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
                  if (_cart.isNotEmpty)
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
                      onPressed: _cart.isEmpty ? null : _checkout,
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
  final Function(double cashAmount, double upiAmount) onConfirm;

  const SplitPaymentDialog({
    super.key,
    required this.totalAmount,
    required this.onConfirm,
  });

  @override
  State<SplitPaymentDialog> createState() => _SplitPaymentDialogState();
}

class _SplitPaymentDialogState extends State<SplitPaymentDialog> {
  final TextEditingController _cashCtrl = TextEditingController();
  final TextEditingController _upiCtrl = TextEditingController();
  bool _isAutoUpdating = false;

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
                      onPressed: _setFullCash,
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
                      onPressed: _setFullUpi,
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(fontSize: 16)),
        ),
        ElevatedButton(
          onPressed: () {
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
          child: const Text(
            'Complete Payment',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
