import 'package:flutter/material.dart';
import 'api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const PosApp());
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '20 MART POS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const OpeningBalanceScreen(),
    );
  }
}

class OpeningBalanceScreen extends StatefulWidget {
  const OpeningBalanceScreen({super.key});

  @override
  State<OpeningBalanceScreen> createState() => _OpeningBalanceScreenState();
}

class _OpeningBalanceScreenState extends State<OpeningBalanceScreen> {
  String _amountStr = "";

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.location,
      ].request();
    }
  }

  void _onKeyTap(String val) {
    if (val == 'C') {
      setState(() => _amountStr = "");
    } else if (val == '<') {
      if (_amountStr.isNotEmpty) {
        setState(() => _amountStr = _amountStr.substring(0, _amountStr.length - 1));
      }
    } else {
      if (val == '.' && _amountStr.contains('.')) return;
      if (val == '.' && _amountStr.isEmpty) {
        setState(() => _amountStr = "0.");
        return;
      }
      setState(() => _amountStr += val);
    }
  }

  void _submit() {
    final balance = double.tryParse(_amountStr) ?? 0.0;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => MainHome(openingBalance: balance)),
    );
  }

  Widget _buildKey(String val) {
    return Expanded(
      child: InkWell(
        onTap: () => _onKeyTap(val),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 60,
          alignment: Alignment.center,
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Text(
            val == '<' ? '⌫' : val,
            style: TextStyle(
              fontSize: 24, 
              fontWeight: (val == 'C' || val == '<') ? FontWeight.normal : FontWeight.bold,
              color: val == 'C' ? Colors.redAccent : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.account_balance_wallet,
                size: 50,
                color: Colors.blue,
              ),
              const SizedBox(height: 16),
              const Text(
                'Opening Balance',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Enter the starting cash in drawer',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border.all(color: Colors.blue.shade200, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _amountStr.isEmpty ? '₹ 0' : '₹ $_amountStr',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: _amountStr.isEmpty ? Colors.grey : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              
              // Custom NumPad
              Column(
                children: [
                  Row(children: [_buildKey('1'), _buildKey('2'), _buildKey('3')]),
                  Row(children: [_buildKey('4'), _buildKey('5'), _buildKey('6')]),
                  Row(children: [_buildKey('7'), _buildKey('8'), _buildKey('9')]),
                  Row(children: [_buildKey('C'), _buildKey('0'), _buildKey('<')]),
                ],
              ),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Start Register',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Product {
  final String id;
  final String stockId;
  final String barcode;
  final String name;
  final double price;
  Product(this.id, this.stockId, this.barcode, this.name, this.price);

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      json['id'] ?? '',
      json['stock_id'] ?? '',
      json['barcode'] ?? '',
      json['name'] ?? 'Unknown',
      (json['sale_rate'] ?? json['stock_sale_rate_a'] ?? json['mrp'] ?? 0.0).toDouble(),
    );
  }
}

class CartItem {
  final Product product;
  int quantity;
  CartItem(this.product, this.quantity);
}

// Wrapper for the selected printer
class SelectedPrinter {
  final PrinterDevice device;
  final PrinterType type;
  SelectedPrinter(this.device, this.type);

  Map<String, dynamic> toJson() {
    return {
      'name': device.name,
      'address': device.address,
      'vendorId': device.vendorId,
      'productId': device.productId,
      'type': type == PrinterType.usb ? 'usb' : 'bluetooth',
    };
  }

  factory SelectedPrinter.fromJson(Map<String, dynamic> json) {
    PrinterDevice d = PrinterDevice(
      name: json['name'],
      address: json['address'],
      vendorId: json['vendorId'],
      productId: json['productId'],
    );
    PrinterType t = json['type'] == 'usb' ? PrinterType.usb : PrinterType.bluetooth;
    return SelectedPrinter(d, t);
  }
}

class MainHome extends StatefulWidget {
  final double openingBalance;

  const MainHome({super.key, required this.openingBalance});

  @override
  State<MainHome> createState() => _MainHomeState();
}

class _MainHomeState extends State<MainHome> {
  int _currentIndex = 0;

  late double _totalCash;
  double _totalUpi = 0.0;
  
  SelectedPrinter? _selectedPrinter;
  bool _isLoadingPrinter = true;

  @override
  void initState() {
    super.initState();
    _totalCash = widget.openingBalance;
    _loadPrinter();
  }

  Future<void> _loadPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final printerData = prefs.getString('saved_printer');
    if (printerData != null) {
      try {
        final decoded = jsonDecode(printerData);
        setState(() {
          _selectedPrinter = SelectedPrinter.fromJson(decoded);
        });
      } catch (e) {
        debugPrint('Error loading printer: $e');
      }
    }
    setState(() {
      _isLoadingPrinter = false;
    });
  }

  void _recordSale(String method, double amount) {
    setState(() {
      if (method == 'Cash') {
        _totalCash += amount;
      } else if (method == 'UPI') {
        _totalUpi += amount;
      }
    });
  }

  void _setPrinter(SelectedPrinter? printer) async {
    setState(() {
      _selectedPrinter = printer;
    });
    final prefs = await SharedPreferences.getInstance();
    if (printer == null) {
      prefs.remove('saved_printer');
    } else {
      prefs.setString('saved_printer', jsonEncode(printer.toJson()));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPrinter) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          PosScreen(
            onSaleCompleted: _recordSale,
            selectedPrinter: _selectedPrinter,
          ),
          SalesScreen(
            openingBalance: widget.openingBalance,
            totalCash: _totalCash,
            totalUpi: _totalUpi,
          ),
          SettingsTab(
            currentPrinter: _selectedPrinter,
            onPrinterSelected: _setPrinter,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.point_of_sale),
            label: 'POS',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Sales',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

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
  List<Product> _products = [];
  bool _isLoading = true;
  bool _isCartVisible = true;
  String _userId = "Cashier";

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _userId = prefs.getString('user_id') ?? 'Cashier');
    try {
      final dynamic data = await ApiService().getProducts(limit: 100);
      setState(() {
        List itemsList = [];
        if (data is List) {
          itemsList = data;
        } else if (data is Map) {
          if (data['items'] != null) itemsList = data['items'];
          else if (data['products'] != null) itemsList = data['products'];
          else if (data['data'] != null) itemsList = data['data'];
        }
        _products = itemsList.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('shift_id');
    await prefs.remove('terminal_id');
    await prefs.remove('store_id');
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  void _addToCart(Product p) {
    final index = _cart.indexWhere((item) => item.product.id == p.id);
    if (index >= 0) {
      _increment(index);
    } else {
      setState(() => _cart.add(CartItem(p, 1)));
    }
  }

  void _increment(int index) {
    setState(() {
      _cart[index].quantity++;
    });
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
  }

  void _setQuantity(int index, int newQty) {
    if (newQty > 0) {
      setState(() {
        _cart[index].quantity = newQty;
      });
    }
  }

  double get _totalAmount {
    return _cart.fold(
      0.0,
      (sum, item) => sum + (item.product.price * item.quantity),
    );
  }

  Widget _buildQuantityButton({required IconData icon, required Color color, required Color iconColor, required VoidCallback onTap}) {
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
            Text('Fetching Products...', style: TextStyle(color: Colors.grey.shade600, fontSize: 16, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }
    if (_products.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('No products available.', style: TextStyle(fontSize: 18, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4, 
        childAspectRatio: 0.8,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: _products.length,
      itemBuilder: (context, index) {
        final p = _products[index];
        final List<Color> colors = [
          Colors.blue.shade50, Colors.purple.shade50, Colors.orange.shade50, Colors.teal.shade50,
          Colors.pink.shade50, Colors.indigo.shade50, Colors.green.shade50, Colors.amber.shade50
        ];
        final List<Color> iconColors = [
          Colors.blue.shade400, Colors.purple.shade400, Colors.orange.shade400, Colors.teal.shade400,
          Colors.pink.shade400, Colors.indigo.shade400, Colors.green.shade400, Colors.amber.shade400
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
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
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
                          Text(
                            p.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              letterSpacing: -0.3,
                              color: Colors.black87,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                        fontWeight: (val == 'C' || val == '<') ? FontWeight.normal : FontWeight.bold,
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
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Column(
                    children: [
                      Row(children: [buildKey('1'), buildKey('2'), buildKey('3')]),
                      Row(children: [buildKey('4'), buildKey('5'), buildKey('6')]),
                      Row(children: [buildKey('7'), buildKey('8'), buildKey('9')]),
                      Row(children: [buildKey('C'), buildKey('0'), buildKey('<')]),
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
          }
        );
      }
    );
  }

  void _checkout() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Select Payment Method',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPaymentOption(
                context,
                title: 'UPI',
                icon: Icons.qr_code_scanner,
                color: Colors.purple.shade600,
                onTap: () {
                  Navigator.pop(context);
                  _processPayment('UPI');
                },
              ),
              const SizedBox(height: 12),
              _buildPaymentOption(
                context,
                title: 'Cash',
                icon: Icons.payments_outlined,
                color: Colors.green.shade600,
                onTap: () {
                  Navigator.pop(context);
                  _processPayment('Cash');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaymentOption(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    );
  }

  Future<void> _processPayment(String method) async {
    final amountToCharge = _totalAmount;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final storeId = prefs.getString('store_id');
      final shiftId = prefs.getString('shift_id');
      
      final items = _cart.map((c) => {
        "product_id": c.product.id,
        "product_stock_id": c.product.stockId,
        "barcode": c.product.barcode,
        "quantity": c.quantity,
        "mrp": c.product.price,
        "sale_rate": c.product.price,
        "line_total": c.product.price * c.quantity
      }).toList();
      
      final fyId = prefs.getString('financial_year_id') ?? '';

      final saleData = {
        "store_id": storeId,
        "shift_id": shiftId,
        "financial_year_id": fyId,
        "invoice_date": DateTime.now().toIso8601String(),
        "is_gst_bill": true,
        "subtotal_amount": amountToCharge,
        "taxable_amount": amountToCharge,
        "net_amount": amountToCharge,
        "items": items,
        "payments": [
          {
            "payment_method_id": method == 'Cash' ? "00000000-0000-0000-0000-000000000001" : "00000000-0000-0000-0000-000000000002",
            "amount_received": amountToCharge,
            "amount_applied": amountToCharge,
            "change_returned": 0.0
          }
        ]
      };
      
      await ApiService().postSale(saleData);
      
      await _printReceipt(method);

      if (mounted) {
        Navigator.pop(context); 
      }

      widget.onSaleCompleted(method, amountToCharge);

      setState(() {
        _cart.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction completed successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch(e) {
      if (mounted) {
        Navigator.pop(context); 
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process sale: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<List<int>> _generateReceiptBytes(String method) async {
    final List<int> bytes = [];
    bytes.addAll([0x1B, 0x40]); 
    bytes.addAll([0x1B, 0x61, 0x01]); 
    bytes.addAll([0x1B, 0x45, 0x01]); 
    bytes.addAll([0x1D, 0x21, 0x11]); 
    bytes.addAll("20 MART\n\n".codeUnits);
    bytes.addAll([0x1D, 0x21, 0x00]); 
    bytes.addAll([0x1B, 0x45, 0x00]); 
    bytes.addAll("Date: ${DateTime.now().toString().substring(0, 16)}\n".codeUnits);
    bytes.addAll([0x1B, 0x61, 0x00]); 
    bytes.addAll("--------------------------------\n".codeUnits);
    
    for (var item in _cart) {
      String nameLine = "${item.product.name} x${item.quantity}";
      String priceLine = "Rs ${(item.product.price * item.quantity).toStringAsFixed(2)}";
      int paddingSize = 32 - nameLine.length - priceLine.length;
      if (paddingSize < 1) paddingSize = 1;
      String padding = " " * paddingSize;
      bytes.addAll("$nameLine$padding$priceLine\n".codeUnits);
    }
    
    bytes.addAll("--------------------------------\n".codeUnits);
    bytes.addAll([0x1B, 0x45, 0x01]); 
    String totalTitle = "TOTAL";
    String totalValue = "Rs ${_totalAmount.toStringAsFixed(2)}";
    int pad1 = 32 - totalTitle.length - totalValue.length;
    bytes.addAll("$totalTitle${" " * (pad1 > 0 ? pad1 : 1)}$totalValue\n".codeUnits);
    bytes.addAll([0x1B, 0x45, 0x00]); 
    String methodTitle = "METHOD";
    int pad2 = 32 - methodTitle.length - method.length;
    bytes.addAll("$methodTitle${" " * (pad2 > 0 ? pad2 : 1)}$method\n".codeUnits);
    bytes.addAll("--------------------------------\n".codeUnits);
    bytes.addAll([0x1B, 0x61, 0x01]); 
    bytes.addAll([0x1B, 0x45, 0x01]); 
    bytes.addAll("Thank You!\n".codeUnits);
    bytes.addAll([0x1B, 0x45, 0x00]); 
    bytes.addAll("Please visit again\n\n\n\n".codeUnits);
    bytes.addAll([0x1D, 0x56, 0x41, 0x00]);
    return bytes;
  }

  Future<void> _printReceipt(String method) async {
    if (widget.selectedPrinter == null) {
      debugPrint("No printer selected. Skipping print.");
      return;
    }

    try {
      var printerManager = PrinterManager.instance;
      
      final device = widget.selectedPrinter!.device;
      final type = widget.selectedPrinter!.type;
      
      var inputParams;
      if (type == PrinterType.usb) {
        inputParams = UsbPrinterInput(
          name: device.name, 
          vendorId: device.vendorId, 
          productId: device.productId
        );
      } else if (type == PrinterType.bluetooth) {
        inputParams = BluetoothPrinterInput(
          name: device.name,
          address: device.address!,
          isBle: false,
        );
      } else {
        return;
      }

      await printerManager.connect(type: type, model: inputParams);
      
      List<int> receiptBytes = await _generateReceiptBytes(method);
      await printerManager.send(type: type, bytes: receiptBytes);
      
      await Future.delayed(const Duration(milliseconds: 500));
      
      await printerManager.disconnect(type: type);

    } catch (e) {
      debugPrint('Raw Print Error: $e');
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
              child: Icon(Icons.storefront, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 12),
            const Text(
              '20 MART POS',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
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
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_outline, size: 18, color: Colors.black54),
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
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(_isCartVisible ? Icons.fullscreen : Icons.shopping_cart, color: Theme.of(context).colorScheme.primary),
              tooltip: _isCartVisible ? 'Expand Products' : 'Show Cart',
              onPressed: () {
                setState(() {
                  _isCartVisible = !_isCartVisible;
                });
              },
            ),
          ),
          const SizedBox(width: 12),
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
                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                       title: const Row(
                         children: [
                           Icon(Icons.lock_clock, color: Colors.orange),
                           SizedBox(width: 8),
                           Text('Close Shift', style: TextStyle(fontWeight: FontWeight.bold)),
                         ],
                       ),
                       content: TextField(
                         controller: txt,
                         keyboardType: const TextInputType.numberWithOptions(decimal: true),
                         decoration: InputDecoration(
                           labelText: 'Closing Cash Amount (Rs)',
                           border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                           prefixIcon: const Icon(Icons.currency_rupee),
                         ),
                       ),
                       actions: [
                         TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                         ElevatedButton(
                           style: ElevatedButton.styleFrom(
                             backgroundColor: Colors.orange,
                             foregroundColor: Colors.white,
                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                           ),
                           onPressed: () {
                             closingCash = double.tryParse(txt.text) ?? 0;
                             Navigator.pop(context, true);
                           }, 
                           child: const Text('Confirm Close')
                         )
                       ]
                     );
                  }
                );
                
                if (res == true) {
                  try {
                    await ApiService().closeShift(shiftId, closingCash);
                    await prefs.remove('shift_id'); // Only clear the shift, not the terminal/login
                    if (mounted) {
                      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SplashLoader()));
                    }
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
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
      body: Row(
        children: [
          Expanded(
            flex: _isCartVisible ? 9 : 14, 
            child: _buildProductGrid(),
          ),
          if (_isCartVisible)
            Expanded(
              flex: 5,
              child: Container(
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
                        border: Border(bottom: BorderSide(color: Colors.grey.shade100, width: 2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.shopping_cart_outlined, color: Colors.blue.shade700),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Current Order',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                          ),
                          const Spacer(),
                          if (_cart.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade600,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_cart.length}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                                Icon(Icons.shopping_basket_outlined, size: 80, color: Colors.grey.shade200),
                                const SizedBox(height: 16),
                                Text("Cart is empty", style: TextStyle(fontSize: 18, color: Colors.grey.shade400, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          )
                        : ListView.separated(
                        padding: const EdgeInsets.all(20.0),
                        itemCount: _cart.length,
                        separatorBuilder: (context, index) => Divider(color: Colors.grey.shade100, height: 24),
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
                                        height: 1.2
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '₹${item.product.price.toStringAsFixed(2)}',
                                      style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600),
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
                                      iconColor: Theme.of(context).colorScheme.primary,
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
                                  Icon(Icons.arrow_forward_rounded)
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
            ),
          ),
        ],
      ),
    );
  }
}

class SalesScreen extends StatelessWidget {
  final double openingBalance;
  final double totalCash;
  final double totalUpi;

  const SalesScreen({
    super.key,
    required this.openingBalance,
    required this.totalCash,
    required this.totalUpi,
  });

  @override
  Widget build(BuildContext context) {
    final double actualCashSales = totalCash - openingBalance;
    final double totalSales = actualCashSales + totalUpi;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Sales Report',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          margin: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              _buildSummaryCard(
                title: 'Total Sales Today',
                amount: totalSales,
                color: Colors.blue.shade700,
                icon: Icons.storefront,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard(
                      title: 'Cash Sales',
                      amount: actualCashSales,
                      color: Colors.green.shade600,
                      icon: Icons.money,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildSummaryCard(
                      title: 'UPI Sales',
                      amount: totalUpi,
                      color: Colors.purple.shade600,
                      icon: Icons.qr_code,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard(
                      title: 'Opening Balance',
                      amount: openingBalance,
                      color: Colors.orange.shade700,
                      icon: Icons.account_balance,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildSummaryCard(
                      title: 'Cash in Drawer',
                      amount: totalCash,
                      color: Colors.teal.shade700,
                      icon: Icons.account_balance_wallet,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required double amount,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsTab extends StatefulWidget {
  final SelectedPrinter? currentPrinter;
  final Function(SelectedPrinter?) onPrinterSelected;

  const SettingsTab({
    super.key,
    required this.currentPrinter,
    required this.onPrinterSelected,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final List<PrinterDevice> _usbPrinters = [];
  final List<PrinterDevice> _btPrinters = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _scanPrinters();
  }

  void _scanPrinters() {
    if (_isScanning) return;
    
    setState(() {
      _usbPrinters.clear();
      _btPrinters.clear();
      _isScanning = true;
    });

    var printerManager = PrinterManager.instance;
    
    // USB Scan
    printerManager.discovery(type: PrinterType.usb, isBle: false).listen((device) {
      if (mounted) {
        if (!_usbPrinters.any((p) => p.name == device.name)) {
          setState(() => _usbPrinters.add(device));
        }
      }
    });

    // Bluetooth Scan
    printerManager.discovery(type: PrinterType.bluetooth, isBle: false).listen((device) {
      if (mounted) {
        if (!_btPrinters.any((p) => p.address == device.address)) {
          setState(() => _btPrinters.add(device));
        }
      }
    });
    
    // Stop scanning visually after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        actions: [
          IconButton(
            icon: _isScanning ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
            onPressed: _scanPrinters,
          )
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          margin: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Hardware Raw Printer Scan',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('This module bypasses Android completely and communicates raw bytes to the Atpos internal hardware via USB serial or Bluetooth.'),
                    ),
                    
                    // --- USB PRINTERS ---
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text(
                        'INTERNAL USB DEVICES',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.blueAccent,
                        ),
                      ),
                    ),
                    if (_usbPrinters.isEmpty && !_isScanning)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('No internal USB printers found.', style: TextStyle(color: Colors.grey)),
                      ),
                    ..._usbPrinters.map((device) {
                      bool isSelected = widget.currentPrinter?.device.name == device.name && widget.currentPrinter?.type == PrinterType.usb;
                      return ListTile(
                        leading: const Icon(Icons.usb, color: Colors.blueAccent),
                        title: Text(device.name ?? 'Unknown USB Printer'),
                        subtitle: Text('Vendor: ${device.vendorId} Product: ${device.productId}'),
                        trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blue) : null,
                        onTap: () {
                          widget.onPrinterSelected(SelectedPrinter(device, PrinterType.usb));
                        },
                      );
                    }),
                    const Divider(),

                    // --- BLUETOOTH PRINTERS ---
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text(
                        'BLUETOOTH DEVICES',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.indigo,
                        ),
                      ),
                    ),
                    if (_btPrinters.isEmpty && !_isScanning)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('No Bluetooth devices found.', style: TextStyle(color: Colors.grey)),
                      ),
                    ..._btPrinters.map((device) {
                      bool isSelected = widget.currentPrinter?.device.address == device.address && widget.currentPrinter?.type == PrinterType.bluetooth;
                      return ListTile(
                        leading: const Icon(Icons.bluetooth, color: Colors.indigo),
                        title: Text(device.name ?? 'Unknown Device'),
                        subtitle: Text(device.address ?? ''),
                        trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blue) : null,
                        onTap: () {
                          widget.onPrinterSelected(SelectedPrinter(device, PrinterType.bluetooth));
                        },
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  void _login() async {
    setState(() => _isLoading = true);
    try {
      await ApiService().login(_emailController.text, _passwordController.text);
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SplashLoader()));
      }
    } catch(e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.storefront,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '20 MART POS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your credentials to login',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Login securely',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SplashLoader extends StatefulWidget {
  const SplashLoader({super.key});
  @override
  State<SplashLoader> createState() => _SplashLoaderState();
}

class _SplashLoaderState extends State<SplashLoader> {
  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  void _checkStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token == null) {
       if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
       return;
    }
    
    try {
      final deviceId = await ApiService().getDeviceIdentifier();
      try {
        final terminal = await ApiService().checkTerminal(deviceId);
        final terminalId = terminal['id'];
        
        final savedStore = prefs.getString('store_id');
        if (savedStore == null || savedStore.isEmpty) {
           if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DeviceNotRegisteredScreen(deviceId: deviceId, existingTerminalId: terminalId)));
           return;
        }

        final storeId = terminal['store_id'] ?? savedStore;
        await prefs.setString('terminal_id', terminalId);
        await prefs.setString('store_id', storeId);

        try {
          final fyId = await ApiService().getActiveFinancialYear();
          await prefs.setString('financial_year_id', fyId);
        } catch (e) {
           // Handle missing financial year if needed
        }

        final shift = await ApiService().getActiveShift(terminalId);
        if (shift != null) {
          await prefs.setString('shift_id', shift['id']);
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MainHome(openingBalance: (shift['opening_cash'] ?? 0.0).toDouble())));
        } else {
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const OpeningBalanceScreen()));
        }
      } catch (e) {
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DeviceNotRegisteredScreen(deviceId: deviceId)));
      }
    } catch(e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class DeviceNotRegisteredScreen extends StatefulWidget {
  final String deviceId;
  final String? existingTerminalId;

  const DeviceNotRegisteredScreen({super.key, required this.deviceId, this.existingTerminalId});
  @override
  State<DeviceNotRegisteredScreen> createState() => _DeviceNotRegisteredScreenState();
}

class _DeviceNotRegisteredScreenState extends State<DeviceNotRegisteredScreen> {
  List<dynamic> _stores = [];
  String? _selectedStore;
  bool _isLoading = true;
  bool _isCartVisible = true;

  @override
  void initState() {
    super.initState();
    _fetchStores();
  }

  void _fetchStores() async {
    try {
      final res = await ApiService().getStores();
      setState(() {
        _stores = res;
        _isLoading = false;
        if (_stores.isNotEmpty) _selectedStore = _stores[0]['id'];
      });
    } catch(e) {
      setState(() => _isLoading = false);
    }
  }
  
  void _register() async {
    if (_selectedStore == null) return;
    try {
      if (widget.existingTerminalId != null) {
        await ApiService().updateTerminal(widget.existingTerminalId!, _selectedStore!, widget.deviceId);
      } else {
        await ApiService().registerTerminal(_selectedStore!, widget.deviceId);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('store_id', _selectedStore!);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const SplashLoader()),
        );
      }
    } catch(e) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Register Terminal')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select Store:'),
            DropdownButton<String>(
              value: _selectedStore,
              items: _stores.map<DropdownMenuItem<String>>((s) => DropdownMenuItem<String>(value: s['id'], child: Text(s['store_name'] ?? s['name'] ?? 'Unknown Store'))).toList(),
              onChanged: (v) => setState(() => _selectedStore = v),
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _register, child: const Text('Register & Continue'))
          ]
        )
      )
    );
  }
}
