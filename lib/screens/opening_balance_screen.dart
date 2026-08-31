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

  void _submit() async {
    final balance = double.tryParse(_amountStr) ?? 0.0;
    
    final prefs = await SharedPreferences.getInstance();
    final storeId = prefs.getString('store_id');
    final terminalId = prefs.getString('terminal_id');
    
    if (storeId == null || terminalId == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device not registered. Please restart app.')));
      return;
    }
    
    try {
      final shift = await ApiService().openShift(storeId, terminalId, balance);
      await prefs.setString('shift_id', shift['id']);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => MainHome(openingBalance: balance)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        if (e.toString().contains('Session expired') || e.toString().contains('Unauthorized') || e.toString().contains('revoked')) {
          await prefs.remove('access_token');
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
        }
      }
    }
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


