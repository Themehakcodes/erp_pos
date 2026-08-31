import 'package:flutter/material.dart';
import 'api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'screens/opening_balance_screen.dart';
import 'screens/main_home.dart';
import 'screens/pos_screen.dart';
import 'screens/sales_screen.dart';
import 'screens/settings_tab.dart';
import 'screens/login_screen.dart';
import 'screens/splash_loader.dart';
import 'screens/device_not_registered_screen.dart';


void main() {
  runApp(const PosApp());
}






// Wrapper for the selected printer














class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '20 MART POS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const SplashLoader(),
    );
  }
}
