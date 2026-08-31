import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'dart:convert';
import 'dart:async';
import '../api_service.dart';
import '../models/models.dart';

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
  static const _printerChannel = MethodChannel('pos_printer');

  final List<PrinterDevice> _usbPrinters = [];
  final List<PrinterDevice> _btPrinters = [];
  bool _isScanning = false;
  String? _deviceId;
  StreamSubscription? _usbSubscription;
  StreamSubscription? _btSubscription;
  bool _isTesting = false;
  String _testResult = '';
  String? _availablePort;

  @override
  void initState() {
    super.initState();
    _scanPrinters();
    _loadDeviceId();
    _detectPort();
  }

  Future<void> _loadDeviceId() async {
    final id = await ApiService().getDeviceIdentifier();
    setState(() => _deviceId = id);
  }

  Future<void> _detectPort() async {
    try {
      final port = await _printerChannel.invokeMethod<String?>('getAvailablePort');
      setState(() => _availablePort = port);
    } catch (_) {
      setState(() => _availablePort = null);
    }
  }

  void _scanPrinters() {
    if (_isScanning) return;

    setState(() {
      _usbPrinters.clear();
      _btPrinters.clear();
      _isScanning = true;
    });

    var printerManager = PrinterManager.instance;

    _usbSubscription = printerManager
        .discovery(type: PrinterType.usb, isBle: false)
        .listen((device) {
      if (mounted && !_usbPrinters.any((p) => p.name == device.name)) {
        setState(() => _usbPrinters.add(device));
      }
    });

    _btSubscription = printerManager
        .discovery(type: PrinterType.bluetooth, isBle: false)
        .listen((device) {
      if (mounted && !_btPrinters.any((p) => p.address == device.address)) {
        setState(() => _btPrinters.add(device));
      }
    });

    // Stop after 5 seconds and cancel streams to prevent lag
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _usbSubscription?.cancel();
        _btSubscription?.cancel();
        setState(() => _isScanning = false);
      }
    });
  }

  Future<void> _testInternalPrint() async {
    setState(() { _isTesting = true; _testResult = ''; });
    try {
      final success = await _printerChannel.invokeMethod<bool>('testPrinter');
      setState(() => _testResult = success == true ? '✅ Internal printer OK!' : '❌ Internal print failed');
    } on PlatformException catch (e) {
      setState(() => _testResult = '❌ Error: ${e.message}');
    } catch (e) {
      setState(() => _testResult = '❌ $e');
    } finally {
      setState(() => _isTesting = false);
    }
  }

  @override
  void dispose() {
    _usbSubscription?.cancel();
    _btSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        actions: [
          IconButton(
            icon: _isScanning
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _scanPrinters,
            tooltip: 'Rescan Printers',
          ),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          margin: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Printer Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [

                    // --- INTERNAL PRINTER (Atpos 1008 built-in) ---
                    if (_availablePort != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text('INTERNAL PRINTER', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.green.shade700)),
                      ),
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: widget.currentPrinter?.isInternal == true ? Colors.green.shade50 : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: widget.currentPrinter?.isInternal == true ? Colors.green.shade300 : Colors.grey.shade300),
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              leading: Icon(Icons.print, color: widget.currentPrinter?.isInternal == true ? Colors.green.shade700 : Colors.grey),
                              title: const Text('Built-in Hardware Printer'),
                              subtitle: Text('Port: $_availablePort'),
                              trailing: widget.currentPrinter?.isInternal == true ? const Icon(Icons.check_circle, color: Colors.green) : null,
                              onTap: () => widget.onPrinterSelected(SelectedPrinter(isInternal: true)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: _isTesting
                                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                          : const Icon(Icons.receipt, size: 16),
                                      label: Text(_isTesting ? 'Printing...' : 'Test Print'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green.shade600,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: _isTesting ? null : _testInternalPrint,
                                    ),
                                  ),
                                  if (_testResult.isNotEmpty) ...[
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(_testResult, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _testResult.startsWith('✅') ? Colors.green.shade800 : Colors.red.shade800)),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 20),
                    ],

                    // --- BLUETOOTH PRINTERS ---
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text('BLUETOOTH DEVICES', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.indigo.shade700)),
                    ),
                    if (_btPrinters.isEmpty && !_isScanning && (widget.currentPrinter?.type != PrinterType.bluetooth))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('No Bluetooth printers found. Tap refresh to scan.', style: TextStyle(color: Colors.grey.shade600)),
                      ),
                    
                    // Always show the explicitly saved Bluetooth printer if it exists
                    if (widget.currentPrinter?.type == PrinterType.bluetooth && widget.currentPrinter?.device != null)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: const Icon(Icons.bluetooth_connected, color: Colors.indigo),
                        title: Text(widget.currentPrinter!.device!.name ?? 'Saved Bluetooth Device'),
                        subtitle: Text('${widget.currentPrinter!.device!.address} (Saved)'),
                        trailing: const Icon(Icons.check_circle, color: Colors.indigo),
                        onTap: () => widget.onPrinterSelected(widget.currentPrinter!),
                      ),

                    // Show other scanned printers, filtering out the saved one to avoid duplicates
                    ..._btPrinters.where((d) => d.address != widget.currentPrinter?.device?.address).map((device) {
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: const Icon(Icons.bluetooth, color: Colors.grey),
                        title: Text(device.name ?? 'Unknown Device'),
                        subtitle: Text(device.address ?? ''),
                        onTap: () => widget.onPrinterSelected(SelectedPrinter(device: device, type: PrinterType.bluetooth)),
                      );
                    }),

                    const Divider(height: 20),

                    // --- USB PRINTERS ---
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text('USB DEVICES', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.blue.shade700)),
                    ),
                    if (_usbPrinters.isEmpty && !_isScanning && (widget.currentPrinter?.type != PrinterType.usb))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('No USB printers found.', style: TextStyle(color: Colors.grey.shade600)),
                      ),
                      
                    // Always show the explicitly saved USB printer if it exists
                    if (widget.currentPrinter?.type == PrinterType.usb && widget.currentPrinter?.device != null)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: const Icon(Icons.usb, color: Colors.blue),
                        title: Text(widget.currentPrinter!.device!.name ?? 'Saved USB Device'),
                        subtitle: Text('Vendor: ${widget.currentPrinter!.device!.vendorId}  Product: ${widget.currentPrinter!.device!.productId} (Saved)'),
                        trailing: const Icon(Icons.check_circle, color: Colors.blue),
                        onTap: () => widget.onPrinterSelected(widget.currentPrinter!),
                      ),

                    // Show other scanned printers, filtering out the saved one to avoid duplicates
                    ..._usbPrinters.where((d) => d.name != widget.currentPrinter?.device?.name).map((device) {
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: const Icon(Icons.usb, color: Colors.grey),
                        title: Text(device.name ?? 'Unknown USB'),
                        subtitle: Text('Vendor: ${device.vendorId}  Product: ${device.productId}'),
                        onTap: () => widget.onPrinterSelected(SelectedPrinter(device: device, type: PrinterType.usb)),
                      );
                    }),

                    const Divider(height: 24),

                    // --- DEVICE ID ---
                    if (_deviceId != null) ...[
                      Text('DEVICE INFORMATION', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.blueGrey.shade700)),
                      const SizedBox(height: 6),
                      SelectableText('Device ID: $_deviceId', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                    ],
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
