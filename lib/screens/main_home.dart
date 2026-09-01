import 'package:flutter/material.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import '../api_service.dart';
import '../models/models.dart';
import 'pos_screen.dart';
import 'sales_screen.dart';
import 'settings_tab.dart';

class MainHome extends StatefulWidget {
  final double openingBalance;

  const MainHome({super.key, required this.openingBalance});

  @override
  State<MainHome> createState() => _MainHomeState();
}

class _MainHomeState extends State<MainHome> with WidgetsBindingObserver {
  int _currentIndex = 0;

  late double _totalCash;
  double _totalUpi = 0.0;
  
  SelectedPrinter? _selectedPrinter;
  bool _isLoadingPrinter = true;
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _totalCash = widget.openingBalance;
    _loadPrinter();
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      Future.microtask(() => ApiService().heartbeat());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startHeartbeat();
      ApiService().heartbeat();
    } else if (state == AppLifecycleState.paused) {
      _heartbeatTimer?.cancel();
      // Removed automatic Bluetooth disconnect on pause because some custom
      // POS Android ROMs aggressively fire 'paused' during simple tab or focus changes,
      // which was killing the printer connection.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    super.dispose();
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
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.storefront, size: 48, color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'ERP POS System',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.point_of_sale, color: Colors.black87),
              title: const Text('POS Terminal', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context); // Close drawer
              },
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart, color: Colors.black87),
              title: const Text('Sales Report', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context); // Close drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SalesScreen(
                      openingBalance: widget.openingBalance,
                      totalCash: _totalCash,
                      totalUpi: _totalUpi,
                    ),
                  ),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.black87),
              title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context); // Close drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SettingsTab(
                      currentPrinter: _selectedPrinter,
                      onPrinterSelected: _setPrinter,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: PosScreen(
        onSaleCompleted: _recordSale,
        selectedPrinter: _selectedPrinter,
      ),
    );
  }
}


