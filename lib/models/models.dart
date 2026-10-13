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

  bool get isBogo => mrp > 0 && saleRate > 0 && saleRate <= ((mrp / 2.0) + 0.01);
  bool get hasMultipleBatches => stocks.length > 1;

  Product copyWith({
    String? id,
    String? stockId,
    String? barcode,
    String? name,
    double? price,
    String? productCode,
    double? stockQuantity,
    List<Map<String, dynamic>>? stocks,
    double? mrp,
    double? saleRate,
  }) {
    return Product(
      id ?? this.id,
      stockId ?? this.stockId,
      barcode ?? this.barcode,
      name ?? this.name,
      price ?? this.price,
      productCode: productCode ?? this.productCode,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      stocks: stocks ?? this.stocks,
      mrp: mrp ?? this.mrp,
      saleRate: saleRate ?? this.saleRate,
    );
  }

  Product copyWithBatch(Map<String, dynamic> sMap) {
    double sale = _safeDouble(sMap['stock_sale_rate_a'] ?? sMap['stock_selling_rate'] ?? sMap['sale_rate_a'] ?? sMap['sale_rate'] ?? sMap['price']);
    double mrpVal = _safeDouble(sMap['stock_mrp'] ?? sMap['mrp']);
    double qty = _safeDouble(sMap['stock_quantity'] ?? sMap['quantity'] ?? sMap['available_quantity']);
    String stId = sMap['id']?.toString().trim() ?? sMap['stock_id']?.toString().trim() ?? stockId;
    String bCode = sMap['stock_barcode']?.toString().trim() ?? sMap['barcode']?.toString().trim() ?? barcode;
    if (sale == 0.0 && mrpVal > 0.0) sale = mrpVal;
    if (mrpVal == 0.0 && sale > 0.0) mrpVal = sale;

    return copyWith(
      stockId: stId,
      barcode: bCode.isNotEmpty ? bCode : barcode,
      mrp: mrpVal > 0 ? mrpVal : mrp,
      saleRate: sale > 0 ? sale : saleRate,
      price: sale > 0 ? sale : price,
      stockQuantity: qty,
    );
  }

  static double _safeDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val.trim()) ?? 0.0;
    return 0.0;
  }

  factory Product.fromJson(Map<String, dynamic> json, {String? targetStoreId}) {
    double sale = _safeDouble(json['stock_sale_rate_a'] ?? json['sale_rate_a'] ?? json['sale_rate'] ?? json['price']);
    double mrpVal = _safeDouble(json['stock_mrp'] ?? json['mrp']);
    double qty = _safeDouble(json['stock_quantity'] ?? json['quantity'] ?? json['available_quantity']);
    String pCode = json['product_code']?.toString().trim() ?? json['sku']?.toString().trim() ?? '';
    String stId = json['stock_id']?.toString().trim() ?? '';
    String bCode = json['stock_barcode']?.toString().trim() ?? json['barcode']?.toString().trim() ?? '';
    List<Map<String, dynamic>> parsedStocks = [];

    final cleanTgtStore = (targetStoreId ?? '').trim().toLowerCase();

    if (json['stocks'] is List) {
      final list = json['stocks'] as List;
      for (final item in list) {
        if (item is Map) {
          final sMap = Map<String, dynamic>.from(item);
          final sStore = (sMap['store_id'] ?? sMap['storeId'] ?? '').toString().trim().toLowerCase();
          final effectiveStore = sStore.isNotEmpty
              ? sStore
              : (json['store_id'] ?? json['storeId'] ?? '').toString().trim().toLowerCase();

          // IMPORTANT: If a store is specified, only include stocks for THAT particular store!
          // Exclude batches that belong to other stores so multi-store products don't show wrong store stock.
          if (cleanTgtStore.isNotEmpty && effectiveStore.isNotEmpty && effectiveStore != cleanTgtStore) {
            continue;
          }
          parsedStocks.add(sMap);
        }
      }
    }

    if (parsedStocks.isNotEmpty) {
      final primaryStock = parsedStocks.first;
      sale = _safeDouble(primaryStock['stock_sale_rate_a'] ?? primaryStock['stock_selling_rate'] ?? primaryStock['sale_rate_a'] ?? primaryStock['sale_rate'] ?? primaryStock['price']);
      mrpVal = _safeDouble(primaryStock['stock_mrp'] ?? primaryStock['mrp']);
      qty = parsedStocks.fold<double>(0.0, (sum, s) => sum + _safeDouble(s['stock_quantity'] ?? s['quantity'] ?? s['available_quantity']));
      stId = primaryStock['id']?.toString().trim() ?? primaryStock['stock_id']?.toString().trim() ?? stId;
      final stockBCode = primaryStock['stock_barcode']?.toString().trim() ?? '';
      if (stockBCode.isNotEmpty) {
        bCode = stockBCode;
      }
    } else if (cleanTgtStore.isNotEmpty) {
      // If store is filtered and no matching batches in this store, stock quantity is strictly 0.0
      final topStore = (json['store_id'] ?? json['storeId'] ?? '').toString().trim().toLowerCase();
      if (topStore.isEmpty || topStore != cleanTgtStore || (json['stocks'] is List && (json['stocks'] as List).isNotEmpty)) {
        qty = 0.0;
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
