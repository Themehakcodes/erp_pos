import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';
import 'splash_loader.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchStores();
  }

  void _fetchStores() async {
    try {
      final stores = await ApiService().getStores();
      setState(() {
        _stores = stores;
        if (_stores.isNotEmpty) {
          _selectedStore = _stores[0]['id'];
        }
        _isLoading = false;
      });
    } catch(e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load stores: $e')));
      }
    }
  }

  void _register() async {
    if (_selectedStore == null) return;
    setState(() => _isLoading = true);
    try {
      if (widget.existingTerminalId != null && widget.existingTerminalId!.isNotEmpty) {
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
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
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
            Text('Device ID: ${widget.deviceId}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('Select Store for this Terminal:'),
            DropdownButton<String>(
              value: _selectedStore,
              items: _stores.map((s) => DropdownMenuItem<String>(
                value: s['id'] as String,
                child: Text(s['name'] ?? s['store_name'] ?? 'Unknown Store'),
              )).toList(),
              onChanged: (val) => setState(() => _selectedStore = val),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _register,
              child: const Text('Link & Start Terminal'),
            )
          ],
        ),
      ),
    );
  }
}
