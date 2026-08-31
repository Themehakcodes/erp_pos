import 'main_home.dart';
import 'pos_screen.dart';
import 'sales_screen.dart';
import 'settings_tab.dart';
import 'login_screen.dart';
import 'splash_loader.dart';
import 'device_not_registered_screen.dart';
import 'opening_balance_screen.dart';
import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import '../api_service.dart';
import '../models/models.dart';
import 'package:flutter/material.dart';

class SalesScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final double actualCashSales = totalCash - openingBalance;
    final double totalSales = actualCashSales + totalUpi;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Sales Report',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          margin: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              _buildSummaryCard(
                title: 'Total Sales Today',
                amount: totalSales,
                color: Colors.blue.shade700,
                icon: Icons.storefront,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard(
                      title: 'Cash Sales',
                      amount: actualCashSales,
                      color: Colors.green.shade600,
                      icon: Icons.money,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildSummaryCard(
                      title: 'UPI Sales',
                      amount: totalUpi,
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
                      amount: openingBalance,
                      color: Colors.orange.shade700,
                      icon: Icons.account_balance,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildSummaryCard(
                      title: 'Cash in Drawer',
                      amount: totalCash,
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
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
                  color: color.withOpacity(0.1),
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


