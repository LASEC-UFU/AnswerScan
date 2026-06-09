import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/services/omr_native_channel.dart';
import '../../domain/entities/omr_scan_result.dart';
import 'camera_capture_page.dart';

class CalibrationPage extends StatefulWidget {
  const CalibrationPage({super.key, required this.camera});

  final CameraDescription? camera;

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> {
  final ImagePicker _imagePicker = ImagePicker();

  OmrScanResult? _scanResult;
  String? _imagePath;
  String? _error;
  bool _isBusy = false;

  Future<void> _captureAndAnalyze() async {
    final camera = widget.camera;
    if (camera == null) {
      setState(() {
        _error = 'Nenhuma camera disponivel para diagnostico.';
      });
      return;
    }

    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CameraCapturePage(
          camera: camera,
          title: 'Capturar folha para diagnostico',
        ),
      ),
    );

    if (path == null) {
      return;
    }

    await _analyze(path);
  }

  Future<void> _pickAndAnalyze() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (file == null) {
      return;
    }

    await _analyze(file.path);
  }

  Future<void> _reanalyze() async {
    final imagePath = _imagePath;
    if (imagePath == null) {
      return;
    }

    await _analyze(imagePath);
  }

  Future<void> _analyze(String imagePath) async {
    setState(() {
      _isBusy = true;
      _imagePath = imagePath;
      _error = null;
    });

    try {
      final result = await OmrNativeChannel.scanFull(imagePath, debug: true);

      if (!mounted) {
        return;
      }

      setState(() {
        _scanResult = result;
        if (!result.success) {
          _error = result.error ?? 'Falha no diagnostico.';
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _scanResult = null;
        _error =
            'Falha no diagnostico: '
            '${error.toString().replaceFirst('OmrScanException: ', '')}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _scanResult;
    final debugPath = result?.debugImagePath;

    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostico nativo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Executa o scanner Kotlin/OpenCV com debug habilitado para '
              'validar marcadores, homografia, ROIs e scores.',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isBusy ? null : _captureAndAnalyze,
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isBusy ? null : _pickAndAnalyze,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galeria'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isBusy || _imagePath == null ? null : _reanalyze,
              icon: const Icon(Icons.refresh),
              label: const Text('Reprocessar'),
            ),
            if (_isBusy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              _InfoCard(
                title: 'Falha',
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              _InfoCard(
                title: 'Resumo da folha',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status OMR: ${result.status}'),
                    Text('Mensagem: ${result.message}'),
                    Text('Status: ${result.sheetStatus}'),
                    Text('Marcadores detectados: ${result.markersDetected}'),
                    Text(
                      'Perspectiva corrigida: '
                      '${result.perspectiveCorrected ? 'sim' : 'nao'}',
                    ),
                    Text(
                      'Confianca media: '
                      '${(result.averageConfidence * 100).toStringAsFixed(0)}%',
                    ),
                    Text('Questoes para revisar: ${result.unresolvedCount}'),
                    if (_imagePath != null)
                      Text('Imagem: ${_basename(_imagePath!)}'),
                  ],
                ),
              ),
              if (debugPath != null && File(debugPath).existsSync()) ...[
                const SizedBox(height: 16),
                _InfoCard(
                  title: 'Debug gerado',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(File(debugPath), fit: BoxFit.cover),
                      ),
                      const SizedBox(height: 8),
                      Text('Arquivo: ${_basename(debugPath)}'),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _InfoCard(
                title: 'Pontos de calibracao no codigo nativo',
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TemplateConfig.HEADER_HEIGHT_FRAC'),
                    Text('TemplateConfig.LABEL_WIDTH_FRAC'),
                    Text('TemplateConfig.CELL_READ_FRAC'),
                    Text('TemplateConfig.BLANK_THRESHOLD'),
                    Text('TemplateConfig.FILL_THRESHOLD'),
                    Text('TemplateConfig.GAP_RATIO'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Diagnostico por questao',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...List.generate(20, (index) {
                final question = index + 1;
                final answer = result.rawAnswers['$question'] ?? '-';
                final confidence = result.confidence['$question'] ?? 0;
                final detail = result.questionDetails['$question'];
                final scores = result.scores['$question'] ?? const [];

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Q${question.toString().padLeft(2, '0')} -> $answer',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Confianca: ${(confidence * 100).toStringAsFixed(0)}%',
                        ),
                        const SizedBox(height: 6),
                        Text(
                          detail != null
                              ? _formatFillMap(detail.fillByOption)
                              : _formatScores(scores),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatScores(List<double> scores) {
    const labels = ['A', 'B', 'C', 'D', 'E'];
    if (scores.isEmpty) {
      return 'Sem scores.';
    }

    final parts = <String>[];
    for (
      var index = 0;
      index < scores.length && index < labels.length;
      index++
    ) {
      parts.add('${labels[index]}=${scores[index].toStringAsFixed(3)}');
    }
    return parts.join('  ');
  }

  static String _formatFillMap(Map<String, double> fillByOption) {
    if (fillByOption.isEmpty) {
      return 'Sem preenchimentos.';
    }

    final labels = ['A', 'B', 'C', 'D', 'E'];
    final parts = <String>[];
    for (final label in labels) {
      final value = fillByOption[label];
      if (value != null) {
        parts.add('$label=${value.toStringAsFixed(3)}');
      }
    }
    return parts.join('  ');
  }

  static String _basename(String path) {
    final parts = path.split(Platform.pathSeparator);
    return parts.isEmpty ? path : parts.last;
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
