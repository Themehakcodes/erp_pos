import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';
import '../models/models.dart';
import '../printer_helper.dart';

String formatBillDate(String rawDate) {
  if (rawDate.isEmpty) return '';
  try {
    final dt = DateTime.tryParse(rawDate);
    if (dt != null) {
      final local = dt.toLocal();
      final y = local.year.toString();
      final m = local.month.toString().padLeft(2, '0');
      final d = local.day.toString().padLeft(2, '0');
      var hour = local.hour;
      final min = local.minute.toString().padLeft(2, '0');
      final ampm = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      return '$d-$m-$y $hour:$min $ampm';
    }
  } catch (_) {}
  return rawDate.length > 16 ? rawDate.substring(0, 16) : rawDate;
}

int compareBillsDescending(BillReceiptData a, BillReceiptData b) {
  final dtA = DateTime.tryParse(a.dateStr);
  final dtB = DateTime.tryParse(b.dateStr);
  if (dtA != null && dtB != null) {
    final cmp = dtB.compareTo(dtA);
    if (cmp != 0) return cmp;
  } else if (a.dateStr.isNotEmpty && b.dateStr.isNotEmpty) {
    final cmp = b.dateStr.compareTo(a.dateStr);
    if (cmp != 0) return cmp;
  }
  return b.invoiceNo.compareTo(a.invoiceNo);
}

class BillHistoryScreen extends StatefulWidget {
  final SelectedPrinter? selectedPrinter;

  const BillHistoryScreen({super.key, this.selectedPrinter});

  @override
  State<BillHistoryScreen> createState() => _BillHistoryScreenState();
}

