class Product {
  final String id;
  final String name;
  final double price;
  final String stockId;
  final String barcode;
  final double purchaseRate;
  final String hsnCode;
  
  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.stockId,
    required this.barcode,
    required this.purchaseRate,
    required this.hsnCode,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    double saleRate = (json['stock_sale_rate_a'] ?? json['sale_rate_a'] ?? 0.0).toDouble();
    double purRate = (json['stock_purchase_rate'] ?? json['purchase_rate'] ?? 0.0).toDouble();
    String stId = '';
    
    if (json['stocks'] is List && (json['stocks'] as List).isNotEmpty) {
       var stk = (json['stocks'] as List)[0];
       if (stk is Map) {
         if (stk['stock_sale_rate_a'] != null) {
           saleRate = (stk['stock_sale_rate_a'] as num).toDouble();
         }
         if (stk['stock_purchase_rate'] != null) {
           purRate = (stk['stock_purchase_rate'] as num).toDouble();
         }
         stId = stk['id']?.toString() ?? '';
       }
    }

    return Product(
      id: json['id'] ?? '',
      name: json['product_name'] ?? 'Unknown',
      price: saleRate,
      stockId: stId,
      barcode: json['barcode'] ?? '',
      purchaseRate: purRate,
      hsnCode: json['hsn_code'] ?? '',
    );
  }
}

class CartItem {
  final Product product;
  int quantity;
  CartItem(this.product, this.quantity);
}
