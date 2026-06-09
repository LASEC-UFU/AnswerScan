import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/services/omr_native_channel.dart';

class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({
    super.key,
    required this.camera,
    required this.title,
  });

  final CameraDescription camera;
  final String title;

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage> {
  late final CameraController _cameraController;
  late final Future<void> _initializeFuture;

  bool _takingPhoto = false;

  // Live marker detection state
  bool _captureReady = false;
  bool _sheetDetected = false;
  double _detectionConfidence = 0;
  bool _streamActive = false;
  int _lastDetectionMs = 0;
  bool _processingFrame = false;
  List<List<double>>? _liveCorners;
  int _liveFrameWidth = 1;
  int _liveFrameHeight = 1;
  DeviceOrientation _captureOrientation = DeviceOrientation.portraitUp;

  @override
  void initState() {
    super.initState();
    _cameraController = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _initializeFuture = _cameraController.initialize().then((_) {
      if (mounted) {
        _startLiveDetection();
      }
    });
  }

  void _startLiveDetection() {
    if (_streamActive) return;
    _streamActive = true;
    _cameraController.startImageStream((CameraImage image) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_processingFrame || now - _lastDetectionMs < 700) return;
      _processingFrame = true;
      _lastDetectionMs = now;

      final plane = image.planes[0];
      OmrNativeChannel.detectMarkersLive(
            yPlane: plane.bytes,
            width: image.width,
            height: image.height,
            rowStride: plane.bytesPerRow,
          )
          .then((detection) {
            if (!mounted) return;
            setState(() {
              _sheetDetected = detection != null;
              _captureReady = detection?.ready ?? false;
              _detectionConfidence = detection?.confidence ?? 0;
              _liveCorners = detection == null
                  ? null
                  : _smoothCorners(_liveCorners, detection.corners);
              _liveFrameWidth = image.width;
              _liveFrameHeight = image.height;
              _processingFrame = false;
            });
          })
          .catchError((_) {
            if (mounted) {
              setState(() {
                _sheetDetected = false;
                _captureReady = false;
                _detectionConfidence = 0;
                _liveCorners = null;
              });
            }
            _processingFrame = false;
          });
    });
  }

  List<List<double>> _smoothCorners(
    List<List<double>>? previous,
    List<List<double>> current,
  ) {
    if (previous == null || previous.length != current.length) return current;
    const currentWeight = 0.45;
    return List.generate(current.length, (index) {
      return [
        previous[index][0] * (1 - currentWeight) +
            current[index][0] * currentWeight,
        previous[index][1] * (1 - currentWeight) +
            current[index][1] * currentWeight,
      ];
    });
  }

  @override
  void dispose() {
    if (_streamActive) {
      try {
        _cameraController.stopImageStream();
      } catch (_) {}
    }
    _cameraController.dispose();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Future<void> _toggleOrientation() async {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final target = isLandscape
        ? DeviceOrientation.portraitUp
        : DeviceOrientation.landscapeLeft;

    await _cameraController.lockCaptureOrientation(target);
    await SystemChrome.setPreferredOrientations([target]);
    if (mounted) {
      setState(() => _captureOrientation = target);
    }
  }

  Future<void> _capture() async {
    if (_takingPhoto) return;
    setState(() => _takingPhoto = true);

    try {
      // Stop stream before takePicture to avoid conflicts
      if (_streamActive) {
        await _cameraController.stopImageStream();
        _streamActive = false;
      }
      await _initializeFuture;
      final file = await _cameraController.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(file.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Falha ao tirar foto. Tente novamente.')),
      );
    } finally {
      if (mounted) setState(() => _takingPhoto = false);
    }
  }

  Widget _buildFullBleedPreview() {
    return Center(
      child: CameraPreview(
        _cameraController,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _LiveCornersPainter(
                corners: _liveCorners,
                frameWidth: _liveFrameWidth,
                frameHeight: _liveFrameHeight,
                ready: _captureReady,
              ),
            ),
            _DetectionStatus(
              detected: _sheetDetected,
              ready: _captureReady,
              confidence: _detectionConfidence,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _toggleOrientation,
            tooltip: _captureOrientation == DeviceOrientation.portraitUp
                ? 'Usar modo paisagem'
                : 'Usar modo retrato',
            icon: Icon(
              _captureOrientation == DeviceOrientation.portraitUp
                  ? Icons.stay_current_landscape
                  : Icons.stay_current_portrait,
            ),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initializeFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Erro ao iniciar camera: ${snapshot.error}'),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final preview = ClipRect(child: _buildFullBleedPreview());

          final captureButton = FloatingActionButton.large(
            onPressed: _takingPhoto ? null : _capture,
            backgroundColor: _captureReady
                ? Colors.green
                : _sheetDetected
                ? Colors.amber.shade700
                : null,
            child: _takingPhoto
                ? const CircularProgressIndicator()
                : const Icon(Icons.camera_alt),
          );

          if (isLandscape) {
            return Row(
              children: [
                Expanded(child: preview),
                SafeArea(
                  left: false,
                  child: Container(
                    color: Colors.black,
                    width: 104,
                    child: Center(child: captureButton),
                  ),
                ),
              ],
            );
          }

          return Column(
            children: [
              Expanded(child: preview),
              SafeArea(
                top: false,
                child: Container(
                  color: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Center(child: captureButton),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LiveCornersPainter extends CustomPainter {
  const _LiveCornersPainter({
    required this.corners,
    required this.frameWidth,
    required this.frameHeight,
    required this.ready,
  });

  final List<List<double>>? corners;
  final int frameWidth;
  final int frameHeight;
  final bool ready;

  @override
  void paint(Canvas canvas, Size size) {
    final points = corners;
    if (points == null || points.length != 4) return;

    Offset mapPoint(List<double> point) {
      if (frameWidth > frameHeight && size.height > size.width) {
        return Offset(
          point[1] / frameHeight * size.width,
          (1 - point[0] / frameWidth) * size.height,
        );
      }
      return Offset(
        point[0] / frameWidth * size.width,
        point[1] / frameHeight * size.height,
      );
    }

    final mapped = points.map(mapPoint).toList();
    final path = Path()
      ..moveTo(mapped[0].dx, mapped[0].dy)
      ..lineTo(mapped[1].dx, mapped[1].dy)
      ..lineTo(mapped[3].dx, mapped[3].dy)
      ..lineTo(mapped[2].dx, mapped[2].dy)
      ..close();
    final color = ready ? Colors.greenAccent : Colors.amberAccent;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawPath(path, stroke);
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (final point in mapped) {
      canvas.drawCircle(point, 9, fill);
    }
  }

  @override
  bool shouldRepaint(_LiveCornersPainter oldDelegate) =>
      oldDelegate.corners != corners ||
      oldDelegate.frameWidth != frameWidth ||
      oldDelegate.frameHeight != frameHeight ||
      oldDelegate.ready != ready;
}

class _DetectionStatus extends StatelessWidget {
  const _DetectionStatus({
    required this.detected,
    required this.ready,
    required this.confidence,
  });

  final bool detected;
  final bool ready;
  final double confidence;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        ready
            ? 'Folha detectada. Pronto para capturar '
                  '(${(confidence * 100).toStringAsFixed(0)}%).'
            : detected
            ? 'Folha detectada parcialmente. Ajuste o posicionamento.'
            : 'Procurando os quatro marcadores da folha...',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: ready
              ? Colors.greenAccent
              : detected
              ? Colors.amberAccent
              : Colors.white,
          fontWeight: ready ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    ),
  );
}
