import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/entities/omr_scan_result.dart';
import '../../domain/entities/sheet_scan_session.dart';

class ScanSourceCard extends StatelessWidget {
  const ScanSourceCard({
    super.key,
    required this.title,
    required this.onCamera,
    required this.onGallery,
    required this.busy,
  });

  final String title;
  final VoidCallback? onCamera;
  final VoidCallback? onGallery;
  final bool busy;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : onCamera,
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Câmera'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Galeria'),
                ),
              ),
            ],
          ),
          if (busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    ),
  );
}

class LocalStatusBanner extends StatelessWidget {
  const LocalStatusBanner({
    super.key,
    required this.message,
    this.error = false,
  });

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? Colors.red : Colors.teal;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: TextStyle(color: color.shade700)),
    );
  }
}

class ScanReviewCard extends StatelessWidget {
  const ScanReviewCard({
    super.key,
    required this.session,
    this.onAnswerChanged,
    this.questionCount,
  });

  final SheetScanSession session;
  final void Function(int question, String answer)? onAnswerChanged;
  final int? questionCount;

  @override
  Widget build(BuildContext context) {
    final result = session.result;
    final imagePath = result.correctedImagePath ?? session.imagePath;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Imagem corrigida',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 260,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 6,
                  child: Image.file(File(imagePath), fit: BoxFit.contain),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                Chip(label: Text('${result.resolvedCount} detectadas')),
                Chip(label: Text('${result.blankCount} em branco')),
                Chip(label: Text('${result.multipleCount} múltiplas')),
                Chip(label: Text('${result.uncertainCount} ambíguas')),
                Chip(
                  label: Text(
                    'Leitura ${(result.averageConfidence * 100).toStringAsFixed(0)}%',
                  ),
                ),
                Chip(
                  label: Text(
                    'Perspectiva ${(result.perspectiveConfidence * 100).toStringAsFixed(0)}%',
                  ),
                ),
                Chip(label: Text(_focusLabel(result))),
                Chip(label: Text(_framingLabel(result))),
              ],
            ),
            const SizedBox(height: 12),
            Text('Respostas', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...List.generate(questionCount ?? 20, (index) {
              final question = index + 1;
              final answer = result.rawAnswers['$question'] ?? 'EM_BRANCO';
              final confidence = result.confidence['$question'] ?? 0;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('Questão $question'),
                subtitle: Text(
                  'Confiança ${(confidence * 100).toStringAsFixed(0)}%',
                ),
                trailing: onAnswerChanged == null
                    ? AnswerBadge(answer: answer)
                    : DropdownButton<String>(
                        value:
                            const [
                              'A',
                              'B',
                              'C',
                              'D',
                              'E',
                              'EM_BRANCO',
                            ].contains(answer)
                            ? answer
                            : null,
                        hint: Text(answer),
                        items: const ['A', 'B', 'C', 'D', 'E', 'EM_BRANCO']
                            .map(
                              (option) => DropdownMenuItem(
                                value: option,
                                child: Text(
                                  option == 'EM_BRANCO' ? 'Em branco' : option,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) onAnswerChanged!(question, value);
                        },
                      ),
              );
            }),
            const Divider(),
            Text(
              'Diagnóstico geométrico',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Ângulos: ${_value(result, 'horizontalAngle', 1)}° / '
              '${_value(result, 'verticalAngle', 1)}°   '
              'Proporção dos lados: ${_value(result, 'widthRatio', 2)} / '
              '${_value(result, 'heightRatio', 2)}',
            ),
          ],
        ),
      ),
    );
  }

  static String _value(OmrScanResult result, String key, int digits) =>
      (result.diagnostics[key] ?? 0).toStringAsFixed(digits);

  static String _focusLabel(OmrScanResult result) {
    final sharpness = result.diagnostics['sharpnessVariance'] ?? 0;
    return 'Foco: ${sharpness >= 40
        ? 'bom'
        : sharpness >= 12
        ? 'aceitável'
        : 'baixo'}';
  }

  static String _framingLabel(OmrScanResult result) {
    final area = result.diagnostics['areaFraction'] ?? 0;
    return 'Enquadramento: ${area >= 0.15 ? 'bom' : 'aceitável'}';
  }
}

class AnswerBadge extends StatelessWidget {
  const AnswerBadge({super.key, required this.answer, this.color});

  final String answer;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: (color ?? Colors.blueGrey).withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      answer,
      style: TextStyle(color: color, fontWeight: FontWeight.bold),
    ),
  );
}
