import 'package:flutter/material.dart';
import 'screens/splash_loader.dart';

void main() async {
  // MUST be called before any Flutter binding or plugin usage
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const PosApp());
}

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
