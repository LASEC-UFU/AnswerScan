package com.example.answer_scan

import android.util.Log
import com.example.answer_scan.omr.TemplateScanner
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.OpenCVLoader
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.example.answer_scan/omr"
    }

    private val templateScanner by lazy { TemplateScanner() }
    private val scanExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var isOpenCvReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        isOpenCvReady = OpenCVLoader.initLocal()
        Log.i(TAG, "OpenCV initialisation: ${if (isOpenCvReady) "OK" else "FAILED"}")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (!isOpenCvReady) {
                    result.error(
                        "OPENCV_INIT_FAILED",
                        "OpenCV nao foi inicializado no Android.",
                        null,
                    )
                    return@setMethodCallHandler
                }

                when (call.method) {
                    "scanSheet" -> {
                        val imagePath = call.argument<String>("imagePath")
                        val debug = call.argument<Boolean>("debug") ?: false
                        if (imagePath.isNullOrBlank()) {
                            result.error("INVALID_ARG", "imagePath is required", null)
                            return@setMethodCallHandler
                        }

                        scanExecutor.execute {
                            try {
                                val scanResult = templateScanner.scan(imagePath, debug)
                                runOnUiThread {
                                    val success = scanResult["success"] as? Boolean ?: false
                                    if (success) {
                                        result.success(scanResult)
                                    } else {
                                        val error = scanResult["error"] as? String ?: "Scan failed"
                                        result.error("SCAN_FAILED", error, scanResult)
                                    }
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Uncaught exception in TemplateScanner", e)
                                runOnUiThread {
                                    result.error(
                                        "SCAN_EXCEPTION",
                                        e.message ?: "Erro interno no scanner nativo.",
                                        null,
                                    )
                                }
                            }
                        }
                    }

                    "detectMarkersLive" -> {
                        val yPlane    = call.argument<ByteArray>("yPlane")
                        val width     = call.argument<Int>("width")
                        val height    = call.argument<Int>("height")
                        val rowStride = call.argument<Int>("rowStride")

                        if (yPlane == null || width == null || height == null || rowStride == null) {
                            result.error("INVALID_ARG", "yPlane, width, height, rowStride are required", null)
                            return@setMethodCallHandler
                        }

                        scanExecutor.execute {
                            try {
                                val detection = templateScanner.detectMarkersLive(yPlane, width, height, rowStride)
                                runOnUiThread { result.success(detection) }
                            } catch (e: Exception) {
                                Log.w(TAG, "detectMarkersLive error: ${e.message}")
                                runOnUiThread { result.success(null) }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        scanExecutor.shutdownNow()
        super.onDestroy()
    }
}
