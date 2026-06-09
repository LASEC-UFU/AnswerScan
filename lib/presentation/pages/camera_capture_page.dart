import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/omr_capture_guide.dart';
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
  bool _markersFound = false;
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
          .then((corners) {
            if (!mounted) return;
            setState(() {
              _markersFound = corners != null;
              _liveCorners = corners;
              _liveFrameWidth = image.width;
              _liveFrameHeight = image.height;
              _processingFrame = false;
            });
          })
          .catchError((_) {
            _processingFrame = false;
          });
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
    return Center(child: CameraPreview(_cameraController));
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

          final preview = ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildFullBleedPreview(),
                CustomPaint(
                  painter: _LiveCornersPainter(
                    corners: _liveCorners,
                    frameWidth: _liveFrameWidth,
                    frameHeight: _liveFrameHeight,
                  ),
                ),
                _GuideOverlay(markersFound: _markersFound),
              ],
            ),
          );

          final captureButton = FloatingActionButton.large(
            onPressed: _takingPhoto ? null : _capture,
            backgroundColor: _markersFound ? Colors.green : null,
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
  });

  final List<List<double>>? corners;
  final int frameWidth;
  final int frameHeight;

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
    final stroke = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawPath(path, stroke);
    final fill = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.fill;
    for (final point in mapped) {
      canvas.drawCircle(point, 9, fill);
    }
  }

  @override
  bool shouldRepaint(_LiveCornersPainter oldDelegate) =>
      oldDelegate.corners != corners ||
      oldDelegate.frameWidth != frameWidth ||
      oldDelegate.frameHeight != frameHeight;
}

class _GuideOverlay extends StatelessWidget {
  const _GuideOverlay({required this.markersFound});

  final bool markersFound;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double guideWidth = constraints.maxWidth * OMRCaptureGuide.widthFactor;
        double guideHeight = guideWidth * OMRCaptureGuide.heightFromWidthFactor;

        final maxHeight = constraints.maxHeight * 0.85;
        if (guideHeight > maxHeight) {
          guideHeight = maxHeight;
          guideWidth = guideHeight / OMRCaptureGuide.heightFromWidthFactor;
        }

        return Center(
          child: SizedBox(
            width: guideWidth,
            height: guideHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _GuidePainter(markersFound: markersFound)),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      markersFound
                          ? 'Marcadores detectados! Pressione para capturar.'
                          : 'Alinhe os 4 marcadores pretos com os cantos do guia.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: markersFound ? Colors.greenAccent : Colors.white,
                        fontWeight: markersFound
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter({required this.markersFound});

  final bool markersFound;

  @override
  void paint(Canvas canvas, Size size) {
    final borderColor = markersFound ? Colors.greenAccent : Colors.white;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = markersFound ? 3.5 : 2.5;
    final markerPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    final answerAreaPaint = Paint()
      ..color = markersFound
          ? Colors.greenAccent.withValues(alpha: 0.6)
          : Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRect(Offset.zero & size, borderPaint);

    final markerSide = size.shortestSide * 0.085;
    final markerInset = markerSide * 0.9;

    final markers = [
      Rect.fromLTWH(markerInset, markerInset, markerSide, markerSide),
      Rect.fromLTWH(
        size.width - markerInset - markerSide,
        markerInset,
        markerSide,
        markerSide,
      ),
      Rect.fromLTWH(
        markerInset,
        size.height - markerInset - markerSide,
        markerSide,
        markerSide,
      ),
      Rect.fromLTWH(
        size.width - markerInset - markerSide,
        size.height - markerInset - markerSide,
        markerSide,
        markerSide,
      ),
    ];

    for (final rect in markers) {
      canvas.drawRect(rect, markerPaint);
      if (markersFound) {
        canvas.drawRect(
          rect.inflate(3),
          Paint()
            ..color = Colors.greenAccent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    final answerArea = Rect.fromLTWH(
      size.width * 0.14,
      size.height * 0.24,
      size.width * 0.78,
      size.height * 0.56,
    );
    canvas.drawRect(answerArea, answerAreaPaint);
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.markersFound != markersFound;
}
