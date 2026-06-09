import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../controllers/correction_controller.dart';
import '../controllers/moodle_controller.dart';
import 'answer_key_page.dart';
import 'calibration_page.dart';
import 'moodle_connect_page.dart';
import 'manual_grade_page.dart';
import 'student_correction_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.moodleController,
    required this.camera,
  });

  final CorrectionController controller;
  final MoodleController moodleController;
  final CameraDescription? camera;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, moodleController]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Corretor de Provas OMR'),
          actions: [
            IconButton(
              tooltip: 'Configurar Moodle',
              icon: Icon(
                Icons.school,
                color: moodleController.isFullyConfigured ? Colors.green : null,
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      MoodleConnectPage(controller: moodleController),
                ),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Escolha uma etapa',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'O cadastro do gabarito e a correção das folhas são processos independentes.',
            ),
            const SizedBox(height: 20),
            _FlowCard(
              icon: Icons.fact_check_outlined,
              title: '1. Cadastrar ou revisar gabarito',
              description:
                  'Capture, corrija a perspectiva, revise respostas e salve o gabarito validado.',
              status: controller.answerKeyValidated
                  ? 'Gabarito salvo com ${controller.answerKeyQuestionCount} questões'
                  : controller.answerKeyScan != null
                  ? 'Gabarito lido, aguardando validação'
                  : 'Nenhum gabarito salvo',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      AnswerKeyPage(controller: controller, camera: camera),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _FlowCard(
              icon: Icons.document_scanner_outlined,
              title: '2. Corrigir folha do aluno',
              description:
                  'Use o gabarito salvo, capture a folha, revise o resultado e envie a nota.',
              status: controller.answerKeyValidated
                  ? 'Pronto para corrigir'
                  : 'Valide um gabarito primeiro',
              onTap: controller.answerKeyValidated
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => StudentCorrectionPage(
                          controller: controller,
                          moodleController: moodleController,
                          camera: camera,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            _FlowCard(
              icon: Icons.edit_note,
              title: 'Lançar ou editar nota manual',
              description:
                  'Selecione uma atividade e um aluno para registrar uma nota sem gabarito.',
              status: moodleController.isFullyConfigured
                  ? 'Atividade: ${moodleController.selectedGradeItem!.name}'
                  : 'Configure o Moodle para lançar notas',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ManualGradePage(controller: moodleController),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.bug_report_outlined),
              label: const Text('Diagnóstico avançado'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CalibrationPage(camera: camera),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowCard extends StatelessWidget {
  const _FlowCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.status,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final String status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(
                icon,
                size: 42,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 5),
                    Text(description),
                    const SizedBox(height: 8),
                    Text(
                      status,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
