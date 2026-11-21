import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:nyx_printer_flutter/nyx_printer.dart';
import 'package:nyx_printer_flutter/nyx_printer_definition.dart';

import 'dart:async';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
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

  static List<int> generateShelfLabelBytes(Product product, {bool hideCompanyName = false, bool hideMrp = false}) {
    List<int> bytes = [];
    bytes.addAll([0x1B, 0x40]); // Init
    bytes.addAll([0x1B, 0x61, 0x01]); // Center align

    // Top Store Header in small capital (Font B, Bold)
    if (!hideCompanyName) {
      bytes.addAll([0x1B, 0x4D, 0x01]); // Font B (condensed small font)
      bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
      bytes.addAll("KCSUPERMARKET\n".codeUnits);
      bytes.addAll([0x1B, 0x4D, 0x00]); // Reset to Font A
      bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
    }

    // Product Name
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold
    bytes.addAll([0x1D, 0x21, 0x00]); // Normal size
    bytes.addAll("${product.name}\n".codeUnits);
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
    bytes.addAll("--------------------------------\n".codeUnits);

    // Sale Rate (Prominently displayed)
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
    bytes.addAll([0x1D, 0x21, 0x11]); // Double width & height
    bytes.addAll("Rs ${product.saleRate.toStringAsFixed(2)}\n".codeUnits);

    // MRP at bottom (Double height for readability)
    if (!hideMrp) {
      bytes.addAll([0x1D, 0x21, 0x01]); // Double height
      bytes.addAll("MRP: Rs ${product.mrp.toStringAsFixed(2)}\n".codeUnits);
    }
    bytes.addAll([0x1D, 0x21, 0x00]); // Normal size
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
    bytes.addAll("--------------------------------\n".codeUnits);

    // Compact feed & cut for shelf rack
    bytes.addAll("\n".codeUnits);
    bytes.addAll([0x1D, 0x56, 0x41, 0x00]); // Cut
    return bytes;
  }

  static List<int> generateBarcodeAndLabelBytes(Product product, {bool hideCompanyName = false, bool hideMrp = false}) {
    List<int> bytes = [];
    bytes.addAll([0x1B, 0x40]); // Init
    bytes.addAll([0x1B, 0x61, 0x01]); // Center align

    // Top Store Header in small capital (Font B, Bold)
    if (!hideCompanyName) {
      bytes.addAll([0x1B, 0x4D, 0x01]); // Font B (condensed small font)
      bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
      bytes.addAll("KCSUPERMARKET\n".codeUnits);
      bytes.addAll([0x1B, 0x4D, 0x00]); // Reset to Font A
      bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
    }

    // Product Name
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold
    bytes.addAll([0x1D, 0x21, 0x00]); // Normal size
    bytes.addAll("${product.name}\n".codeUnits);
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold off

    // Price & MRP row (Bold, Double height)
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold
    bytes.addAll([0x1D, 0x21, 0x01]); // Double height
    if (hideMrp) {
      bytes.addAll("RATE: Rs ${product.saleRate.toStringAsFixed(2)}\n\n".codeUnits);
    } else {
      bytes.addAll("RATE: Rs ${product.saleRate.toStringAsFixed(2)} (MRP: Rs ${product.mrp.toStringAsFixed(2)})\n\n".codeUnits);
    }
    bytes.addAll([0x1D, 0x21, 0x00]); // Normal size
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold off

    // 1D Barcode (compact for shelf racks)
    final rawBarcode = product.barcode.isNotEmpty ? product.barcode : (product.id.length >= 8 ? product.id.substring(0, 8) : '100001');
    final cleanBarcode = rawBarcode.replaceAll(RegExp(r'[^A-Za-z0-9\-_.]'), '');

    if (cleanBarcode.isNotEmpty) {
      bytes.addAll([0x1D, 0x68, 48]); // Height = 48 dots (~6mm, compact for racks)
      bytes.addAll([0x1D, 0x77, 2]);  // Module width = 2 (sharp and readable)
      bytes.addAll([0x1D, 0x48, 0x02]); // HRI position: Below barcode
      bytes.addAll([0x1D, 0x66, 0x00]); // HRI font: Font A

      // ESC/POS CODE128 Code Set B prefix '{B'
      final code128Payload = "{B$cleanBarcode".codeUnits;
      bytes.addAll([0x1D, 0x6B, 0x49, code128Payload.length]);
      bytes.addAll(code128Payload);
      bytes.addAll("\n".codeUnits);
    }

    // Compact feed & cut for shelf rack
    bytes.addAll("\n".codeUnits);
    bytes.addAll([0x1D, 0x56, 0x41, 0x00]); // Cut
    return bytes;
  }

  static Future<bool> printShelfLabel(SelectedPrinter? printer, Product product, {int copies = 1, bool? hideCompanyName, bool? hideMrp}) async {
    final prefs = await SharedPreferences.getInstance();
    final hideCompany = hideCompanyName ?? (prefs.getBool('hide_company_name') ?? false);
    final hidePriceMrp = hideMrp ?? (prefs.getBool('hide_mrp') ?? false);
    final bytes = generateShelfLabelBytes(product, hideCompanyName: hideCompany, hideMrp: hidePriceMrp);
    return _sendPrintData(printer, bytes, copies: copies);
  }

  static Future<bool> printBarcodeAndLabel(SelectedPrinter? printer, Product product, {int copies = 1, bool? hideCompanyName, bool? hideMrp}) async {
    final prefs = await SharedPreferences.getInstance();
    final hideCompany = hideCompanyName ?? (prefs.getBool('hide_company_name') ?? false);
    final hidePriceMrp = hideMrp ?? (prefs.getBool('hide_mrp') ?? false);
    final bytes = generateBarcodeAndLabelBytes(product, hideCompanyName: hideCompany, hideMrp: hidePriceMrp);
    return _sendPrintData(printer, bytes, copies: copies);
  }

  static List<int> generateDiscountLabelBytes(Product product, {bool hideCompanyName = false, bool hideMrp = false}) {
    List<int> bytes = [];
    bytes.addAll([0x1B, 0x40]); // Init
    bytes.addAll([0x1B, 0x61, 0x01]); // Center align

    // Top Store Header in small capital (Font B, Bold)
    if (!hideCompanyName) {
      bytes.addAll([0x1B, 0x4D, 0x01]); // Font B (condensed small font)
      bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
      bytes.addAll("KCSUPERMARKET\n".codeUnits);
      bytes.addAll([0x1B, 0x4D, 0x00]); // Reset to Font A
      bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
    }

    final double mrp = product.mrp;
    final double sale = product.saleRate;
    final double savings = mrp - sale;
    final int discountPercent = mrp > 0 && savings > 0 ? ((savings / mrp) * 100).round() : 0;

    // Line 1: Product Name (Bold, 1 line)
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
    bytes.addAll([0x1D, 0x21, 0x00]); // Normal size
    bytes.addAll("${product.name}\n".codeUnits);
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
    bytes.addAll("--------------------------------\n".codeUnits);

    // Line 2: Discount - Large percentage and off in a single row
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
    if (discountPercent > 0) {
      // Large font for the entire line (Double width & double height) - no mid-line size change to guarantee single row!
      bytes.addAll([0x1D, 0x21, 0x11]); // Double width & double height
      bytes.addAll("$discountPercent% off\n".codeUnits);
    } else if (savings > 0) {
      bytes.addAll([0x1D, 0x21, 0x11]); // Double width & height
      bytes.addAll("SAVE Rs ${savings.toStringAsFixed(0)}\n".codeUnits);
    } else {
      bytes.addAll([0x1D, 0x21, 0x11]); // Double width & height
      bytes.addAll("SPECIAL OFFER\n".codeUnits);
    }
    bytes.addAll([0x1D, 0x21, 0x00]); // Normal size
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
    bytes.addAll("--------------------------------\n".codeUnits);

    // Line 3: Sale Rate , MRP (Bold, Double height - larger rates text)
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
    bytes.addAll([0x1D, 0x21, 0x01]); // Double height
    if (hideMrp) {
      bytes.addAll("SALE: Rs ${sale.toStringAsFixed(2)}\n".codeUnits);
    } else {
      bytes.addAll("SALE: Rs ${sale.toStringAsFixed(2)} , MRP: Rs ${mrp.toStringAsFixed(2)}\n".codeUnits);
    }
    bytes.addAll([0x1D, 0x21, 0x00]); // Normal size
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold off

    // Minimal feed & cut for shelf rack (matches standard shelf label height)
    bytes.addAll("\n".codeUnits);
    bytes.addAll([0x1D, 0x56, 0x41, 0x00]); // Cut
    return bytes;
  }

  static Future<bool> printDiscountLabel(SelectedPrinter? printer, Product product, {int copies = 1, bool? hideCompanyName, bool? hideMrp}) async {
    final prefs = await SharedPreferences.getInstance();
    final hideCompany = hideCompanyName ?? (prefs.getBool('hide_company_name') ?? false);
    final hidePriceMrp = hideMrp ?? (prefs.getBool('hide_mrp') ?? false);
    final bytes = generateDiscountLabelBytes(product, hideCompanyName: hideCompany, hideMrp: hidePriceMrp);
    return _sendPrintData(printer, bytes, copies: copies);
  }

  static List<int> generateBogoLabelBytes(Product product, {bool hideCompanyName = false, bool hideMrp = false}) {
    if (!product.isBogo) {
      return generateDiscountLabelBytes(product, hideCompanyName: hideCompanyName, hideMrp: hideMrp);
    }
    List<int> bytes = [];
    bytes.addAll([0x1B, 0x40]); // Init
    bytes.addAll([0x1B, 0x61, 0x01]); // Center align

    // Top Store Header in small capital (Font B, Bold)
    if (!hideCompanyName) {
      bytes.addAll([0x1B, 0x4D, 0x01]); // Font B (condensed small font)
      bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
      bytes.addAll("KCSUPERMARKET\n".codeUnits);
      bytes.addAll([0x1B, 0x4D, 0x00]); // Reset to Font A
      bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
    }

    final double mrp = product.mrp;

    // Line 1: Product Name (Bold, 1 line)
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
    bytes.addAll([0x1D, 0x21, 0x00]); // Normal size
    bytes.addAll("${product.name}\n".codeUnits);
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
    bytes.addAll("--------------------------------\n".codeUnits);

    // Line 2: BOGO Offer Text (Bold, Double width & height - large eye-catching offer)
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
    bytes.addAll([0x1D, 0x21, 0x11]); // Double width & height
    bytes.addAll("BUY 1 GET 1 FREE\n".codeUnits);
    bytes.addAll([0x1D, 0x21, 0x00]); // Normal size
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
    bytes.addAll("--------------------------------\n".codeUnits);

    // Line 3: ONLY MRP for BOGO (Strictly DO NOT show sale rate!)
    if (!hideMrp) {
      bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
      bytes.addAll([0x1D, 0x21, 0x01]); // Double height
      bytes.addAll("MRP: Rs ${mrp.toStringAsFixed(2)}\n".codeUnits);
      bytes.addAll([0x1D, 0x21, 0x00]); // Normal size
      bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
    }

    // Minimal feed & cut for shelf rack (matches standard shelf label height)
    bytes.addAll("\n".codeUnits);
    bytes.addAll([0x1D, 0x56, 0x41, 0x00]); // Cut
    return bytes;
  }

  static Future<bool> printBogoLabel(SelectedPrinter? printer, Product product, {int copies = 1, bool? hideCompanyName, bool? hideMrp}) async {
    if (!product.isBogo) {
      debugPrint('Cannot print BOGO label: sale rate is not half of MRP');
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    final hideCompany = hideCompanyName ?? (prefs.getBool('hide_company_name') ?? false);
    final hidePriceMrp = hideMrp ?? (prefs.getBool('hide_mrp') ?? false);
    final bytes = generateBogoLabelBytes(product, hideCompanyName: hideCompany, hideMrp: hidePriceMrp);
    return _sendPrintData(printer, bytes, copies: copies);
  }

  /// Generates ESC/POS thermal receipt bytes matching POS bill template exactly.
  /// If [isReprint] is true, shows '*** DUPLICATE REPRINT ***' in center bold at the very top.
  static List<int> generateReceiptBytes(BillReceiptData bill, {bool isReprint = false}) {
    final List<int> bytes = [];
    bytes.addAll([0x1B, 0x40]); // ESC @ (Initialize)
    bytes.addAll([0x1B, 0x61, 0x01]); // Center align

    // UPPER DUPLICATE REPRINT (Only if isReprint is true)
    if (isReprint) {
      bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
      bytes.addAll("*** DUPLICATE REPRINT ***\n\n".codeUnits);
      bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
    }

    bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
    bytes.addAll([0x1D, 0x21, 0x11]); // Double width/height
    bytes.addAll("${bill.invoiceNo}\n\n".codeUnits);
    bytes.addAll([0x1D, 0x21, 0x00]); // Normal size
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold off

    final dateDisplay = bill.dateStr.isNotEmpty
        ? (bill.dateStr.length > 16 ? bill.dateStr.substring(0, 16) : bill.dateStr)
        : DateTime.now().toString().substring(0, 16);

    bytes.addAll("Date: $dateDisplay\n".codeUnits);
    bytes.addAll([0x1B, 0x61, 0x00]); // Left align
    bytes.addAll("--------------------------------\n".codeUnits);

    for (var item in bill.items) {
      String nameLine = "${item.name} x${item.quantityString}";
      String priceLine = "Rs ${item.lineTotal.toStringAsFixed(2)}";
      int paddingSize = 32 - nameLine.length - priceLine.length;
      if (paddingSize < 1) paddingSize = 1;
      String padding = " " * paddingSize;
      bytes.addAll("$nameLine$padding$priceLine\n".codeUnits);
    }

    bytes.addAll("--------------------------------\n".codeUnits);

    final double subtotal = bill.subtotal;
    final double roundOff = bill.roundOff;

    if (roundOff.abs() > 0.001) {
      String subtotalTitle = "SUBTOTAL";
      String subtotalVal = "Rs ${subtotal.toStringAsFixed(2)}";
      int padSub = 32 - subtotalTitle.length - subtotalVal.length;
      bytes.addAll(
        "$subtotalTitle${" " * (padSub > 0 ? padSub : 1)}$subtotalVal\n".codeUnits,
      );

      String roundTitle = "ROUND OFF";
      String sign = roundOff > 0 ? "+" : "";
      String roundVal = "$sign${roundOff.toStringAsFixed(2)}";
      int padRound = 32 - roundTitle.length - roundVal.length;
      bytes.addAll(
        "$roundTitle${" " * (padRound > 0 ? padRound : 1)}$roundVal\n".codeUnits,
      );
    }

    bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
    String totalTitle = "TOTAL";
    String totalValue = "Rs ${bill.totalAmount.toStringAsFixed(2)}";
    int pad1 = 32 - totalTitle.length - totalValue.length;
    bytes.addAll(
      "$totalTitle${" " * (pad1 > 0 ? pad1 : 1)}$totalValue\n".codeUnits,
    );
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold off

    String methodTitle = "METHOD";
    String methodVal = bill.method.isNotEmpty ? bill.method : "Cash";
    int pad2 = 32 - methodTitle.length - methodVal.length;
    bytes.addAll(
      "$methodTitle${" " * (pad2 > 0 ? pad2 : 1)}$methodVal\n".codeUnits,
    );

    bytes.addAll("--------------------------------\n".codeUnits);
    bytes.addAll([0x1B, 0x61, 0x01]); // Center align
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold on
    bytes.addAll("Thank You!\n".codeUnits);
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold off
    bytes.addAll("Please visit again\n\n\n\n".codeUnits);
    bytes.addAll([0x1D, 0x56, 0x41, 0x00]); // Cut
    return bytes;
  }

  /// Prints or reprints a complete BillReceiptData object
  static Future<bool> printBillReceipt(
    SelectedPrinter? printer,
    BillReceiptData bill, {
    bool isReprint = false,
  }) async {
    final bytes = generateReceiptBytes(bill, isReprint: isReprint);
    return await _sendPrintData(printer, bytes, copies: 1);
  }

  static Future<bool> _sendPrintData(SelectedPrinter? printer, List<int> bytes, {int copies = 1}) async {
    if (printer == null) {
      debugPrint('No printer selected.');
      return false;
    }
    if (copies < 1) copies = 1;

    // 1. Internal Printer (NYX AIDL or Atpos 1008 Serial)
    if (printer.isInternal) {
      while (_isPrintingHardware) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      _isPrintingHardware = true;
      try {
        final uint8 = Uint8List.fromList(bytes);

        // Try NYX AIDL service
        try {
          var ret = await NyxPrinter.getPrinterStatus();
          if (ret == PrinterStatus.SDK_OK) {
            for (int i = 0; i < copies; i++) {
              await NyxPrinter.printEscposData(uint8);
              if (copies > 1) await Future.delayed(const Duration(milliseconds: 150));
            }
            return true;
          }
        } catch (_) {}

        // Fallback to internal native serial printer (Atpos 1008 via /dev/ttyS*)
        try {
          const nativeChannel = MethodChannel('pos_printer');
          for (int i = 0; i < copies; i++) {
            final res = await nativeChannel.invokeMethod('printBytes', {'bytes': uint8});
            if (res == true) {
              if (copies > 1) await Future.delayed(const Duration(milliseconds: 150));
            }
          }
          return true;
        } catch (e) {
          debugPrint('Internal serial printer error: $e');
        }
      } catch (e) {
        debugPrint('Internal print error: $e');
      } finally {
        _isPrintingHardware = false;
      }
      return false;
    }

    // 2. Bluetooth / USB Printer
    while (_isPrintingHardware) {
      await Future.delayed(const Duration(milliseconds: 200));
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
        final uint8 = Uint8List.fromList(bytes);
        for (int i = 0; i < copies; i++) {
          await printerManager.send(type: type, bytes: uint8).timeout(const Duration(seconds: 10));
          if (copies > 1) await Future.delayed(const Duration(milliseconds: 150));
        }
        success = true;
      }
      try { await PrinterManager.instance.disconnect(type: type); } catch (_) {}
    } catch (e) {
      debugPrint('BT/USB label print error: $e');
      try { await PrinterManager.instance.disconnect(type: printer.type!); } catch (_) {}
    } finally {
      _isPrintingHardware = false;
    }
    return success;
  }
}
