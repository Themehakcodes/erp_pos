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
        if (e.toString().contains('Session expired') || e.toString().contains('Unauthorized') || e.toString().contains('revoked')) {
          await prefs.remove('access_token');
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
          return;
        }
        
        final offlineShiftId = prefs.getString('shift_id');
        if (offlineShiftId != null) {
           if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MainHome(openingBalance: 0.0)));
           return;
        }
        
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DeviceNotRegisteredScreen(deviceId: deviceId)));
      }
    } catch(e) {
      final offlineShiftId = prefs.getString('shift_id');
      if (offlineShiftId != null) {
         final prefs = await SharedPreferences.getInstance(); // Ensure prefs is available
         if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MainHome(openingBalance: 0.0)));
         return;
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}


