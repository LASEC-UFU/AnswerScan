import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/models/moodle_models.dart';
import '../../domain/entities/answer_option.dart';
import '../controllers/correction_controller.dart';
import '../controllers/moodle_controller.dart';
import '../widgets/scan_workflow_widgets.dart';
import 'camera_capture_page.dart';
import 'moodle_connect_page.dart';

class StudentCorrectionPage extends StatefulWidget {
  const StudentCorrectionPage({
    super.key,
    required this.controller,
    required this.moodleController,
    required this.camera,
  });

  final CorrectionController controller;
  final MoodleController moodleController;
  final CameraDescription? camera;

  @override
  State<StudentCorrectionPage> createState() => _StudentCorrectionPageState();
}

class _StudentCorrectionPageState extends State<StudentCorrectionPage> {
  final _picker = ImagePicker();

  Future<void> _capture() async {
    if (widget.camera == null) return;
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CameraCapturePage(
          camera: widget.camera!,
          title: 'Capturar folha do aluno',
        ),
      ),
    );
    if (path != null) {
      await widget.controller.loadStudentSheet(path, debug: true);
    }
  }

  Future<void> _gallery() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (file != null) {
      await widget.controller.loadStudentSheet(file.path, debug: true);
    }
  }

  Future<void> _grade() async {
    final result = widget.controller.grade();
    if (result == null || !widget.moodleController.isReadyToSubmit) return;
    final activity = widget.moodleController.selectedGradeItem!;
    final student = widget.moodleController.selectedStudent!;
    final calculated =
        result.correctAnswers / result.totalQuestions * activity.gradeMax;
    final grade = await _reviewGrade(student, activity, calculated);
    if (grade == null) return;
    final ok = await widget.moodleController.submitGrade(
      studentId: student.id,
      correctAnswers: result.correctAnswers,
      totalQuestions: result.totalQuestions,
      gradeOverride: grade,
    );
    if (ok) {
      widget.moodleController.selectStudent(null);
    }
  }

  Future<double?> _reviewGrade(
    MoodleStudent student,
    MoodleGradeItem activity,
    double calculated,
  ) {
    final text = TextEditingController(
      text: calculated.toStringAsFixed(2).replaceFirst('.', ','),
    );
    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revisar nota'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(student.fullname),
            Text(activity.name),
            const SizedBox(height: 12),
            TextField(
              controller: text,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Nota a enviar',
                suffixText: '/ ${activity.gradeMax.toStringAsFixed(2)}',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(text.text.replaceAll(',', '.'));
              if (value != null && value >= 0 && value <= activity.gradeMax) {
                Navigator.pop(context, value);
              }
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    ).whenComplete(text.dispose);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.controller, widget.moodleController]),
    builder: (context, _) {
      final session = widget.controller.studentSheetScan;
      final result = widget.controller.result;
      return Scaffold(
        appBar: AppBar(title: const Text('Correção da folha do aluno')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Gabarito salvo → capturar folha → corrigir perspectiva → revisar → corrigir',
            ),
            const SizedBox(height: 12),
            _MoodleStudentCard(
              controller: widget.moodleController,
              onConfigure: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      MoodleConnectPage(controller: widget.moodleController),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ScanSourceCard(
              title: 'Capturar ou selecionar folha do aluno',
              onCamera: widget.camera == null ? null : _capture,
              onGallery: _gallery,
              busy: widget.controller.isBusy,
            ),
            if (widget.controller.studentError != null) ...[
              const SizedBox(height: 8),
              LocalStatusBanner(
                message: widget.controller.studentError!,
                error: true,
              ),
            ],
            if (widget.controller.studentMessage != null) ...[
              const SizedBox(height: 8),
              LocalStatusBanner(message: widget.controller.studentMessage!),
            ],
            if (session != null) ...[
              const SizedBox(height: 12),
              ScanReviewCard(session: session),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed:
                    widget.controller.isBusy ||
                        (widget.moodleController.isFullyConfigured &&
                            !widget.moodleController.isReadyToSubmit)
                    ? null
                    : _grade,
                icon: const Icon(Icons.done_all),
                label: Text(
                  widget.moodleController.isFullyConfigured
                      ? 'Corrigir, revisar e enviar nota'
                      : 'Corrigir folha',
                ),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 12),
              _DetailedResult(controller: widget.controller),
            ],
          ],
        ),
      );
    },
  );
}

class _MoodleStudentCard extends StatelessWidget {
  const _MoodleStudentCard({
    required this.controller,
    required this.onConfigure,
  });
  final MoodleController controller;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    if (!controller.isFullyConfigured) {
      return OutlinedButton.icon(
        onPressed: onConfigure,
        icon: const Icon(Icons.school),
        label: const Text('Configurar atividade do Moodle'),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Atividade: ${controller.selectedGradeItem!.name}'),
            const SizedBox(height: 8),
            Autocomplete<MoodleStudent>(
              displayStringForOption: (student) => student.fullname,
              optionsBuilder: (value) {
                final query = value.text.toLowerCase();
                return controller.students.where(
                  (student) => student.fullname.toLowerCase().contains(query),
                );
              },
              onSelected: controller.selectStudent,
              fieldViewBuilder: (context, text, focus, submit) => TextField(
                controller: text,
                focusNode: focus,
                onChanged: (_) {
                  if (controller.selectedStudent != null) {
                    controller.selectStudent(null);
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Aluno desta correção',
                  prefixIcon: Icon(Icons.person_search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailedResult extends StatelessWidget {
  const _DetailedResult({required this.controller});
  final CorrectionController controller;

  @override
  Widget build(BuildContext context) {
    final key = controller.answerKeyScan!.answerSheet.answers;
    final student = controller.studentSheetScan!.answerSheet.answers;
    final result = controller.result!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${result.correctAnswers} de ${result.totalQuestions} corretas '
              '(${(result.correctAnswers / result.totalQuestions * 100).toStringAsFixed(0)}%)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            ...List.generate(20, (index) {
              final answer = student[index];
              final correct = key[index];
              final isCorrect = answer != null && answer == correct;
              final color = answer == null
                  ? Colors.orange
                  : isCorrect
                  ? Colors.green
                  : Colors.red;
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: color,
                  child: Text('${index + 1}'),
                ),
                title: Text(
                  answer == null
                      ? 'Em branco ou ambígua'
                      : isCorrect
                      ? 'Correta'
                      : 'Incorreta',
                ),
                trailing: Text(
                  '${answer?.label ?? '-'} / ${correct?.label ?? '-'}',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
