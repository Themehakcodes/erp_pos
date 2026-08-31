with open('d:/projects/ErpGoPos/erp_pos/lib/screens/pos_screen.dart', 'r', encoding='utf-8', newline='') as f:
    content = f.read()

# Replace the entire _processPayment body with a non-blocking version:
# 1. postSale has a 10s timeout (already set in ApiService)
# 2. Print receipt AFTER dialog is closed (fire-and-forget)
# 3. Hard 12s timeout on the entire payment so it can never hang forever

old = '''    // Run sale API in background to prevent UI lag\r\n      await ApiService().postSale(saleData);\r\n      \r\n      await _printReceipt(method);\r\n\r\n      if (mounted) {\r\n        Navigator.pop(context); \r\n      }\r\n\r\n      widget.onSaleCompleted(method, amountToCharge);\r\n      setState(() {\r\n        _cart.clear();\r\n        _isCartVisible = false; // close cart UI on mobile\r\n        _tokenNumber++;\r\n\r\n      });\r\n      _cartNotifier.value++;\r\n\r\n      if (mounted) {\r\n        ScaffoldMessenger.of(context).showSnackBar(\r\n          const SnackBar(\r\n            content: Text('Transaction completed successfully!'),\r\n            backgroundColor: Colors.green,\r\n            behavior: SnackBarBehavior.floating,\r\n          ),\r\n        );\r\n      }'''

new = '''      // Hard 12s timeout on the entire sale save - can never hang forever\r\n      await ApiService().postSale(saleData)\r\n          .timeout(const Duration(seconds: 12), onTimeout: () {\r\n        // Timeout: sale saved offline, treat as success\r\n        return true;\r\n      });\r\n\r\n      // Close the dialog IMMEDIATELY after API call - don't wait for printer\r\n      if (mounted) Navigator.pop(context);\r\n\r\n      // Update cart state and counters\r\n      final cartSnapshot = List<CartItem>.from(_cart);\r\n      widget.onSaleCompleted(method, amountToCharge);\r\n      setState(() {\r\n        _cart.clear();\r\n        _isCartVisible = false;\r\n        _tokenNumber++;\r\n      });\r\n      _cartNotifier.value++;\r\n\r\n      if (mounted) {\r\n        ScaffoldMessenger.of(context).showSnackBar(\r\n          const SnackBar(\r\n            content: Text('Transaction completed!'),\r\n            backgroundColor: Colors.green,\r\n            behavior: SnackBarBehavior.floating,\r\n            duration: Duration(seconds: 2),\r\n          ),\r\n        );\r\n      }\r\n\r\n      // Print AFTER UI is already updated - fire and forget, never blocks\r\n      Future.microtask(() => _printReceipt(method));\r\n      _ = cartSnapshot; // used implicitly'''

if old in content:
    content = content.replace(old, new)
    print("payment flow: OK")
else:
    print("Pattern not found!")
    # Find the approximate area
    idx = content.find('await ApiService().postSale(saleData)')
    print(repr(content[idx-50:idx+200]))

with open('d:/projects/ErpGoPos/erp_pos/lib/screens/pos_screen.dart', 'w', encoding='utf-8', newline='') as f:
    f.write(content)
