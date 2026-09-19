import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';

class Product {
  final String id;
  final String productCode;
  final String stockId;
  final String barcode;
  final String name;
  final double price;
  final double mrp;
  final double saleRate;
  final double stockQuantity;
  final List<Map<String, dynamic>> stocks;

  Product(
    this.id,
    this.stockId,
    this.barcode,
    this.name,
    this.price, {
    this.productCode = '',
    this.stockQuantity = 0.0,
    this.stocks = const [],
    double? mrp,
    double? saleRate,
  })  : mrp = mrp ?? price,
        saleRate = saleRate ?? price;

  static double _safeDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val.trim()) ?? 0.0;
    return 0.0;
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    double sale = _safeDouble(json['stock_sale_rate_a'] ?? json['sale_rate_a'] ?? json['sale_rate'] ?? json['price']);
    double mrpVal = _safeDouble(json['stock_mrp'] ?? json['mrp']);
    double qty = _safeDouble(json['stock_quantity'] ?? json['quantity'] ?? json['available_quantity']);
    String pCode = json['product_code']?.toString().trim() ?? json['sku']?.toString().trim() ?? '';
    String stId = json['stock_id']?.toString().trim() ?? '';
    String bCode = json['stock_barcode']?.toString().trim() ?? json['barcode']?.toString().trim() ?? '';
    List<Map<String, dynamic>> parsedStocks = [];

    if (json['stocks'] is List) {
      final list = json['stocks'] as List;
      for (final item in list) {
        if (item is Map) {
          final sMap = Map<String, dynamic>.from(item);
          parsedStocks.add(sMap);
          if (sale == 0.0 && sMap['stock_sale_rate_a'] != null) {
            sale = _safeDouble(sMap['stock_sale_rate_a']);
          }
          if (mrpVal == 0.0 && sMap['stock_mrp'] != null) {
            mrpVal = _safeDouble(sMap['stock_mrp']);
          }
          if (qty == 0.0 && sMap['stock_quantity'] != null) {
            qty = _safeDouble(sMap['stock_quantity']);
          }
          if (stId.isEmpty && sMap['id'] != null) {
            stId = sMap['id'].toString();
          }
          if (bCode.isEmpty && sMap['stock_barcode'] != null && sMap['stock_barcode'].toString().trim().isNotEmpty) {
            bCode = sMap['stock_barcode'].toString().trim();
          }
        }
      }
    }

    // Fallbacks
    if (bCode.isEmpty && pCode.isNotEmpty) {
      bCode = pCode;
    }
    if (sale == 0.0 && mrpVal > 0.0) sale = mrpVal;
    if (mrpVal == 0.0 && sale > 0.0) mrpVal = sale;

    return Product(
      json['id']?.toString() ?? '',
      stId,
      bCode,
      json['product_name']?.toString() ?? json['name']?.toString() ?? 'Unknown',
      sale,
      productCode: pCode,
      stockQuantity: qty,
      stocks: parsedStocks,
      mrp: mrpVal,
      saleRate: sale,
    );
  }
}

class CartItem {
  final Product product;
  int quantity;
  CartItem(this.product, this.quantity);
}

class SelectedPrinter {
  final PrinterDevice? device;
  final PrinterType? type;
  final bool isInternal;

  SelectedPrinter({this.device, this.type, this.isInternal = false});

  Map<String, dynamic> toJson() {
    if (isInternal) {
      return {'isInternal': true};
    }
    return {
      'name': device?.name,
      'address': device?.address,
      'vendorId': device?.vendorId,
      'productId': device?.productId,
      'type': type == PrinterType.usb ? 'usb' : 'bluetooth',
      'isInternal': false,
    };
  }

  factory SelectedPrinter.fromJson(Map<String, dynamic> json) {
    if (json['isInternal'] == true) {
      return SelectedPrinter(isInternal: true);
    }
    PrinterDevice d = PrinterDevice(
      name: json['name'],
      address: json['address'],
      vendorId: json['vendorId'],
      productId: json['productId'],
    );
    PrinterType t = json['type'] == 'usb' ? PrinterType.usb : PrinterType.bluetooth;
    return SelectedPrinter(device: d, type: t, isInternal: false);
  }
}
