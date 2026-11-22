import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';
import 'main_home.dart';
import 'login_screen.dart';
import 'device_not_registered_screen.dart';
import 'opening_balance_screen.dart';

class SplashLoader extends StatefulWidget {
  const SplashLoader({super.key});
  @override
  State<SplashLoader> createState() => _SplashLoaderState();
}

class _SplashLoaderState extends State<SplashLoader> {
  bool _hasError = false;
  String _errorMsg = "";

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  void _checkStatus() async {
    setState(() {
      _hasError = false;
      _errorMsg = "";
    });

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token == null) {
       if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
       return;
    }
    
    try {
      final deviceId = await ApiService().getDeviceIdentifier();
      try {
        final terminal = await ApiService().checkTerminal(deviceId);
        final terminalId = terminal['id'];
        
        final savedStore = prefs.getString('store_id');
        if (savedStore == null || savedStore.isEmpty) {
           if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DeviceNotRegisteredScreen(deviceId: deviceId, existingTerminalId: terminalId)));
           return;
        }

        final storeId = terminal['store_id'] ?? savedStore;
        await prefs.setString('terminal_id', terminalId);
        await prefs.setString('store_id', storeId);

        try {
          final fyId = await ApiService().getActiveFinancialYear();
          await prefs.setString('financial_year_id', fyId);
        } catch (e) {
           // Handle missing financial year if needed
        }

        final shift = await ApiService().getActiveShift(terminalId);
        if (shift != null) {
          await prefs.setString('shift_id', shift['id']);
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MainHome(openingBalance: (shift['opening_cash'] ?? 0.0).toDouble())));
        } else {
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const OpeningBalanceScreen()));
        }
      } catch (e) {
        // Auth/session errors → go to login
        final errStr = e.toString();
        if (errStr.contains('Session expired') || errStr.contains('Unauthorized') || errStr.contains('revoked') || errStr.contains('401')) {
          await prefs.remove('access_token');
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
          return;
        }
        
        // If we have a saved shift, go offline mode
        final offlineShiftId = prefs.getString('shift_id');
        if (offlineShiftId != null) {
           if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MainHome(openingBalance: 0.0)));
           return;
        }
        
        // Network/timeout errors → show retry screen
        if (errStr.contains('TimeoutException') || errStr.contains('SocketException') || errStr.contains('Failed host lookup') || errStr.contains('Connection refused')) {
          rethrow; // Goes to outer catch → shows retry screen
        }
        
        // Any other error (terminal not found, 404, not registered, etc.) → register device
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DeviceNotRegisteredScreen(deviceId: deviceId)));
        return;
      }
    } catch(e) {
      final offlineShiftId = prefs.getString('shift_id');
      if (offlineShiftId != null) {
         if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MainHome(openingBalance: 0.0)));
         return;
      }
      
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMsg = e.toString().replaceAll("Exception: ", "");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'Connection Error',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMsg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _checkStatus,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}


