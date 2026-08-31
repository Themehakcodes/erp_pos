import 'main_home.dart';
import 'pos_screen.dart';
import 'sales_screen.dart';
import 'settings_tab.dart';
import 'login_screen.dart';
import 'splash_loader.dart';
import 'device_not_registered_screen.dart';
import 'opening_balance_screen.dart';
import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import '../api_service.dart';
import '../models/models.dart';
import 'package:flutter/material.dart';

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
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    _totalCash = widget.openingBalance;
    _loadPrinter();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      Future.microtask(() => ApiService().heartbeat());
    });
  }

  @override
  void dispose() {
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

  bool _salesVisited = false;
  bool _settingsVisited = false;

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPrinter) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        children: [
          Offstage(
            offstage: _currentIndex != 0,
            child: PosScreen(
              onSaleCompleted: _recordSale,
              selectedPrinter: _selectedPrinter,
            ),
          ),
          Offstage(
            offstage: _currentIndex != 1,
            child: _salesVisited ? SalesScreen(
              openingBalance: widget.openingBalance,
              totalCash: _totalCash,
              totalUpi: _totalUpi,
            ) : const SizedBox(),
          ),
          Offstage(
            offstage: _currentIndex != 2,
            child: _settingsVisited ? SettingsTab(
              currentPrinter: _selectedPrinter,
              onPrinterSelected: _setPrinter,
            ) : const SizedBox(),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
            if (index == 1) _salesVisited = true;
            if (index == 2) _settingsVisited = true;
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


