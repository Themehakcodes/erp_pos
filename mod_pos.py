import re

with open('d:/projects/ErpGoPos/erp_pos/lib/screens/pos_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

pattern = r'      final items = _cart\.map\(\(c\) => \{[\s\S]*?      \};\n'

replacement = """      final items = _cart.map((c) => {
        "product_id": c.product.id,
        "product_stock_id": c.product.stockId.isEmpty ? "00000000-0000-0000-0000-000000000000" : c.product.stockId,
        "product_name": c.product.name,
        "barcode": c.product.barcode,
        "hsn_code": "",
        "quantity": c.quantity,
        "mrp": c.product.price,
        "sale_rate": c.product.price,
        "cost_price": c.product.price,
        "taxable_amount": c.product.price * c.quantity,
        "cgst_percent": 0.0,
        "cgst_amount": 0.0,
        "sgst_percent": 0.0,
        "sgst_amount": 0.0,
        "igst_percent": 0.0,
        "igst_amount": 0.0,
        "tax_amount": 0.0,
        "line_total": c.product.price * c.quantity
      }).toList();
      
      final saleData = {
        "store_id": storeId,
        "shift_id": shiftId,
        "financial_year_id": financialYearId,
        "invoice_date": DateTime.now().toUtc().toIso8601String(),
        "invoice_status": "completed",
        "bill_type": "pos",
        "is_gst_bill": false,
        "total_items": _cart.length,
        "total_quantity": _cart.fold(0.0, (sum, item) => sum + item.quantity),
        "subtotal_amount": amountToCharge,
        "discount_amount": 0.0,
        "taxable_amount": amountToCharge,
        "cgst_amount": 0.0,
        "sgst_amount": 0.0,
        "igst_amount": 0.0,
        "round_off_amount": 0.0,
        "net_amount": amountToCharge,
        "gross_profit_amount": 0.0,
        "remarks": "Flutter POS Terminal",
        "items": items,
        "payments": [
          {
            "payment_method_id": method == 'Cash' ? "e0000000-0000-0000-0000-000000000001" : "e0000000-0000-0000-0000-000000000003",
            "amount_received": amountToCharge,
            "amount_applied": amountToCharge,
            "change_returned": 0.0,
            "amount": amountToCharge,
            "reference_number": ""
          }
        ]
      };
"""

new_content = re.sub(pattern, replacement, content)

with open('d:/projects/ErpGoPos/erp_pos/lib/screens/pos_screen.dart', 'w', encoding='utf-8') as f:
    f.write(new_content)
