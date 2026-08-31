package com.example.erp_pos

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.FileOutputStream
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "pos_printer"

    // Common internal serial port paths for Unisoc/MediaTek-based Android POS devices
    private val SERIAL_PATHS = listOf("/dev/ttyS1", "/dev/ttyS2", "/dev/ttyS3", "/dev/ttyS0")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "printBytes" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null) {
                        result.error("INVALID_ARGS", "bytes argument is null", null)
                        return@setMethodCallHandler
                    }
                    // Run on a background thread so we never block the UI
                    Thread {
                        val success = printToSerial(bytes)
                        runOnUiThread {
                            if (success) result.success(true)
                            else result.error("PRINT_FAILED", "Could not write to any serial port", null)
                        }
                    }.start()
                }
                "testPrinter" -> {
                    Thread {
                        // ESC/POS: initialize + print test text + cut
                        val testBytes = byteArrayOf(0x1B, 0x40) + // ESC @ (init)
                            "Test Print OK\n\n\n".toByteArray() +
                            byteArrayOf(0x1D, 0x56, 0x41, 0x00) // cut
                        val success = printToSerial(testBytes)
                        runOnUiThread {
                            result.success(success)
                        }
                    }.start()
                }
                "getAvailablePort" -> {
                    val available = SERIAL_PATHS.firstOrNull { File(it).exists() }
                    result.success(available)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun printToSerial(bytes: ByteArray): Boolean {
        for (path in SERIAL_PATHS) {
            try {
                val file = File(path)
                if (!file.exists()) continue

                val fos = FileOutputStream(file)
                fos.write(bytes)
                fos.flush()
                fos.close()
                android.util.Log.d("POS_PRINTER", "Printed to $path (${bytes.size} bytes)")
                return true
            } catch (e: Exception) {
                android.util.Log.w("POS_PRINTER", "Failed to print to $path: ${e.message}")
                continue
            }
        }
        return false
    }
}
