import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';
import '../models/models.dart';
import '../printer_helper.dart';

class BarcodePrintScreen extends StatefulWidget {
  final SelectedPrinter? selectedPrinter;

  const BarcodePrintScreen({super.key, this.selectedPrinter});

  @override
  State<BarcodePrintScreen> createState() => _BarcodePrintScreenState();
}

class _BarcodePrintScreenState extends State<BarcodePrintScreen> {
  final TextEditingController _barcodeCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Product? _product;
  bool _isLoading = false;
  bool _isSearchingSuggestions = false;
  bool _isPrinting = false;
  int _copies = 1;
  String _statusMessage = '';
  bool _isError = false;
  int _selectedPreviewMode = 0; // 0 = Discount Tag, 1 = BOGO Tag, 2 = Shelf Label, 3 = Barcode Tag

  String _currentStoreId = '';
  String _currentStoreName = '';

  bool _hideMrp = false;
  bool _hideCompanyName = false;

  Timer? _debounceTimer;
  List<Product> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _loadStoreInfo();
  }

  Future<void> _loadStoreInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final sId = prefs.getString('store_id') ?? '';
    var sName = prefs.getString('store_name') ?? '';
    _hideMrp = prefs.getBool('hide_mrp') ?? false;
    _hideCompanyName = prefs.getBool('hide_company_name') ?? false;

    if (sName.isEmpty && sId.isNotEmpty) {
      try {
        final stores = await ApiService().getStores();
        for (final st in stores) {
          if (st is Map && st['id']?.toString().toLowerCase() == sId.toLowerCase()) {
            sName = (st['store_name'] ?? st['name'] ?? '').toString();
            if (sName.isNotEmpty) {
              await prefs.setString('store_name', sName);
            }
            break;
          }
        }
      } catch (_) {}
    }

    _currentStoreId = sId;
    _currentStoreName = sName;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _ensureStoreLoaded() async {
    if (_currentStoreId.isEmpty) {
      await _loadStoreInfo();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _barcodeCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    final query = val.trim();
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _isSearchingSuggestions = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      await _ensureStoreLoaded();
      setState(() => _isSearchingSuggestions = true);
      try {
        final list = await ApiService().searchProducts(query, limit: 15);
        if (mounted) {
          setState(() {
            _suggestions = list.map((e) => Product.fromJson(e, targetStoreId: _currentStoreId)).toList();
            _isSearchingSuggestions = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearchingSuggestions = false);
      }
    });
  }

  Future<void> _selectProduct(Product prod) async {
    await _ensureStoreLoaded();
    final cleanTgtStore = _currentStoreId.trim().toLowerCase();
    final storeBatches = prod.stocks.where((b) {
      final sStore = (b['store_id'] ?? b['storeId'] ?? '').toString().trim().toLowerCase();
      if (cleanTgtStore.isNotEmpty) {
        if (sStore.isNotEmpty && sStore != cleanTgtStore) {
          return false;
        }
      }
      return true;
    }).toList();

    if (storeBatches.length > 1) {
      _showBatchSelectDialog(prod);
    } else if (storeBatches.length == 1) {
      _applyProduct(prod, selectedBatch: storeBatches.first);
    } else {
      _applyProduct(prod);
    }
  }

  void _applyProduct(Product prod, {Map<String, dynamic>? selectedBatch}) {
    Product effectiveProd = prod;
    if (selectedBatch != null) {
      effectiveProd = prod.copyWithBatch(selectedBatch);
    }
    setState(() {
      _product = effectiveProd;
      _suggestions = [];
      _statusMessage = '';
      _isError = false;
      _barcodeCtrl.text = effectiveProd.barcode.isNotEmpty ? effectiveProd.barcode : effectiveProd.productCode;
      if (effectiveProd.isBogo) {
        _selectedPreviewMode = 1; // Auto-switch to BOGO Tag
      } else if (_selectedPreviewMode == 1) {
        _selectedPreviewMode = 0; // If previously BOGO, fallback to Discount Tag
      }
    });
    _focusNode.unfocus();
  }

  double _safeDoubleVal(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val.trim()) ?? 0.0;
    return 0.0;
  }

  Future<void> _showBatchSelectDialog(Product prod, {String? scannedBarcode}) async {
    await _ensureStoreLoaded();
    final cleanTgtStore = _currentStoreId.trim().toLowerCase();
    final batches = prod.stocks.where((b) {
      final sStore = (b['store_id'] ?? b['storeId'] ?? '').toString().trim().toLowerCase();
      if (cleanTgtStore.isNotEmpty) {
        if (sStore.isNotEmpty && sStore != cleanTgtStore) {
          return false;
        }
      }
      return true;
    }).toList();

    if (batches.isEmpty) {
      _applyProduct(prod);
      return;
    }

    if (batches.length == 1) {
      _applyProduct(prod, selectedBatch: batches.first);
      return;
    }

    int defaultIdx = 0;
    if (scannedBarcode != null && scannedBarcode.isNotEmpty) {
      final matchIdx = batches.indexWhere((s) =>
          (s['stock_barcode']?.toString().trim().toLowerCase() ?? '') == scannedBarcode.toLowerCase());
      if (matchIdx != -1) {
        defaultIdx = matchIdx;
      }
    }

    if (!mounted) return;

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.layers_rounded, color: Colors.blue, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Stock Batch / MRP',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      prod.name,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.normal),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _currentStoreName.isNotEmpty
                              ? 'Multiple batches detected for $_currentStoreName. Select which tag to print:'
                              : 'Multiple batches detected for this store. Select which tag to print:',
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: batches.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final b = batches[i];
                      final mrp = (b['stock_mrp'] ?? b['mrp'] ?? 0.0);
                      final sale = (b['stock_sale_rate_a'] ?? b['stock_selling_rate'] ?? b['sale_rate_a'] ?? b['sale_rate'] ?? mrp);
                      final double mrpVal = mrp is num ? mrp.toDouble() : (double.tryParse(mrp.toString()) ?? 0.0);
                      final double saleVal = sale is num ? sale.toDouble() : (double.tryParse(sale.toString()) ?? 0.0);
                      final double qty = (b['stock_quantity'] ?? b['quantity'] ?? 0.0) is num
                          ? (b['stock_quantity'] ?? b['quantity'] ?? 0.0).toDouble()
                          : (double.tryParse((b['stock_quantity'] ?? b['quantity'] ?? '').toString()) ?? 0.0);
                      final barcodeStr = (b['stock_barcode'] ?? b['barcode'] ?? '').toString().trim();
                      final bool isMatch = i == defaultIdx;
                      final bool isBogo = mrpVal > 0 && saleVal > 0 && saleVal <= ((mrpVal / 2.0) + 0.01);
                      final double diff = mrpVal - saleVal;
                      final int discPercent = mrpVal > 0 && diff > 0 ? ((diff / mrpVal) * 100).round() : 0;

                      return InkWell(
                        onTap: () => Navigator.pop(ctx, b),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isMatch ? Colors.blue.shade50.withValues(alpha: 0.7) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isMatch ? Colors.blue.shade400 : Colors.grey.shade300,
                              width: isMatch ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: isMatch ? Colors.blue : Colors.grey.shade200,
                                child: Text(
                                  '#${i + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isMatch ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'MRP: ₹${mrpVal.toStringAsFixed(2)}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'SALE: ₹${saleVal.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14,
                                            color: Color(0xFF16A34A),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        if (isBogo)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade100,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '🎁 BOGO (50% OFF)',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.orange.shade900,
                                              ),
                                            ),
                                          )
                                        else if (discPercent > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade100,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '$discPercent% OFF',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red.shade900,
                                              ),
                                            ),
                                          ),
                                        if (barcodeStr.isNotEmpty)
                                          Text(
                                            'Barcode: $barcodeStr',
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                          ),
                                        Text(
                                          'Stock: ${qty.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: qty > 0 ? Colors.black87 : Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.black45),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, batches[defaultIdx]);
              },
              child: const Text('Use Default Batch'),
            ),
          ],
        );
      },
    );

    if (selected != null) {
      _applyProduct(prod, selectedBatch: selected);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Selected Batch: MRP ₹${_safeDoubleVal(selected['stock_mrp'] ?? selected['mrp']).toStringAsFixed(2)} | Sale ₹${_safeDoubleVal(selected['stock_sale_rate_a'] ?? selected['stock_selling_rate'] ?? selected['price']).toStringAsFixed(2)}',
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.blue.shade700,
          ),
        );
      }
    } else {
      _applyProduct(prod, selectedBatch: batches[defaultIdx]);
    }
  }

  Future<void> _searchBarcode(String barcode) async {
    final query = barcode.trim();
    if (query.isEmpty) return;

    await _ensureStoreLoaded();

    setState(() {
      _isLoading = true;
      _statusMessage = '';
      _isError = false;
      _suggestions = [];
    });

    try {
      final json = await ApiService().getProductByBarcode(query);
      if (json != null) {
        final prod = Product.fromJson(json, targetStoreId: _currentStoreId);
        if (mounted) {
          setState(() => _isLoading = false);
          _selectProduct(prod);
        }
      } else {
        final fallbackList = await ApiService().searchProducts(query, limit: 10);
        if (mounted) {
          if (fallbackList.isNotEmpty) {
            final prods = fallbackList.map((e) => Product.fromJson(e, targetStoreId: _currentStoreId)).toList();
            if (prods.length == 1) {
              setState(() => _isLoading = false);
              _selectProduct(prods.first);
            } else {
              setState(() {
                _suggestions = prods;
                _isLoading = false;
                _statusMessage = 'Select matching product from the list below:';
                _isError = false;
              });
            }
          } else {
            setState(() {
              _isLoading = false;
              _isError = true;
              _statusMessage = 'Product not found with barcode or name: "$query"';
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isError = true;
          _statusMessage = 'Search failed: ${e.toString().replaceAll("Exception: ", "")}';
        });
      }
    }
  }

  Future<void> _openCameraScanner() async {
    try {
      final status = await Permission.camera.request();

      if (!mounted) return;

      if (status.isPermanentlyDenied) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Camera Permission Required'),
            content: const Text(
              'Camera access is permanently disabled for ERP POS. Please enable camera permission in App Settings to scan barcodes.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
        return;
      }

      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission was denied. Please allow camera to scan.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.black,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) {
          return _CameraScannerSheet(
            onBarcodeDetected: (scannedCode) {
              Navigator.pop(ctx);
              _barcodeCtrl.text = scannedCode;
              _searchBarcode(scannedCode);
            },
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera initialization error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// printMode:
  /// 0 = Shelf Label (Name + Big Rate + MRP)
  /// 1 = Barcode + Label (Name + Rate + MRP + 1D Barcode)
  /// 2 = Discount Tag (Name + Giant Discount % / Savings + Offer Rate + MRP + Barcode)
  /// 3 = BOGO Tag (Buy 1 Get 1 Free - Strictly requires sale rate <= half MRP)
  Future<void> _handlePrint({required int printMode}) async {
    if (_product == null) return;

    if (printMode == 3 && !_product!.isBogo) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'BOGO Tag cannot be printed: Sale Rate (₹${_product!.saleRate.toStringAsFixed(2)}) must be half or less of MRP (₹${_product!.mrp.toStringAsFixed(2)}).',
          ),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }

    if (widget.selectedPrinter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No printer selected! Please select a printer in Settings.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _hideMrp = prefs.getBool('hide_mrp') ?? false;
    _hideCompanyName = prefs.getBool('hide_company_name') ?? false;

    setState(() => _isPrinting = true);
    try {
      bool success = false;
      if (printMode == 1) {
        success = await PrinterHelper.printBarcodeAndLabel(
          widget.selectedPrinter,
          _product!,
          copies: _copies,
          hideCompanyName: _hideCompanyName,
          hideMrp: _hideMrp,
        );
      } else if (printMode == 2) {
        success = await PrinterHelper.printDiscountLabel(
          widget.selectedPrinter,
          _product!,
          copies: _copies,
          hideCompanyName: _hideCompanyName,
          hideMrp: _hideMrp,
        );
      } else if (printMode == 3) {
        success = await PrinterHelper.printBogoLabel(
          widget.selectedPrinter,
          _product!,
          copies: _copies,
          hideCompanyName: _hideCompanyName,
          hideMrp: _hideMrp,
        );
      } else {
        success = await PrinterHelper.printShelfLabel(
          widget.selectedPrinter,
          _product!,
          copies: _copies,
          hideCompanyName: _hideCompanyName,
          hideMrp: _hideMrp,
        );
      }

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$_copies ${_copies > 1 ? 'labels' : 'label'} printed successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Print failed or printer busy. Check printer connection.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text(
          'Print Barcode & Shelf Label',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Active Store Badge
                if (_currentStoreName.isNotEmpty || _currentStoreId.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blueGrey.shade100),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.storefront_rounded, size: 18, color: Colors.blue),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ACTIVE STORE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black54,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              Text(
                                _currentStoreName.isNotEmpty ? _currentStoreName : _currentStoreId,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Text(
                            'Stock Filtered',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 1. Search Box with Camera Icon & Live Autocomplete
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Scan Barcode or Search Product',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _barcodeCtrl,
                              focusNode: _focusNode,
                              decoration: InputDecoration(
                                hintText: 'Type barcode, SKU, or product name...',
                                prefixIcon: const Icon(Icons.qr_code_2),
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_barcodeCtrl.text.isNotEmpty)
                                      IconButton(
                                        icon: const Icon(Icons.clear, size: 20),
                                        onPressed: () {
                                          _barcodeCtrl.clear();
                                          setState(() {
                                            _product = null;
                                            _suggestions = [];
                                            _statusMessage = '';
                                          });
                                        },
                                      ),
                                    Container(
                                      margin: const EdgeInsets.only(right: 6),
                                      decoration: BoxDecoration(
                                        color: primaryColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: IconButton(
                                        icon: Icon(Icons.camera_alt_rounded, color: primaryColor),
                                        tooltip: 'Scan using phone camera',
                                        onPressed: _openCameraScanner,
                                      ),
                                    ),
                                  ],
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              ),
                              onChanged: _onSearchChanged,
                              onSubmitted: _searchBarcode,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _isLoading ? null : () => _searchBarcode(_barcodeCtrl.text),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.search),
                          ),
                        ],
                      ),

                      // Live search suggestions dropdown
                      if (_isSearchingSuggestions) ...[
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(minHeight: 2),
                      ],

                      if (_suggestions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          constraints: const BoxConstraints(maxHeight: 280),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _suggestions.length,
                            separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
                            itemBuilder: (ctx, i) {
                              final p = _suggestions[i];
                              final double diff = p.mrp - p.saleRate;
                              final int discPercent = p.mrp > 0 && diff > 0 ? ((diff / p.mrp) * 100).round() : 0;

                              return ListTile(
                                dense: true,
                                title: Text(
                                  p.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Row(
                                  children: [
                                    if (p.productCode.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        margin: const EdgeInsets.only(right: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.grey.shade300),
                                        ),
                                        child: Text(
                                          p.productCode,
                                          style: const TextStyle(fontSize: 10, color: Colors.black87),
                                        ),
                                      ),
                                    if (p.barcode.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        margin: const EdgeInsets.only(right: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.green.shade200),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.qr_code, size: 10, color: Colors.green),
                                            const SizedBox(width: 3),
                                            Text(
                                              p.barcode,
                                              style: TextStyle(fontSize: 10, color: Colors.green.shade800, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (discPercent > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade50,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.orange.shade300),
                                        ),
                                        child: Text(
                                          '$discPercent% OFF',
                                          style: TextStyle(fontSize: 10, color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '₹${p.saleRate.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (p.mrp > p.saleRate)
                                      Text(
                                        'MRP ₹${p.mrp.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade500,
                                          decoration: TextDecoration.lineThrough,
                                        ),
                                      ),
                                  ],
                                ),
                                onTap: () => _selectProduct(p),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Error or status message
                if (_statusMessage.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _isError ? Colors.red.shade50 : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isError ? Colors.red.shade200 : Colors.blue.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isError ? Icons.error_outline : Icons.info_outline,
                          color: _isError ? Colors.red.shade700 : Colors.blue.shade700,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _statusMessage,
                            style: TextStyle(
                              color: _isError ? Colors.red.shade900 : Colors.blue.shade900,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 2. Product Found & Live Shelf Tag Preview
                if (_product != null) ...[
                  // Store Stock Indicator (strictly for this store)
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _product!.stockQuantity > 0 ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _product!.stockQuantity > 0 ? Colors.green.shade200 : Colors.red.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _product!.stockQuantity > 0 ? Icons.inventory_2_outlined : Icons.remove_shopping_cart_outlined,
                          size: 18,
                          color: _product!.stockQuantity > 0 ? Colors.green.shade800 : Colors.red.shade800,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _product!.stockQuantity > 0
                                ? 'Store Stock: ${_product!.stockQuantity.toStringAsFixed(0)} units in ${_currentStoreName.isNotEmpty ? _currentStoreName : "current store"}'
                                : 'Store Stock: 0 units in ${_currentStoreName.isNotEmpty ? _currentStoreName : "current store"} (Out of stock)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _product!.stockQuantity > 0 ? Colors.green.shade900 : Colors.red.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Multi-batch / Multi-MRP detected indicator
                  if (_product!.hasMultipleBatches) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.layers_rounded, color: Colors.blue, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Multiple Batches / MRPs Available',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue),
                                ),
                                Text(
                                  'Active: MRP ₹${_product!.mrp.toStringAsFixed(2)} | Sale ₹${_product!.saleRate.toStringAsFixed(2)} (${_product!.stocks.length} batches)',
                                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _showBatchSelectDialog(_product!),
                            icon: const Icon(Icons.swap_horiz, size: 16),
                            label: const Text('Change', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // BOGO eligibility banner
                  if (_product!.isBogo) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.stars_rounded, color: Color(0xFFEA580C), size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 12, color: Colors.black87),
                                children: [
                                  const TextSpan(
                                    text: 'BOGO Offer Eligible! ',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFC2410C)),
                                  ),
                                  TextSpan(
                                    text: 'Sale Rate (₹${_product!.saleRate.toStringAsFixed(2)}) is half of MRP (₹${_product!.mrp.toStringAsFixed(2)}). You can print BOGO Tags!',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),
                  _buildShelfLabelPreview(_product!),
                  const SizedBox(height: 18),

                  // 3. Copies selector
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Number of Copies:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: _copies > 1 ? () => setState(() => _copies--) : null,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$_copies',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => setState(() => _copies++),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // 4. Action Buttons (4 Options: Discount Tag, BOGO Tag, Shelf Label, Barcode+Label)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Row 1: Promotional Tag Buttons (Discount & BOGO)
                      Row(
                        children: [
                          // Button 1: Print Discount Tag
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isPrinting ? null : () => _handlePrint(printMode: 2),
                              icon: const Icon(Icons.local_offer_rounded, size: 18),
                              label: const Text(
                                'Print Discount Tag',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFDC2626), // Eye-catching Red
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Button 2: Print BOGO Tag (Buy 1 Get 1 Free - Strictly requires sale rate <= half MRP)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isPrinting
                                  ? null
                                  : (!_product!.isBogo
                                      ? () {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'BOGO Tag is disabled: Sale rate (₹${_product!.saleRate.toStringAsFixed(2)}) must be half or less of MRP (₹${_product!.mrp.toStringAsFixed(2)}).',
                                              ),
                                              backgroundColor: Colors.orange.shade800,
                                            ),
                                          );
                                        }
                                      : () => _handlePrint(printMode: 3)),
                              icon: Icon(
                                _product!.isBogo ? Icons.card_giftcard_rounded : Icons.lock_outline,
                                size: 18,
                              ),
                              label: Text(
                                _product!.isBogo ? 'Print BOGO Tag 🔥' : 'BOGO (Not Half MRP)',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _product!.isBogo ? const Color(0xFFEA580C) : Colors.grey.shade400,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                elevation: _product!.isBogo ? 2 : 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Row 2: Standard Rack Tags (Shelf Label & Barcode Tag)
                      Row(
                        children: [
                          // Button 3: Print Shelf Label Only
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isPrinting ? null : () => _handlePrint(printMode: 0),
                              icon: const Icon(Icons.label_outline, size: 18),
                              label: const Text(
                                'Print Shelf Label',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Button 4: Print Barcode + Label
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isPrinting ? null : () => _handlePrint(printMode: 1),
                              icon: const Icon(Icons.qr_code, size: 18),
                              label: const Text(
                                'Print Barcode + Label',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F172A),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  if (_isPrinting) ...[
                    const SizedBox(height: 16),
                    const Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Sending commands to printer...',
                            style: TextStyle(color: Colors.black54, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Live visual preview card with compact layout matching exact shelf label height
  Widget _buildShelfLabelPreview(Product p) {
    final double savings = p.mrp - p.saleRate;
    final int discountPercent = p.mrp > 0 && savings > 0 ? ((savings / p.mrp) * 100).round() : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Preview Mode Switcher (Discount Tag / BOGO Tag / Shelf Label / Barcode Tag)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              _buildPreviewTabItem(0, 'Discount Tag', Icons.local_offer),
              _buildPreviewTabItem(
                1,
                p.isBogo ? 'BOGO Tag 🔥' : 'BOGO Tag 🔒',
                Icons.card_giftcard_rounded,
                isEnabled: p.isBogo,
              ),
              _buildPreviewTabItem(2, 'Shelf Label', Icons.label_outline),
              _buildPreviewTabItem(3, 'Barcode Tag', Icons.qr_code),
            ],
          ),
        ),

        // Compact Tag Card (Exact same physical shelf rack height)
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _selectedPreviewMode == 0
                  ? Colors.red.shade300
                  : (_selectedPreviewMode == 1
                      ? Colors.orange.shade300
                      : (_selectedPreviewMode == 2 ? Colors.purple.shade300 : Colors.blue.shade200)),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _selectedPreviewMode == 0
                      ? const Color(0xFFDC2626) // Red
                      : (_selectedPreviewMode == 1
                          ? const Color(0xFFEA580C) // Orange / BOGO
                          : (_selectedPreviewMode == 2 ? Colors.deepPurple : const Color(0xFF0F172A))),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _selectedPreviewMode == 0
                          ? 'DISCOUNT RACK TAG'
                          : (_selectedPreviewMode == 1
                              ? 'BOGO RACK TAG (BUY 1 GET 1 FREE)'
                              : (_selectedPreviewMode == 2 ? 'SHELF RACK LABEL' : 'BARCODE + RACK TAG')),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '58mm Compact',
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

              // Content Area - Exactly compact, consistent height
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: _selectedPreviewMode == 1 && p.isBogo
                    ? _buildBogoTagContent(p)
                    : (_selectedPreviewMode == 0
                        ? _buildDiscountTagContent(p, discountPercent, savings)
                        : (_selectedPreviewMode == 2
                            ? _buildShelfLabelContent(p)
                            : _buildBarcodeTagContent(p))),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewTabItem(int mode, String label, IconData icon, {bool isEnabled = true}) {
    final bool isSelected = _selectedPreviewMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (!isEnabled) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'BOGO Tag is only available when Sale Rate (₹${_product?.saleRate.toStringAsFixed(2) ?? "0"}) is half or less of MRP (₹${_product?.mrp.toStringAsFixed(2) ?? "0"}).',
                ),
                backgroundColor: const Color(0xFFEA580C),
                duration: const Duration(seconds: 3),
              ),
            );
            return;
          }
          setState(() => _selectedPreviewMode = mode);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white
                : (!isEnabled ? Colors.grey.shade100 : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Opacity(
            opacity: isEnabled ? 1.0 : 0.45,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isEnabled ? icon : Icons.lock_outline,
                  size: 14,
                  color: isSelected ? Colors.black87 : Colors.black54,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? Colors.black87 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Store brand header displayed on top of each tag in small capital
  Widget _buildStoreHeader() {
    if (_hideCompanyName) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2.5),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'KCSUPERMARKET',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.8,
          color: Color(0xFF334155),
        ),
      ),
    );
  }

  /// Exact 3-row compact format requested by user:
  /// 0. KCSUPERMARKET (small capital header)
  /// 1. Product Name
  /// 2. Discount (Giant % value and | OFF | on a single line adapting to full tag)
  /// 3. Sale Rate , MRP
  Widget _buildDiscountTagContent(Product p, int discountPercent, double savings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Store Header (small capital)
        _buildStoreHeader(),

        // 1. Product Name (Bold, increased size)
        Text(
          p.name.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: Colors.black87,
            height: 1.15,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 5),
        Divider(color: Colors.grey.shade300, thickness: 1, height: 10),
        const SizedBox(height: 3),

        // 2. Discount - Single row: Large percentage + 'off' (Strict single row, keeps compact tag height)
        if (discountPercent > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: RichText(
                maxLines: 1,
                softWrap: false,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$discountPercent% ',
                      style: const TextStyle(
                        fontSize: 50,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFDC2626),
                        letterSpacing: -1.0,
                        height: 1.0,
                      ),
                    ),
                    const TextSpan(
                      text: 'off',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFDC2626),
                        letterSpacing: 0.5,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (savings > 0)
          Text(
            'SAVE ₹${savings.toStringAsFixed(0)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Color(0xFFDC2626),
              letterSpacing: 0.5,
            ),
          )
        else
          const Text(
            'SPECIAL OFFER',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Color(0xFFDC2626),
              letterSpacing: 0.5,
            ),
          ),
        const SizedBox(height: 3),
        Divider(color: Colors.grey.shade300, thickness: 1, height: 10),
        const SizedBox(height: 5),

        // 3. Sale Rate , MRP (on one single line, larger rates text)
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold, color: Colors.black87),
            children: [
              const TextSpan(text: 'SALE: '),
              TextSpan(
                text: '₹${p.saleRate.toStringAsFixed(2)}',
                style: const TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.w900, fontSize: 18),
              ),
              if (!_hideMrp) ...[
                const TextSpan(text: ' , MRP: '),
                TextSpan(
                  text: '₹${p.mrp.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w800),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Exact 3-row compact BOGO tag format:
  /// 0. KCSUPERMARKET (small capital header)
  /// 1. Product Name
  /// 2. BUY 1 GET 1 FREE (Large eye-catching offer)
  /// 3. ONLY MRP (No sale rate!)
  Widget _buildBogoTagContent(Product p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Store Header (small capital)
        _buildStoreHeader(),

        // 1. Product Name (Bold, increased size)
        Text(
          p.name.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: Colors.black87,
            height: 1.15,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 5),
        Divider(color: Colors.grey.shade300, thickness: 1, height: 10),
        const SizedBox(height: 3),

        // 2. BOGO Offer Text (Large, prominent)
        const Text(
          'BUY 1 GET 1 FREE',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            color: Color(0xFFEA580C),
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 3),
        Divider(color: Colors.grey.shade300, thickness: 1, height: 10),
        const SizedBox(height: 5),

        // 3. ONLY MRP for BOGO (Strictly DO NOT show sale rate!)
        if (!_hideMrp)
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
              children: [
                const TextSpan(text: 'MRP: '),
                TextSpan(
                  text: '₹${p.mrp.toStringAsFixed(2)}',
                  style: const TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.w900, fontSize: 22),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildShelfLabelContent(Product p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Store Header (small capital)
        _buildStoreHeader(),

        // 1. Product Name (increased size)
        Text(
          p.name.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: Colors.black87,
            height: 1.15,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 5),
        Divider(color: Colors.grey.shade300, thickness: 1, height: 10),
        const SizedBox(height: 3),

        // 2. Big Sale Rate (Larger text)
        Text(
          '₹${p.saleRate.toStringAsFixed(2)}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w900,
            color: Color(0xFF16A34A),
          ),
        ),
        const SizedBox(height: 2),

        // 3. MRP (Larger text)
        if (!_hideMrp) ...[
          Text(
            'MRP: ₹${p.mrp.toStringAsFixed(2)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF475569),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Divider(color: Colors.grey.shade300, thickness: 1, height: 10),
      ],
    );
  }

  Widget _buildBarcodeTagContent(Product p) {
    final rawBarcode = p.barcode.isNotEmpty ? p.barcode : (p.id.length >= 8 ? p.id.substring(0, 8) : '100001');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Store Header (small capital)
        _buildStoreHeader(),

        Text(
          p.name.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w900,
            color: Colors.black87,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black87),
            children: [
              const TextSpan(text: 'RATE: '),
              TextSpan(
                text: '₹${p.saleRate.toStringAsFixed(2)}',
                style: const TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.w900),
              ),
              if (!_hideMrp) ...[
                const TextSpan(text: '  (MRP: '),
                TextSpan(
                  text: '₹${p.mrp.toStringAsFixed(2)}',
                  style: const TextStyle(color: Color(0xFF475569)),
                ),
                const TextSpan(text: ')'),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            32,
            (i) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              width: (i % 3 == 0) ? 2.5 : ((i % 2 == 0) ? 1.5 : 2),
              height: 26,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          rawBarcode,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            fontFamily: 'Courier',
          ),
        ),
      ],
    );
  }
}

/// Phone Camera Barcode Scanner BottomSheet using mobile_scanner
class _CameraScannerSheet extends StatefulWidget {
  final Function(String barcode) onBarcodeDetected;

  const _CameraScannerSheet({required this.onBarcodeDetected});

  @override
  State<_CameraScannerSheet> createState() => _CameraScannerSheetState();
}

class _CameraScannerSheetState extends State<_CameraScannerSheet> {
  MobileScannerController? _controller;
  bool _isReady = false;
  bool _isScanned = false;
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    // Initialize controller only after the widget is fully mounted in the view hierarchy
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller = MobileScannerController(
          autoStart: true,
          detectionSpeed: DetectionSpeed.normal,
          facing: CameraFacing.back,
        );
        setState(() => _isReady = true);
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: _isReady && _controller != null
                ? MobileScanner(
                    controller: _controller!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, child) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.videocam_off_rounded, color: Colors.white70, size: 52),
                              const SizedBox(height: 16),
                              Text(
                                'Camera Notice: ${error.errorCode.name}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                error.errorDetails?.message ?? 'Please ensure camera permissions are allowed in phone settings.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: () => openAppSettings(),
                                icon: const Icon(Icons.settings),
                                label: const Text('Open App Settings'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    onDetect: (capture) {
                      if (_isScanned) return;
                      final barcodes = capture.barcodes;
                      for (final barcode in barcodes) {
                        final raw = barcode.rawValue;
                        if (raw != null && raw.trim().isNotEmpty) {
                          _isScanned = true;
                          widget.onBarcodeDetected(raw.trim());
                          break;
                        }
                      }
                    },
                  )
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
          ),

          // Top Header with Close & Torch
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton.filled(
                  icon: const Icon(Icons.close, color: Colors.white),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                  onPressed: () => Navigator.pop(context),
                ),
                const Text(
                  'Scan Barcode',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton.filled(
                  icon: Icon(
                    _torchOn ? Icons.flash_on : Icons.flash_off,
                    color: Colors.white,
                  ),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                  onPressed: () async {
                    if (_controller != null) {
                      try {
                        await _controller!.toggleTorch();
                        setState(() => _torchOn = !_torchOn);
                      } catch (_) {}
                    }
                  },
                ),
              ],
            ),
          ),

          // Center Viewfinder Target
          Center(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 2.5),
                borderRadius: BorderRadius.circular(16),
                color: Colors.black.withValues(alpha: 0.1),
              ),
              child: Center(
                child: Container(
                  height: 2,
                  width: 240,
                  color: Colors.redAccent.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),

          // Bottom Instruction
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
                child: const Text(
                  'Align barcode inside the frame',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
