import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';

class Product {
  final String id;
  final String stockId;
  final String barcode;
  final String name;
  final double price;
  Product(this.id, this.stockId, this.barcode, this.name, this.price);

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      json['id'] ?? '',
      json['stock_id'] ?? '',
      json['stock_barcode'] ?? json['barcode'] ?? '',
      json['product_name'] ?? json['name'] ?? 'Unknown',
      (json['stock_sale_rate_a'] ?? json['sale_rate'] ?? json['mrp'] ?? 0.0).toDouble(),
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
