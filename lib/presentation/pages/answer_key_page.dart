import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../controllers/correction_controller.dart';
import '../widgets/scan_workflow_widgets.dart';
import 'camera_capture_page.dart';

class AnswerKeyPage extends StatefulWidget {
  const AnswerKeyPage({
    super.key,
    required this.controller,
    required this.camera,
  });

  final CorrectionController controller;
  final CameraDescription? camera;

  @override
  State<AnswerKeyPage> createState() => _AnswerKeyPageState();
}

class _AnswerKeyPageState extends State<AnswerKeyPage> {
  final _picker = ImagePicker();

  Future<void> _capture() async {
    if (widget.camera == null) return;
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CameraCapturePage(
          camera: widget.camera!,
          title: 'Capturar gabarito',
        ),
      ),
    );
    if (path != null) {
      await widget.controller.loadAnswerKey(path, debug: true);
    }
  }

  Future<void> _gallery() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (file != null) {
      await widget.controller.loadAnswerKey(file.path, debug: true);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final session = widget.controller.answerKeyScan;
      return Scaffold(
        appBar: AppBar(title: const Text('Cadastro do gabarito')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Capture → corrigir perspectiva → revisar respostas → salvar gabarito',
            ),
            const SizedBox(height: 12),
            ScanSourceCard(
              title: 'Capturar ou selecionar gabarito',
              onCamera: widget.camera == null ? null : _capture,
              onGallery: _gallery,
              busy: widget.controller.isBusy,
            ),
            if (widget.controller.answerKeyError != null) ...[
              const SizedBox(height: 8),
              LocalStatusBanner(
                message: widget.controller.answerKeyError!,
                error: true,
              ),
            ],
            if (widget.controller.answerKeyMessage != null) ...[
              const SizedBox(height: 8),
              LocalStatusBanner(message: widget.controller.answerKeyMessage!),
            ],
            if (session != null) ...[
              const SizedBox(height: 12),
              LocalStatusBanner(
                message:
                    'Quantidade detectada: ${session.result.lastResolvedQuestion} questões. '
                    'Questões em branco após esta posição serão ignoradas.',
              ),
              const SizedBox(height: 12),
              ScanReviewCard(
                session: session,
                onAnswerChanged: widget.controller.updateAnswerKey,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: widget.controller.validateAnswerKey,
                icon: const Icon(Icons.save),
                label: Text(
                  widget.controller.answerKeyValidated
                      ? 'Gabarito salvo'
                      : 'Validar e salvar gabarito',
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}