class _BillHistoryScreenState extends State<BillHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  static const int _pageSize = 30;

  bool _isLoading = false;
  String _currentShiftId = '';
  String _currentStoreId = '';

  List<BillReceiptData> _shiftBills = [];
  int _shiftPage = 1;
  bool _shiftHasMore = true;
  bool _isLoadingMoreShift = false;
  final ScrollController _shiftScrollCtrl = ScrollController();

  List<BillReceiptData> _todayBills = [];
  int _todayPage = 1;
  bool _todayHasMore = true;
  bool _isLoadingMoreToday = false;
  final ScrollController _todayScrollCtrl = ScrollController();

  List<BillReceiptData> _offlineBills = [];
  final ScrollController _offlineScrollCtrl = ScrollController();

  String _searchQuery = '';
  Timer? _debounceTimer;

  // Track which bill is currently reprinting to show spinner on its button
  String? _printingInvoiceNo;
  bool _isSyncingOffline = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _shiftScrollCtrl.addListener(_onShiftScroll);
    _todayScrollCtrl.addListener(_onTodayScroll);
    _loadInitialData();
  }

  @override
  void dispose() {
    _shiftScrollCtrl.removeListener(_onShiftScroll);
    _todayScrollCtrl.removeListener(_onTodayScroll);
    _shiftScrollCtrl.dispose();
    _todayScrollCtrl.dispose();
    _offlineScrollCtrl.dispose();
    _tabController.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onShiftScroll() {
    if (_shiftScrollCtrl.position.pixels >=
        _shiftScrollCtrl.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMoreShift && _shiftHasMore && _searchQuery.isEmpty) {
        _loadMoreShiftBills();
      }
    }
  }

  void _onTodayScroll() {
    if (_todayScrollCtrl.position.pixels >=
        _todayScrollCtrl.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMoreToday && _todayHasMore && _searchQuery.isEmpty) {
        _loadMoreTodayBills();
      }
    }
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    _currentShiftId = prefs.getString('shift_id') ?? '';
    _currentStoreId = prefs.getString('store_id') ?? '';

    // If shift_id was not in prefs, check active terminal shift
    if (_currentShiftId.isEmpty) {
      try {
        final deviceId = prefs.getString('device_identifier');
        if (deviceId != null) {
          final terminalData = await ApiService().checkTerminal(deviceId);
          final terminalId = terminalData['id'];
          if (terminalId != null) {
            final activeShift = await ApiService().getActiveShift(terminalId);
            if (activeShift != null && activeShift['id'] != null) {
              _currentShiftId = activeShift['id'].toString();
              await prefs.setString('shift_id', _currentShiftId);
            }
          }
        }
      } catch (_) {}
    }

    await _fetchAllTabsData();
  }

  Future<void> _fetchAllTabsData() async {
    setState(() {
      _isLoading = true;
      _shiftPage = 1;
      _shiftHasMore = true;
      _todayPage = 1;
      _todayHasMore = true;
    });
    try {
      // 1. Load local terminal cache & offline pending sales first (instant!)
      final localCache = await ApiService.getLocalShiftBills();
      final offlineSales = await ApiService.getOfflinePendingBills();
      offlineSales.sort(compareBillsDescending);

      // 2. Load today's date string in YYYY-MM-DD
      final now = DateTime.now();
      final todayStr =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      // 3. Fetch first page of shift bills and today's bills from ERP server
      List<Map<String, dynamic>> serverShiftSales = [];
      List<Map<String, dynamic>> serverTodaySales = [];

      try {
        if (_currentShiftId.isNotEmpty) {
          serverShiftSales = await ApiService().getSales(
            page: 1,
            limit: _pageSize,
            shiftId: _currentShiftId,
            storeId: _currentStoreId,
          );
          if (serverShiftSales.length < _pageSize) {
            _shiftHasMore = false;
          }
        } else {
          _shiftHasMore = false;
        }
      } catch (e) {
        debugPrint('Could not fetch shift sales from server: $e');
      }

      try {
        serverTodaySales = await ApiService().getSales(
          page: 1,
          limit: _pageSize,
          fromDate: todayStr,
          toDate: todayStr,
          storeId: _currentStoreId,
        );
        if (serverTodaySales.length < _pageSize) {
          _todayHasMore = false;
        }
      } catch (e) {
        debugPrint('Could not fetch today sales from server: $e');
      }

      // Merge and deduplicate shift bills (Local cache + Server + Offline)
      final Map<String, BillReceiptData> shiftMap = {};

      // Add local cache first (they contain full items without needing extra fetch!)
      for (final bill in localCache) {
        if (_currentShiftId.isEmpty ||
            bill.shiftId.isEmpty ||
            bill.shiftId == _currentShiftId) {
          shiftMap[bill.invoiceNo] = bill;
        }
      }

      // Add server shift sales
      for (final s in serverShiftSales) {
        final invNo =
            (s['invoice_number'] ?? s['invoice_no'] ?? '').toString();
        if (invNo.isEmpty) continue;
        if (!shiftMap.containsKey(invNo)) {
          shiftMap[invNo] = _convertSaleSummaryToBill(s);
        }
      }

      // Add offline sales that match shift
      for (final off in offlineSales) {
        if (!shiftMap.containsKey(off.invoiceNo)) {
          shiftMap[off.invoiceNo] = off;
        }
      }

      // Convert map to sorted list (newest first / descending)
      final List<BillReceiptData> mergedShift = shiftMap.values.toList();
      mergedShift.sort(compareBillsDescending);

      // Build today bills list
      final Map<String, BillReceiptData> todayMap = {};
      for (final b in mergedShift) {
        todayMap[b.invoiceNo] = b;
      }
      for (final s in serverTodaySales) {
        final invNo =
            (s['invoice_number'] ?? s['invoice_no'] ?? '').toString();
        if (invNo.isNotEmpty && !todayMap.containsKey(invNo)) {
          todayMap[invNo] = _convertSaleSummaryToBill(s);
        }
      }
      for (final off in offlineSales) {
        if (!todayMap.containsKey(off.invoiceNo)) {
          todayMap[off.invoiceNo] = off;
        }
      }
      final List<BillReceiptData> mergedToday = todayMap.values.toList();
      mergedToday.sort(compareBillsDescending);

      if (mounted) {
        setState(() {
          _shiftBills = mergedShift;
          _todayBills = mergedToday;
          _offlineBills = offlineSales;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading bills: $e')),
        );
      }
    }
  }

  Future<void> _loadMoreShiftBills() async {
    if (_isLoadingMoreShift || !_shiftHasMore || _currentShiftId.isEmpty) return;
    setState(() => _isLoadingMoreShift = true);
    try {
      final nextPage = _shiftPage + 1;
      final newSales = await ApiService().getSales(
        page: nextPage,
        limit: _pageSize,
        shiftId: _currentShiftId,
        storeId: _currentStoreId,
      );
      if (newSales.isEmpty || newSales.length < _pageSize) {
        _shiftHasMore = false;
      }
      if (newSales.isNotEmpty) {
        final Map<String, BillReceiptData> map = {
          for (var b in _shiftBills) b.invoiceNo: b,
        };
        for (var s in newSales) {
          final inv = (s['invoice_number'] ?? s['invoice_no'] ?? '').toString();
          if (inv.isNotEmpty && !map.containsKey(inv)) {
            map[inv] = _convertSaleSummaryToBill(s);
          }
        }
        final list = map.values.toList();
        list.sort(compareBillsDescending);
        if (mounted) {
          setState(() {
            _shiftBills = list;
            _shiftPage = nextPage;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading more shift bills: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMoreShift = false);
    }
  }

  Future<void> _loadMoreTodayBills() async {
    if (_isLoadingMoreToday || !_todayHasMore) return;
    setState(() => _isLoadingMoreToday = true);
    try {
      final now = DateTime.now();
      final todayStr =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final nextPage = _todayPage + 1;
      final newSales = await ApiService().getSales(
        page: nextPage,
        limit: _pageSize,
        fromDate: todayStr,
        toDate: todayStr,
        storeId: _currentStoreId,
      );
      if (newSales.isEmpty || newSales.length < _pageSize) {
        _todayHasMore = false;
      }
      if (newSales.isNotEmpty) {
        final Map<String, BillReceiptData> map = {
          for (var b in _todayBills) b.invoiceNo: b,
        };
        for (var s in newSales) {
          final inv = (s['invoice_number'] ?? s['invoice_no'] ?? '').toString();
          if (inv.isNotEmpty && !map.containsKey(inv)) {
            map[inv] = _convertSaleSummaryToBill(s);
          }
        }
        final list = map.values.toList();
        list.sort(compareBillsDescending);
        if (mounted) {
          setState(() {
            _todayBills = list;
            _todayPage = nextPage;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading more today bills: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMoreToday = false);
    }
  }

  BillReceiptData _convertSaleSummaryToBill(Map<String, dynamic> s) {
    final netAmount = (s['net_amount'] is num)
        ? (s['net_amount'] as num).toDouble()
        : (double.tryParse(s['net_amount']?.toString() ?? '0') ?? 0.0);
    final invNo = (s['invoice_number'] ?? s['invoice_no'] ?? '').toString();
    // Prefer created_at because it holds the exact timestamp with hours:minutes:seconds
    final dStr = (s['created_at'] ?? s['invoice_date'] ?? '').toString();
    final method = (s['payment_methods_used'] ?? 'Cash').toString();
    final id = (s['id'] ?? '').toString();
    final isCancelled = s['is_cancelled'] == true;

    return BillReceiptData(
      id: id,
      invoiceNo: invNo,
      dateStr: dStr,
      items: const [], // items will be loaded on demand if full details needed
      totalAmount: netAmount,
      method: method,
      isCancelled: isCancelled,
      shiftId: (s['shift_id'] ?? '').toString(),
    );
  }

  List<BillReceiptData> _getFilteredList(List<BillReceiptData> original) {
    if (_searchQuery.isEmpty) return original;
    final query = _searchQuery.toLowerCase();
    return original.where((b) {
      if (b.invoiceNo.toLowerCase().contains(query)) return true;
      if (b.method.toLowerCase().contains(query)) return true;
      if (b.totalAmount.toStringAsFixed(2).contains(query)) return true;
      for (final it in b.items) {
        if (it.name.toLowerCase().contains(query)) return true;
      }
      return false;
    }).toList();
  }

  Future<void> _reprintBill(BillReceiptData bill) async {
    if (_printingInvoiceNo != null) return; // Prevent duplicate reprint calls while printing

    if (widget.selectedPrinter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No printer selected. Please configure a printer in Settings.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _printingInvoiceNo = bill.invoiceNo);

    try {
      BillReceiptData billToPrint = bill;

      // If items are empty (because it was loaded from sale summary list),
      // fetch full details from backend before printing!
      if (billToPrint.items.isEmpty && billToPrint.id.isNotEmpty) {
        try {
          billToPrint =
              await ApiService().getSaleInvoiceDetails(billToPrint.id);
        } catch (e) {
          throw Exception("Could not fetch bill items: $e");
        }
      }

      final success = await PrinterHelper.printBillReceipt(
        widget.selectedPrinter,
        billToPrint,
        isReprint: true,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Reprinted ${bill.invoiceNo} successfully!',
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Printer busy or failed to print ${bill.invoiceNo}.',
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print failed: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _printingInvoiceNo = null);
    }
  }

  void _showBillDetailsModal(BillReceiptData bill) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BillDetailsSheet(
        bill: bill,
        selectedPrinter: widget.selectedPrinter,
        onReprint: () {
          Navigator.pop(ctx);
          _reprintBill(bill);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activePrinterName = widget.selectedPrinter == null
        ? "No Printer"
        : (widget.selectedPrinter!.isInternal
            ? "Internal POS Printer"
            : (widget.selectedPrinter!.device?.name ?? "Bluetooth/USB Printer"));

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bill History & Reprint',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Row(
              children: [
                Icon(
                  widget.selectedPrinter == null
                      ? Icons.print_disabled
                      : Icons.print,
                  size: 13,
                  color: widget.selectedPrinter == null
                      ? Colors.red
                      : Colors.green,
                ),
                const SizedBox(width: 4),
                Text(
                  activePrinterName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Bills',
            onPressed: _fetchAllTabsData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorWeight: 3,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('This Shift', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_shiftBills.length}${_shiftHasMore ? "+" : ""}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Today', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_todayBills.length}${_todayHasMore ? "+" : ""}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Offline', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_offlineBills.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_offlineBills.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Instant Search Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.white,
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              onChanged: (val) {
                _debounceTimer?.cancel();
                _debounceTimer = Timer(const Duration(milliseconds: 200), () {
                  setState(() => _searchQuery = val.trim());
                });
              },
              decoration: InputDecoration(
                hintText: 'Search by Invoice No, Amount, or Item name...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
          ),

          // Bill List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildBillsList(
                        bills: _getFilteredList(_shiftBills),
                        emptyMessage: 'No bills found in this shift.',
                        scrollController: _shiftScrollCtrl,
                        isLoadingMore: _isLoadingMoreShift,
                        hasMore: _shiftHasMore,
                        onRefresh: _fetchAllTabsData,
                      ),
                      _buildBillsList(
                        bills: _getFilteredList(_todayBills),
                        emptyMessage: 'No bills found today.',
                        scrollController: _todayScrollCtrl,
                        isLoadingMore: _isLoadingMoreToday,
                        hasMore: _todayHasMore,
                        onRefresh: _fetchAllTabsData,
                      ),
                      _buildOfflineTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerManualOfflineSync() async {
    if (_isSyncingOffline) return;
    setState(() => _isSyncingOffline = true);

    try {
      final synced = await ApiService().syncOfflineSales();
      await _fetchAllTabsData();
      if (mounted) {
        if (synced > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully synced $synced offline bills to cloud!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All bills synced or network busy.'),
              backgroundColor: Colors.blue,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncingOffline = false);
    }
  }

  Widget _buildOfflineTab() {
    final filtered = _getFilteredList(_offlineBills);
    if (_offlineBills.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchAllTabsData,
        child: ListView(
          controller: _offlineScrollCtrl,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_done_outlined, size: 64, color: Colors.green.shade400),
                    const SizedBox(height: 12),
                    Text(
                      'All bills are fully synced to cloud!',
                      style: TextStyle(fontSize: 16, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'No pending offline bills on this device.',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.cloud_off_rounded, color: Colors.amber.shade800, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_offlineBills.length} Offline Bills Saved Locally',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.amber.shade900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Auto-syncs in background every 30s or tap to sync now:',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isSyncingOffline ? null : _triggerManualOfflineSync,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: _isSyncingOffline
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.cloud_upload_outlined, size: 18),
                label: Text(_isSyncingOffline ? 'Syncing...' : 'Sync Now'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildBillsList(
            bills: filtered,
            emptyMessage: 'No matching offline bills found.',
            scrollController: _offlineScrollCtrl,
            isLoadingMore: false,
            hasMore: false,
            onRefresh: _fetchAllTabsData,
          ),
        ),
      ],
    );
  }

  Widget _buildBillsList({
    required List<BillReceiptData> bills,
    required String emptyMessage,
    required ScrollController scrollController,
    required bool isLoadingMore,
    required bool hasMore,
    required Future<void> Function() onRefresh,
  }) {
    if (bills.isEmpty && !isLoadingMore) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.45,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      emptyMessage,
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final showFooter = isLoadingMore || (!hasMore && bills.length >= _pageSize);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        itemCount: bills.length + (showFooter ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == bills.length) {
            if (isLoadingMore) {
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Loading more bills...',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              );
            }
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              child: Text(
                '— All ${bills.length} bills loaded —',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            );
          }
        final bill = bills[index];
        final isPrinting = (_printingInvoiceNo == bill.invoiceNo);

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0.8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showBillDetailsModal(bill),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Receipt Icon with Status Badge
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: bill.isOffline
                          ? Colors.amber.shade50
                          : (bill.isCancelled
                              ? Colors.red.shade50
                              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      bill.isOffline
                          ? Icons.cloud_off
                          : (bill.isCancelled
                              ? Icons.cancel_outlined
                              : Icons.receipt_long),
                      color: bill.isOffline
                          ? Colors.amber.shade800
                          : (bill.isCancelled
                              ? Colors.red.shade700
                              : Theme.of(context).colorScheme.primary),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Middle: Bill info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              bill.invoiceNo,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            if (bill.isOffline) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'OFFLINE',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                            if (bill.isCancelled) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'CANCELLED',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text(
                              formatBillDate(bill.dateStr),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                bill.method,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Amount and Reprint Button
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Rs ${bill.totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          elevation: 0,
                        ),
                        onPressed: isPrinting ? null : () => _reprintBill(bill),
                        icon: isPrinting
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.print, size: 14),
                        label: Text(
                          isPrinting ? 'Printing...' : 'Reprint',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
}

class _BillDetailsSheet extends StatefulWidget {
  final BillReceiptData bill;
  final SelectedPrinter? selectedPrinter;
  final VoidCallback onReprint;

  const _BillDetailsSheet({
    required this.bill,
    this.selectedPrinter,
    required this.onReprint,
  });

  @override
  State<_BillDetailsSheet> createState() => _BillDetailsSheetState();
}

class _BillDetailsSheetState extends State<_BillDetailsSheet> {
  bool _isLoadingItems = false;
  late BillReceiptData _activeBill;

  @override
  void initState() {
    super.initState();
    _activeBill = widget.bill;
    if (_activeBill.items.isEmpty && _activeBill.id.isNotEmpty) {
      _loadFullBillDetails();
    }
  }

  Future<void> _loadFullBillDetails() async {
    setState(() => _isLoadingItems = true);
    try {
      final full = await ApiService().getSaleInvoiceDetails(_activeBill.id);
      if (mounted) {
        setState(() {
          _activeBill = full;
          _isLoadingItems = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingItems = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activeBill.invoiceNo,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      formatBillDate(_activeBill.dateStr),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content / Thermal preview
          Expanded(
            child: _isLoadingItems
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Duplicate reprint banner preview
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '*** DUPLICATE REPRINT ***',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E40AF),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: Text(
                              _activeBill.invoiceNo,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Center(
                            child: Text(
                              'Date: ${formatBillDate(_activeBill.dateStr)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '------------------------------------------------',
                            style: TextStyle(color: Colors.grey),
                          ),

                          // Items
                          if (_activeBill.items.isEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Line items not loaded.',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            )
                          else
                            ..._activeBill.items.map((item) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${item.name} x${item.quantityString}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'Rs ${item.lineTotal.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),

                          const Text(
                            '------------------------------------------------',
                            style: TextStyle(color: Colors.grey),
                          ),

                          // Subtotal & Roundoff
                          if (_activeBill.roundOff.abs() > 0.001) ...[
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('SUBTOTAL',
                                    style: TextStyle(fontSize: 13)),
                                Text(
                                  'Rs ${_activeBill.subtotal.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('ROUND OFF',
                                    style: TextStyle(fontSize: 13)),
                                Text(
                                  '${_activeBill.roundOff > 0 ? "+" : ""}${_activeBill.roundOff.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                          ],

                          // Total
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'TOTAL',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Rs ${_activeBill.totalAmount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),

                          // Method
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('METHOD',
                                  style: TextStyle(fontSize: 13)),
                              Text(
                                _activeBill.method,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const Text(
                            '------------------------------------------------',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const Center(
                            child: Text(
                              'Thank You!\nPlease visit again',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),

          // Action Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D000000),
                  offset: Offset(0, -2),
                  blurRadius: 10,
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                onPressed: widget.onReprint,
                icon: const Icon(Icons.print, size: 20),
                label: const Text(
                  'Reprint Duplicate Bill',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
