import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';

class SalesScreen extends StatefulWidget {
  final double openingBalance;
  final double totalCash;
  final double totalUpi;

  const SalesScreen({
    super.key,
    required this.openingBalance,
    required this.totalCash,
    required this.totalUpi,
  });

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  bool _isLoading = true;
  double _openingBalance = 0.0;
  double _cashSales = 0.0;
  double _upiSales = 0.0;
  double _totalSales = 0.0;
  double _cashInDrawer = 0.0;

  @override
  void initState() {
    super.initState();
    _openingBalance = widget.openingBalance;
    _cashSales = widget.totalCash - widget.openingBalance;
    _upiSales = widget.totalUpi;
    _totalSales = _cashSales + _upiSales;
    _cashInDrawer = widget.totalCash;
    _fetchLiveSales();
  }

  Future<void> _fetchLiveSales() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('device_identifier');
      if (deviceId != null) {
        // Fetch terminal info to get terminalId
        final terminalData = await ApiService().checkTerminal(deviceId);
        final terminalId = terminalData['id'];
        if (terminalId != null) {
          final activeShift = await ApiService().getActiveShift(terminalId);
          if (activeShift != null) {
            if (mounted) {
              setState(() {
                _openingBalance = double.tryParse(activeShift['opening_cash'].toString()) ?? widget.openingBalance;
                _cashSales = double.tryParse(activeShift['total_cash_sales'].toString()) ?? 0.0;
                _upiSales = double.tryParse(activeShift['total_upi_sales'].toString()) ?? 0.0;
                _totalSales = double.tryParse(activeShift['total_sales_amount'].toString()) ?? 0.0;
                _cashInDrawer = _openingBalance + _cashSales;
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Failed to fetch live sales: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Live Sales Report',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _fetchLiveSales();
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                margin: const EdgeInsets.all(16.0),
                child: ListView(
                  children: [
                    _buildSummaryCard(
                      title: 'Total Sales Today',
                      amount: _totalSales,
                      color: Colors.blue.shade700,
                      icon: Icons.storefront,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryCard(
                            title: 'Cash Sales',
                            amount: _cashSales,
                            color: Colors.green.shade600,
                            icon: Icons.money,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildSummaryCard(
                            title: 'UPI Sales',
                            amount: _upiSales,
                            color: Colors.purple.shade600,
                            icon: Icons.qr_code,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryCard(
                            title: 'Opening Balance',
                            amount: _openingBalance,
                            color: Colors.orange.shade700,
                            icon: Icons.account_balance,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildSummaryCard(
                            title: 'Cash in Drawer',
                            amount: _cashInDrawer,
                            color: Colors.teal.shade700,
                            icon: Icons.account_balance_wallet,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required double amount,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
