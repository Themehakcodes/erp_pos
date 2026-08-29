import 'package:flutter/material.dart';
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
  final String name;
  final double price;
  Product(this.name, this.price);
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
  final List<CartItem> _cart = [CartItem(Product('Item-20', 20.0), 1)];

  final String _userId = "ID: 45091";

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
                  // Prevent long quantities
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
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
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

    await _printReceipt(method);

    if (mounted) {
      Navigator.pop(context); // Close loader
    }

    widget.onSaleCompleted(method, amountToCharge);

    setState(() {
      for (var item in _cart) {
        item.quantity = 1;
      }
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
  }

  Future<List<int>> _generateReceiptBytes(String method) async {
    final List<int> bytes = [];
    
    // Init
    bytes.addAll([0x1B, 0x40]); 
    
    // Title (Centered & Bold & Double Size)
    bytes.addAll([0x1B, 0x61, 0x01]); // Center
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold
    bytes.addAll([0x1D, 0x21, 0x11]); // Double Height & Width
    bytes.addAll("20 MART\n\n".codeUnits);
    
    // Normal Text Size
    bytes.addAll([0x1D, 0x21, 0x00]); 
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
    bytes.addAll("Date: ${DateTime.now().toString().substring(0, 16)}\n".codeUnits);
    
    bytes.addAll([0x1B, 0x61, 0x00]); // Left Align
    bytes.addAll("--------------------------------\n".codeUnits);
    
    for (var item in _cart) {
      String nameLine = "${item.product.name} x${item.quantity}";
      String priceLine = "Rs ${(item.product.price * item.quantity).toStringAsFixed(2)}";
      
      // Basic padding to align right (assume 32 chars width for 58mm)
      int paddingSize = 32 - nameLine.length - priceLine.length;
      if (paddingSize < 1) paddingSize = 1;
      String padding = " " * paddingSize;
      
      bytes.addAll("$nameLine$padding$priceLine\n".codeUnits);
    }
    
    bytes.addAll("--------------------------------\n".codeUnits);
    
    // Total
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold
    String totalTitle = "TOTAL";
    String totalValue = "Rs ${_totalAmount.toStringAsFixed(2)}";
    int pad1 = 32 - totalTitle.length - totalValue.length;
    bytes.addAll("$totalTitle${" " * (pad1 > 0 ? pad1 : 1)}$totalValue\n".codeUnits);
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
    
    // Method
    String methodTitle = "METHOD";
    int pad2 = 32 - methodTitle.length - method.length;
    bytes.addAll("$methodTitle${" " * (pad2 > 0 ? pad2 : 1)}$method\n".codeUnits);
    
    bytes.addAll("--------------------------------\n".codeUnits);
    
    // Footer
    bytes.addAll([0x1B, 0x61, 0x01]); // Center
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold
    bytes.addAll("Thank You!\n".codeUnits);
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
    bytes.addAll("Please visit again\n\n\n\n".codeUnits);
    
    // Cut Paper (Standard ESC/POS full cut)
    bytes.addAll([0x1D, 0x56, 0x41, 0x00]);
    
    return bytes;
  }

  Future<void> _printReceipt(String method) async {
    if (widget.selectedPrinter == null) {
      debugPrint("No printer selected. Skipping print.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No printer configured. Go to Settings.'), backgroundColor: Colors.red)
        );
      }
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
        throw Exception("Network printers not implemented in this snippet");
      }

      await printerManager.connect(type: type, model: inputParams);
      
      List<int> receiptBytes = await _generateReceiptBytes(method);
      await printerManager.send(type: type, bytes: receiptBytes);
      
      // Slight delay to ensure buffer is sent
      await Future.delayed(const Duration(milliseconds: 500));
      
      await printerManager.disconnect(type: type);

    } catch (e) {
      debugPrint('Raw Print Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print Failed! $e'), backgroundColor: Colors.red)
        );
      }
    }
  }

  void _logout() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Logged out!')));
  }

  Widget _buildQuantityButton({
    required IconData icon,
    required Color color,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 28),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          '20 MART',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                _userId,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
          const SizedBox(width: 8),
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
                  'Current Sale',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: _cart.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final item = _cart[index];
                    return Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.product.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '₹${item.product.price.toStringAsFixed(2)}',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            _buildQuantityButton(
                              icon: Icons.remove,
                              color: Colors.red.shade50,
                              iconColor: Colors.red.shade600,
                              onTap: () => _decrement(index),
                            ),
                            InkWell(
                              onTap: () => _showNumpadDialog(index),
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                width: 50,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  '${item.quantity}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            _buildQuantityButton(
                              icon: Icons.add,
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                              iconColor: Theme.of(context).colorScheme.primary,
                              onTap: () => _increment(index),
                            ),
                          ],
                        ),
                        SizedBox(
                          width: 80,
                          child: Text(
                            '₹${(item.product.price * item.quantity).toStringAsFixed(2)}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Amount',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '₹${_totalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _checkout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Save & Pay',
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
            ],
          ),
        ),
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
