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


