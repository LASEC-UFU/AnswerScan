import 'package:flutter/services.dart';

import '../../domain/entities/answer_sheet.dart';
import '../../domain/entities/omr_scan_result.dart';

/// Flutter client for the native Kotlin/OpenCV OMR scanner.
///
/// All heavy image processing runs in Kotlin on a background thread via the
/// platform channel [_channel].  This class only handles serialisation and
/// deserialisation of the result map.
class OmrNativeChannel {
  static const _channel = MethodChannel('com.example.answer_scan/omr');

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Scans [imagePath] and returns a parsed [AnswerSheet].
  ///
  /// Throws [OmrScanException] when the native scanner reports an error
  /// (e.g. blurry image, markers not found).
  static Future<AnswerSheet> scan(String imagePath) async {
    final result = await _invoke(imagePath, debug: false);
    if (!result.success) {
      throw OmrScanException(result.error ?? 'Scan failed');
    }
    return result.toAnswerSheet();
  }

  /// Scans and returns the full [OmrScanResult] including scores, confidence,
  /// and an optional debug JPEG path.
  static Future<OmrScanResult> scanFull(
    String imagePath, {
    bool debug = false,
  }) async {
    return _invoke(imagePath, debug: debug);
  }

  /// Fast live detection: passes a raw Y-plane from a camera frame to native
  /// and returns the same corners and geometry confidence used by the full scan.
  static Future<LiveOmrDetection?> detectMarkersLive({
    required Uint8List yPlane,
    required int width,
    required int height,
    required int rowStride,
  }) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'detectMarkersLive',
        {
          'yPlane': yPlane,
          'width': width,
          'height': height,
          'rowStride': rowStride,
        },
      );
      final rawCorners = raw?['corners'] as List<dynamic>?;
      if (rawCorners == null || rawCorners.length < 8) return null;
      final corners = List.generate(4, (i) {
        final x = (rawCorners[i * 2] as num).toDouble();
        final y = (rawCorners[i * 2 + 1] as num).toDouble();
        return [x, y];
      });
      return LiveOmrDetection(
        corners: corners,
        confidence: (raw?['confidence'] as num?)?.toDouble() ?? 0,
        ready: raw?['state'] == 'ready',
      );
    } catch (_) {
      return null;
    }
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  static Future<OmrScanResult> _invoke(
    String imagePath, {
    required bool debug,
  }) async {
    try {
      final Map<Object?, Object?> raw = await _channel.invokeMethod(
        'scanSheet',
        {'imagePath': imagePath, 'debug': debug},
      );
      return OmrScanResult.fromMap(raw);
    } on PlatformException catch (e) {
      // Native side threw an error (e.g. SCAN_FAILED, INVALID_ARG)
      final details = e.details;
      if (details is Map) {
        return OmrScanResult.fromMap(details.cast<Object?, Object?>());
      }
      return OmrScanResult(
        success: false,
        status: 'ERRO',
        message: e.message ?? e.code,
        sheetStatus: 'platform_error',
        rawAnswers: {},
        confidence: {},
        scores: {},
        questionDetails: const {},
        markersDetected: 0,
        perspectiveCorrected: false,
        error: e.message ?? e.code,
      );
    }
  }
}

class LiveOmrDetection {
  const LiveOmrDetection({
    required this.corners,
    required this.confidence,
    required this.ready,
  });

  final List<List<double>> corners;
  final double confidence;
  final bool ready;
}

/// Thrown when the native scanner cannot produce a valid result.
class OmrScanException implements Exception {
  const OmrScanException(this.message);
  final String message;

  @override
  String toString() => 'OmrScanException: $message';
}
