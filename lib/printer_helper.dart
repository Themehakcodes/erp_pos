import 'package:flutter/material.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:nyx_printer_flutter/nyx_printer.dart';
import 'package:nyx_printer_flutter/nyx_printer_definition.dart';

import 'dart:async';
import 'dart:typed_data';
import 'models/models.dart';

class PrinterHelper {
  // Global hardware lock to prevent Bluetooth stack from crashing and lagging the app
  static bool _isPrintingHardware = false;

  static Future<void> printShiftReceipt(SelectedPrinter? printer, bool isOpening, double amount, String storeId, String terminalId) async {
    if (printer == null) {
      debugPrint('No printer selected. Skipping shift receipt.');
      return;
    }

    final dateStr = DateTime.now().toString().substring(0, 16);
    final title = isOpening ? 'SHIFT OPENED' : 'SHIFT CLOSED';
    
    // 1. Internal AIDL Printer (NYX)
    if (printer.isInternal) {
      if (_isPrintingHardware) {
        debugPrint('AIDL Hardware is busy. Skipping overlapping shift print job.');
        return;
      }
      _isPrintingHardware = true;
      try {
        var ret = await NyxPrinter.getPrinterStatus();
        if (ret == PrinterStatus.SDK_OK) {
          // Generate ESC/POS bytes manually
          List<int> bytes = [];
          
          // Initialize printer
          bytes.addAll([0x1B, 0x40]);
          
          // Center align
          bytes.addAll([0x1B, 0x61, 0x01]);
          // Bold on
          bytes.addAll([0x1B, 0x45, 0x01]);
          // Double width/height
          bytes.addAll([0x1D, 0x21, 0x11]);
          bytes.addAll("$title\n\n".codeUnits);
          
          // Left align, Normal size, Bold off
          bytes.addAll([0x1D, 0x21, 0x00]);
          bytes.addAll([0x1B, 0x61, 0x00]);
          bytes.addAll([0x1B, 0x45, 0x00]);
          
          bytes.addAll("Date: $dateStr\n".codeUnits);
          bytes.addAll("--------------------------------\n".codeUnits);
          
          // Bold on
          bytes.addAll([0x1B, 0x45, 0x01]);
          bytes.addAll("AMOUNT: Rs ${amount.toStringAsFixed(2)}\n".codeUnits);
          // Bold off
          bytes.addAll([0x1B, 0x45, 0x00]);
          
          bytes.addAll("--------------------------------\n".codeUnits);
          
          // Center align
          bytes.addAll([0x1B, 0x61, 0x01]);
          bytes.addAll("Signature:\n\n\n\n_______________________\n\n\n\n".codeUnits);
          
          // Cut paper
          bytes.addAll([0x1D, 0x56, 0x41, 0x00]);

          await NyxPrinter.printEscposData(Uint8List.fromList(bytes));
          debugPrint('Shift Receipt Printed via NYX AIDL (ESC/POS)');
        } else {
          debugPrint('NYX printer service not available or error.');
        }
      } catch (e) {
        debugPrint('NYX printer error: $e');
      } finally {
        _isPrintingHardware = false;
      }
      return;
    }

    // 2. Bluetooth/USB Printer
    while (_isPrintingHardware) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    _isPrintingHardware = true;

    unawaited(
      Future(() async {
        try {
          var printerManager = PrinterManager.instance;
          final device = printer.device!;
          final type = printer.type!;

          dynamic inputParams;
          if (type == PrinterType.usb) {
            inputParams = UsbPrinterInput(name: device.name, vendorId: device.vendorId, productId: device.productId);
          } else if (type == PrinterType.bluetooth) {
            inputParams = BluetoothPrinterInput(name: device.name, address: device.address!, isBle: false, autoConnect: false);
          } else {
            _isPrintingHardware = false;
            return;
          }

          bool isConnected = false;
          try {
            isConnected = (await printerManager.connect(type: type, model: inputParams).timeout(const Duration(seconds: 8))) == true;
          } catch (e) {
            debugPrint('BT connect timeout/error: $e');
          }

          if (isConnected) {
            // Generate ESC/POS bytes manually
            List<int> bytes = [];
            
            // Initialize printer
            bytes.addAll([0x1B, 0x40]);
            
            // Center align
            bytes.addAll([0x1B, 0x61, 0x01]);
            // Bold on
            bytes.addAll([0x1B, 0x45, 0x01]);
            // Double width/height
            bytes.addAll([0x1D, 0x21, 0x11]);
            bytes.addAll("$title\n\n".codeUnits);
            
            // Left align, Normal size, Bold off
            bytes.addAll([0x1D, 0x21, 0x00]);
            bytes.addAll([0x1B, 0x61, 0x00]);
            bytes.addAll([0x1B, 0x45, 0x00]);
            
            bytes.addAll("Date: $dateStr\n".codeUnits);
            bytes.addAll("--------------------------------\n".codeUnits);
            
            // Bold on
            bytes.addAll([0x1B, 0x45, 0x01]);
            bytes.addAll("AMOUNT: Rs ${amount.toStringAsFixed(2)}\n".codeUnits);
            // Bold off
            bytes.addAll([0x1B, 0x45, 0x00]);
            
            bytes.addAll("--------------------------------\n".codeUnits);
            
            // Center align
            bytes.addAll([0x1B, 0x61, 0x01]);
            bytes.addAll("Signature:\n\n\n\n_______________________\n\n\n\n".codeUnits);
            
            // Cut paper
            bytes.addAll([0x1D, 0x56, 0x41, 0x00]);

            await printerManager.send(type: type, bytes: Uint8List.fromList(bytes)).timeout(const Duration(seconds: 10));
            debugPrint('BT/USB shift print sent successfully.');
          }
          
          try { await PrinterManager.instance.disconnect(type: type); } catch (_) {}
          _isPrintingHardware = false;
        } catch (e) {
          try { await PrinterManager.instance.disconnect(type: printer.type!); } catch (_) {}
          _isPrintingHardware = false;
        }
      }).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          try { PrinterManager.instance.disconnect(type: printer.type!); } catch (_) {}
          _isPrintingHardware = false;
        },
      ),
    );
  }

  static Future<bool> printTestReceipt(SelectedPrinter? printer) async {
    if (printer == null) {
      debugPrint('No printer selected.');
      return false;
    }

    final dateStr = DateTime.now().toString().substring(0, 16);
    
    // 1. Internal AIDL Printer (NYX)
    if (printer.isInternal) {
      if (_isPrintingHardware) {
        return false;
      }
      _isPrintingHardware = true;
      try {
        var ret = await NyxPrinter.getPrinterStatus();
        if (ret == PrinterStatus.SDK_OK) {
          List<int> bytes = [];
          bytes.addAll([0x1B, 0x40]); // Init
          bytes.addAll([0x1B, 0x61, 0x01]); // Center
          bytes.addAll([0x1B, 0x45, 0x01]); // Bold
          bytes.addAll([0x1D, 0x21, 0x11]); // Double
          bytes.addAll("PRINTER TEST OK\n\n".codeUnits);
          bytes.addAll([0x1D, 0x21, 0x00]); // Normal
          bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
          bytes.addAll("Date: $dateStr\n\n\n\n".codeUnits);
          
          // Cut paper
          bytes.addAll([0x1D, 0x56, 0x41, 0x00]);

          await NyxPrinter.printEscposData(Uint8List.fromList(bytes));
          return true;
        }
      } catch (e) {
        debugPrint('NYX test print error: $e');
      } finally {
        _isPrintingHardware = false;
      }
      return false;
    }

    // 2. Bluetooth/USB Printer
    while (_isPrintingHardware) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    _isPrintingHardware = true;
    bool success = false;

    try {
      var printerManager = PrinterManager.instance;
      final device = printer.device!;
      final type = printer.type!;
      dynamic inputParams;
      
      if (type == PrinterType.usb) {
        inputParams = UsbPrinterInput(name: device.name, vendorId: device.vendorId, productId: device.productId);
      } else if (type == PrinterType.bluetooth) {
        inputParams = BluetoothPrinterInput(name: device.name, address: device.address!, isBle: false, autoConnect: false);
      } else {
        _isPrintingHardware = false;
        return false;
      }

      bool isConnected = false;
      try {
        isConnected = (await printerManager.connect(type: type, model: inputParams).timeout(const Duration(seconds: 8))) == true;
      } catch (_) {}

      if (isConnected) {
        List<int> bytes = [];
        bytes.addAll([0x1B, 0x40]); // Init
        bytes.addAll([0x1B, 0x61, 0x01]); // Center
        bytes.addAll([0x1B, 0x45, 0x01]); // Bold
        bytes.addAll([0x1D, 0x21, 0x11]); // Double
        bytes.addAll("PRINTER TEST OK\n\n".codeUnits);
        bytes.addAll([0x1D, 0x21, 0x00]); // Normal
        bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
        bytes.addAll("Date: $dateStr\n\n\n\n".codeUnits);
        bytes.addAll([0x1D, 0x56, 0x41, 0x00]); // Cut

        await printerManager.send(type: type, bytes: Uint8List.fromList(bytes)).timeout(const Duration(seconds: 10));
        success = true;
      }
      try { await PrinterManager.instance.disconnect(type: type); } catch (_) {}
    } catch (_) {
      try { await PrinterManager.instance.disconnect(type: printer.type!); } catch (_) {}
    } finally {
      _isPrintingHardware = false;
    }
    return success;
  }
}
