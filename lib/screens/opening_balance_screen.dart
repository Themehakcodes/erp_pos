import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../api_service.dart';
import 'main_home.dart';
import 'login_screen.dart';
import '../models/models.dart';
import '../printer_helper.dart';

class OpeningBalanceScreen extends StatefulWidget {
  const OpeningBalanceScreen({super.key});

  @override
  State<OpeningBalanceScreen> createState() => _OpeningBalanceScreenState();
}

class _OpeningBalanceScreenState extends State<OpeningBalanceScreen> {
  String _amountStr = "";
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
  }

  void _onKeyTap(String val) {
    if (val == 'C') {
      setState(() => _amountStr = "");
    } else if (val == '<') {
      if (_amountStr.isNotEmpty) {
        setState(() => _amountStr = _amountStr.substring(0, _amountStr.length - 1));
      }
    } else {
      if (val == '.' && _amountStr.contains('.')) return;
      if (val == '.' && _amountStr.isEmpty) {
        setState(() => _amountStr = "0.");
        return;
      }
      setState(() => _amountStr += val);
    }
  }

  void _submit() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final balance = double.tryParse(_amountStr) ?? 0.0;

    final prefs = await SharedPreferences.getInstance();
    final storeId = prefs.getString('store_id');
    final terminalId = prefs.getString('terminal_id');

    if (storeId == null || terminalId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device not registered. Please restart app.')),
        );
      }
      setState(() => _isSubmitting = false);
      return;
    }

    try {
      // STEP 1: Always check if a shift is already open for this terminal — same logic as web POS
      final existingShift = await ApiService().getActiveShift(terminalId);
      if (existingShift != null) {
        // Resume existing shift — do NOT create a new one
        await prefs.setString('shift_id', existingShift['id']);
        final openingCash = double.tryParse(existingShift['opening_cash'].toString()) ?? 0.0;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Resuming existing open shift...'),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => MainHome(openingBalance: openingCash)),
          );
        }
        return;
      }

      // STEP 2: No existing shift — open a fresh one
      final shift = await ApiService().openShift(storeId, terminalId, balance);
      await prefs.setString('shift_id', shift['id']);
      
      // Print Opening Receipt
      try {
        final savedData = prefs.getString('saved_printer');
        if (savedData != null) {
          final map = jsonDecode(savedData);
          final printer = SelectedPrinter.fromJson(map);
          await PrinterHelper.printShiftReceipt(printer, true, balance, storeId, terminalId);
        }
      } catch (e) {
        debugPrint('Error printing opening receipt: $e');
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => MainHome(openingBalance: balance)),
        );
      }
    } catch (e) {
      final errStr = e.toString();

      // Backend says a shift already exists — fetch and resume it
      if (errStr.contains('already has an open shift') || errStr.contains('open shift')) {
        try {
          final existingShift = await ApiService().getActiveShift(terminalId);
          if (existingShift != null) {
            await prefs.setString('shift_id', existingShift['id']);
            final openingCash = double.tryParse(existingShift['opening_cash'].toString()) ?? 0.0;
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => MainHome(openingBalance: openingCash)),
              );
            }
            return;
          }
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        if (errStr.contains('Session expired') || errStr.contains('Unauthorized') || errStr.contains('revoked')) {
          await prefs.remove('access_token');
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          }
        }
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildKey(String val) {
    return Expanded(
      child: InkWell(
        onTap: () => _onKeyTap(val),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 60,
          alignment: Alignment.center,
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Text(
            val == '<' ? '⌫' : val,
            style: TextStyle(
              fontSize: 24,
              fontWeight: (val == 'C' || val == '<') ? FontWeight.normal : FontWeight.bold,
              color: val == 'C' ? Colors.redAccent : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: const Color(0x0D000000), blurRadius: 20),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_balance_wallet, size: 50, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                'Opening Balance',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Enter the starting cash in drawer',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border.all(color: Colors.blue.shade200, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _amountStr.isEmpty ? '₹ 0' : '₹ $_amountStr',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: _amountStr.isEmpty ? Colors.grey : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),

              // Custom NumPad
              Column(
                children: [
                  Row(children: [_buildKey('1'), _buildKey('2'), _buildKey('3')]),
                  Row(children: [_buildKey('4'), _buildKey('5'), _buildKey('6')]),
                  Row(children: [_buildKey('7'), _buildKey('8'), _buildKey('9')]),
                  Row(children: [_buildKey('C'), _buildKey('0'), _buildKey('<')]),
                ],
              ),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Start Register',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const MainHome(openingBalance: 0.0)),
                  );
                },
                child: const Text(
                  'Skip for Now (Enter POS without shift)',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
