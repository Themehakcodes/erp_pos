import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
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
  int _selectedPreviewMode = 0; // 0 = Discount Tag, 1 = Shelf Label, 2 = Barcode Tag

  Timer? _debounceTimer;
  List<Product> _suggestions = [];

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
      setState(() => _isSearchingSuggestions = true);
      try {
        final list = await ApiService().searchProducts(query, limit: 15);
        if (mounted) {
          setState(() {
            _suggestions = list.map((e) => Product.fromJson(e)).toList();
            _isSearchingSuggestions = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearchingSuggestions = false);
      }
    });
  }

  void _selectProduct(Product prod) {
    setState(() {
      _product = prod;
      _suggestions = [];
      _statusMessage = '';
      _isError = false;
      _barcodeCtrl.text = prod.barcode.isNotEmpty ? prod.barcode : prod.productCode;
    });
    _focusNode.unfocus();
  }

  Future<void> _searchBarcode(String barcode) async {
    final query = barcode.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _statusMessage = '';
      _isError = false;
      _suggestions = [];
    });

    try {
      final json = await ApiService().getProductByBarcode(query);
      if (json != null) {
        final prod = Product.fromJson(json);
        if (mounted) {
          setState(() {
            _product = prod;
            _isLoading = false;
          });
        }
      } else {
        final fallbackList = await ApiService().searchProducts(query, limit: 10);
        if (mounted) {
          if (fallbackList.isNotEmpty) {
            final prods = fallbackList.map((e) => Product.fromJson(e)).toList();
            if (prods.length == 1) {
              setState(() {
                _product = prods.first;
                _isLoading = false;
              });
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
  Future<void> _handlePrint({required int printMode}) async {
    if (_product == null) return;

    if (widget.selectedPrinter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No printer selected! Please select a printer in Settings.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isPrinting = true);
    try {
      bool success = false;
      if (printMode == 1) {
        success = await PrinterHelper.printBarcodeAndLabel(
          widget.selectedPrinter,
          _product!,
          copies: _copies,
        );
      } else if (printMode == 2) {
        success = await PrinterHelper.printDiscountLabel(
          widget.selectedPrinter,
          _product!,
          copies: _copies,
        );
      } else {
        success = await PrinterHelper.printShelfLabel(
          widget.selectedPrinter,
          _product!,
          copies: _copies,
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
                  const SizedBox(height: 16),
                  _buildShelfLabelPreview(_product!),
                  const SizedBox(height: 20),

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

                  const SizedBox(height: 20),

                  // 4. Action Buttons (3 Options: Shelf Label, Barcode+Label, Discount Tag)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Option 3 (Highlighted): Print Discount Tag with Large % OFF
                      ElevatedButton.icon(
                        onPressed: _isPrinting ? null : () => _handlePrint(printMode: 2),
                        icon: const Icon(Icons.local_offer_rounded, size: 20),
                        label: const Text(
                          'Print Discount Tag (Compact Rack Tag)',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626), // Eye-catching Red for Discounts
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          // Option 1: Print Shelf Label Only
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
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Option 2: Print Barcode + Label
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
                                padding: const EdgeInsets.symmetric(vertical: 15),
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
        // Preview Mode Switcher (Discount Tag / Shelf Label / Barcode Tag)
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
              _buildPreviewTabItem(1, 'Shelf Label', Icons.label_outline),
              _buildPreviewTabItem(2, 'Barcode Tag', Icons.qr_code),
            ],
          ),
        ),

        // Compact Tag Card (Exact same physical shelf rack height)
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _selectedPreviewMode == 0 ? Colors.red.shade300 : Colors.blue.shade200,
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
                      ? const Color(0xFFDC2626)
                      : (_selectedPreviewMode == 1 ? Colors.deepPurple : const Color(0xFF0F172A)),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _selectedPreviewMode == 0
                          ? 'DISCOUNT RACK TAG'
                          : (_selectedPreviewMode == 1 ? 'SHELF RACK LABEL' : 'BARCODE + RACK TAG'),
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
                child: _selectedPreviewMode == 0
                    ? _buildDiscountTagContent(p, discountPercent, savings)
                    : (_selectedPreviewMode == 1
                        ? _buildShelfLabelContent(p)
                        : _buildBarcodeTagContent(p)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewTabItem(int mode, String label, IconData icon) {
    final bool isSelected = _selectedPreviewMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedPreviewMode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? Colors.black87 : Colors.black54,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.black87 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Exact 3-row compact format requested by user:
  /// 1. Product Name
  /// 2. Discount
  /// 3. Sale Rate , MRP
  Widget _buildDiscountTagContent(Product p, int discountPercent, double savings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 1. Product Name (Bold)
        Text(
          p.name.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
            height: 1.2,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Divider(color: Colors.grey.shade300, thickness: 1, height: 12),
        const SizedBox(height: 4),

        // 2. Discount (Bold, prominent)
        Text(
          discountPercent > 0
              ? '$discountPercent% OFF'
              : (savings > 0 ? 'SAVE ₹${savings.toStringAsFixed(0)}' : 'SPECIAL OFFER'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Color(0xFFDC2626),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Divider(color: Colors.grey.shade300, thickness: 1, height: 12),
        const SizedBox(height: 6),

        // 3. Sale Rate , MRP (on one single line)
        Text(
          'SALE: ₹${p.saleRate.toStringAsFixed(2)} , MRP: ₹${p.mrp.toStringAsFixed(2)}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildShelfLabelContent(Product p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 1. Product Name
        Text(
          p.name.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
            height: 1.2,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Divider(color: Colors.grey.shade300, thickness: 1, height: 12),
        const SizedBox(height: 4),

        // 2. Big Sale Rate
        Text(
          '₹${p.saleRate.toStringAsFixed(2)}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Color(0xFF16A34A),
          ),
        ),
        const SizedBox(height: 2),

        // 3. MRP
        Text(
          'MRP: ₹${p.mrp.toStringAsFixed(2)}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black54,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Divider(color: Colors.grey.shade300, thickness: 1, height: 12),
      ],
    );
  }

  Widget _buildBarcodeTagContent(Product p) {
    final rawBarcode = p.barcode.isNotEmpty ? p.barcode : (p.id.length >= 8 ? p.id.substring(0, 8) : '100001');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          p.name.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          'RATE: ₹${p.saleRate.toStringAsFixed(2)}  (MRP: ₹${p.mrp.toStringAsFixed(2)})',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
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
              height: 24,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          rawBarcode,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
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
