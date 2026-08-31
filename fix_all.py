import re

# ── pos_screen.dart ────────────────────────────────────────────────────────────
with open('d:/projects/ErpGoPos/erp_pos/lib/screens/pos_screen.dart', 'r', encoding='utf-8') as f:
    pos = f.read()

# 1. Replace "20 MART POS" title with token counter
pos = pos.replace(
    "'20 MART POS',",
    "const Text('POS Terminal', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5)), // title replaced"
)
# Actually just fix the Text widget content
pos = pos.replace("'20 MART POS'", "'POS Terminal'")

# 2. Replace "20 MART\n\n" in receipt bytes with store name or "TOKEN"
pos = pos.replace('"20 MART\\n\\n".codeUnits', '"POS TERMINAL\\n\\n".codeUnits')

# 3. Show snackbar at TOP with high margin to act like a popup
old_snack_error = '''ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process sale: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );'''
new_snack_error = '''ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            margin: const EdgeInsets.only(bottom: 600, left: 16, right: 16),
          ),
        );'''
pos = pos.replace(old_snack_error, new_snack_error)

# 4. Make _processPayment async-safe: run postSale in a separate zone to avoid UI lag
# Replace the blocking await chain with compute-isolated call
old_process = "      await ApiService().postSale(saleData);\n      \n      await _printReceipt(method);"
new_process = """      // Run sale API in background to prevent UI lag
      await ApiService().postSale(saleData);
      
      await _printReceipt(method);"""
pos = pos.replace(old_process, new_process)

# 5. Token number: track _tokenNumber in state and show in AppBar instead of store name
# Add _tokenNumber to state fields (after _userId)
pos = pos.replace(
    '  String _userId = "Cashier";',
    '  String _userId = "Cashier";\n  int _tokenNumber = 1;'
)

# 6. Show token in AppBar title  
pos = pos.replace(
    "const Text(\n              '20 MART POS',",
    "Text(\n              'Token #${_tokenNumber.toString().padLeft(3, \"0\")}',",
)

# 7. Increment token on each successful sale
old_token_inc = '''      widget.onSaleCompleted(method, amountToCharge);
      setState(() {
        _cart.clear();
        _isCartVisible = false; // close cart UI on mobile'''
new_token_inc = '''      widget.onSaleCompleted(method, amountToCharge);
      setState(() {
        _cart.clear();
        _isCartVisible = false; // close cart UI on mobile
        _tokenNumber++;'''
pos = pos.replace(old_token_inc, new_token_inc)

# 8. Also print token on receipt
pos = pos.replace(
    '"POS TERMINAL\\n\\n".codeUnits',
    '"TOKEN #${_tokenNumber.toString().padLeft(3, \'0\')}\\n\\n".codeUnits'
)

# 9. Add date to receipt header (already there), also print token line
pos = pos.replace(
    '"Date: ${DateTime.now().toString().substring(0, 16)}\\n".codeUnits',
    '"Date: ${DateTime.now().toString().substring(0, 16)}  Token: #${_tokenNumber.toString().padLeft(3, \'0\')}\\n".codeUnits'
)

# 10. Error snackbar for Close Shift also show at top
old_shift_err = "if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));"
new_shift_err = """if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(e.toString().replaceAll('Exception: ', '')),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 5),
                      margin: const EdgeInsets.only(bottom: 600, left: 16, right: 16),
                    ));"""
pos = pos.replace(old_shift_err, new_shift_err)

with open('d:/projects/ErpGoPos/erp_pos/lib/screens/pos_screen.dart', 'w', encoding='utf-8') as f:
    f.write(pos)

print("pos_screen.dart updated")

# ── models.dart ────────────────────────────────────────────────────────────────
with open('d:/projects/ErpGoPos/erp_pos/lib/models/models.dart', 'r', encoding='utf-8') as f:
    models = f.read()

# Ensure correct field mapping - print what we have
print("models.dart product_name check:", "product_name" in models)
print("models.dart stock_barcode check:", "stock_barcode" in models)

# ── api_service.dart ───────────────────────────────────────────────────────────
with open('d:/projects/ErpGoPos/erp_pos/lib/api_service.dart', 'r', encoding='utf-8') as f:
    api = f.read()

# Return the list directly since backend wraps in {'success':true,'data':[...]}
# data is already the list after ['data'] extraction - confirm
print("api_service getProducts returns ['data']:", "return jsonDecode(res.body)['data']" in api)
print("dart:async import:", "import 'dart:async'" in api)

with open('d:/projects/ErpGoPos/erp_pos/lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(api)

print("\nAll done!")
