import os
import re

def split_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Define the directories
    lib_dir = os.path.dirname(filepath)
    models_dir = os.path.join(lib_dir, 'models')
    screens_dir = os.path.join(lib_dir, 'screens')
    
    os.makedirs(models_dir, exist_ok=True)
    os.makedirs(screens_dir, exist_ok=True)

    # We will just write new files for now and leave main.dart to be replaced later.

    models_content = """import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';

class Product {
  final String id;
  final String name;
  final double price;
  final String barcode;
  final String stockId;

  Product({required this.id, required this.name, required this.price, required this.barcode, required this.stockId});

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown',
      price: (json['sale_rate'] ?? json['price'] ?? 0).toDouble(),
      barcode: json['barcode'] ?? '',
      stockId: json['stock_id'] ?? '',
    );
  }
}

class CartItem {
  final Product product;
  int quantity;
  CartItem(this.product, this.quantity);
}

enum PrinterType { bluetooth, usb }

class SelectedPrinter {
  final PrinterDevice device;
  final PrinterType type;
  SelectedPrinter(this.device, this.type);
}
"""
    with open(os.path.join(models_dir, 'models.dart'), 'w', encoding='utf-8') as f:
        f.write(models_content)

    print("Refactoring prepared models.dart")

if __name__ == '__main__':
    split_file('lib/main.dart')
