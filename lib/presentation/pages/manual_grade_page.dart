import 'package:flutter/material.dart';

import '../../data/models/moodle_models.dart';
import '../controllers/moodle_controller.dart';
import 'moodle_connect_page.dart';

class ManualGradePage extends StatelessWidget {
  const ManualGradePage({super.key, required this.controller});

  final MoodleController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Lançar nota manualmente')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!controller.isFullyConfigured)
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MoodleConnectPage(controller: controller),
                ),
              ),
              icon: const Icon(Icons.school),
              label: const Text('Selecionar curso e atividade'),
            )
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      controller.selectedGradeItem!.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Nota máxima: '
                      '${controller.selectedGradeItem!.gradeMax.toStringAsFixed(2)}',
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                MoodleConnectPage(controller: controller),
                          ),
                        ),
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Alterar curso ou atividade'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownMenu<MoodleStudent>(
                      key: ValueKey(controller.selectedStudent?.id ?? 'empty'),
                      initialSelection: controller.selectedStudent,
                      expandedInsets: EdgeInsets.zero,
                      enableFilter: true,
                      enableSearch: true,
                      requestFocusOnTap: true,
                      label: const Text('Aluno'),
                      hintText: 'Digite para pesquisar',
                      leadingIcon: const Icon(Icons.person_search),
                      onSelected: controller.selectStudent,
                      dropdownMenuEntries: controller.students
                          .map(
                            (student) => DropdownMenuEntry(
                              value: student,
                              label: student.fullname,
                              labelWidget: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(student.fullname),
                                subtitle: student.email.isEmpty
                                    ? null
                                    : Text(student.email),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    if (controller.selectedStudent != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: controller.isSubmitting
                              ? null
                              : () => controller.selectStudent(null),
                          icon: const Icon(Icons.close),
                          label: const Text('Limpar seleção'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!controller.supportsGradebookRead ||
                !controller.supportsDirectGradebookWrite) ...[
              const SizedBox(height: 12),
              Card(
                color: Colors.amber.shade50,
                child: ListTile(
                  leading: Icon(
                    Icons.warning_amber,
                    color: Colors.amber.shade900,
                  ),
                  title: const Text('Serviço Moodle com acesso limitado'),
                  subtitle: Text(
                    'Para carregar e alterar a nota final diretamente, '
                    'conecte usando um Serviço Externo que contenha '
                    '${!controller.supportsGradebookRead ? 'gradereport_user_get_grade_items' : ''}'
                    '${!controller.supportsGradebookRead && !controller.supportsDirectGradebookWrite ? ' e ' : ''}'
                    '${!controller.supportsDirectGradebookWrite ? 'core_grades_update_grades' : ''}.',
                  ),
                ),
              ),
            ],
            if (controller.isLoadingGrade) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (controller.selectedStudent != null &&
                !controller.isLoadingGrade) ...[
              const SizedBox(height: 12),
              if (controller.gradeLoadError != null)
                Card(
                  color: Colors.red.shade50,
                  child: ListTile(
                    leading: Icon(
                      Icons.error_outline,
                      color: Colors.red.shade700,
                    ),
                    title: const Text('Não foi possível carregar a nota atual'),
                    subtitle: Text(controller.gradeLoadError!),
                    trailing: IconButton(
                      onPressed: controller.reloadSelectedStudentGrade,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Tentar novamente',
                    ),
                  ),
                ),
              Card(
                child: ListTile(
                  title: Text(controller.selectedStudent!.fullname),
                  subtitle: Text(
                    _currentGradeText(controller.selectedStudentGrade),
                  ),
                  trailing: FilledButton.icon(
                    onPressed:
                        controller.isSubmitting ||
                            controller.gradeLoadError != null
                        ? null
                        : () => _editGrade(context),
                    icon: const Icon(Icons.edit),
                    label: Text(
                      controller.selectedStudentGrade?.exists == true
                          ? 'Editar nota'
                          : 'Lançar nota',
                    ),
                  ),
                ),
              ),
            ],
            if (controller.lastSubmitMessage != null) ...[
              const SizedBox(height: 12),
              Text(controller.lastSubmitMessage!),
            ],
            if (controller.diagnosticLog.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('Diagnóstico Moodle'),
                  subtitle: const Text(
                    'Detalhes das buscas, envios e respostas recebidas',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: SelectableText(
                        controller.diagnosticLog.reversed.join('\n\n'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    ),
  );

  String _currentGradeText(MoodleStudentGrade? grade) {
    final value = grade?.value ?? 0;
    final source = switch (grade?.source) {
      MoodleGradeSource.manual => 'manual',
      MoodleGradeSource.automatic => 'automática',
      _ => 'origem não identificada',
    };
    return 'Nota atual: ${value.toStringAsFixed(2)} ($source)';
  }

  Future<void> _editGrade(BuildContext context) async {
    final item = controller.selectedGradeItem!;
    final current = controller.selectedStudentGrade?.value ?? 0;
    final text = TextEditingController(
      text: current.toStringAsFixed(2).replaceFirst('.', ','),
    );
    String? error;
    final grade = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          void save() {
            final value = double.tryParse(
              text.text.trim().replaceAll(',', '.'),
            );
            if (value == null || value < 0 || value > item.gradeMax) {
              setState(() {
                error =
                    'Informe uma nota entre 0 e ${item.gradeMax.toStringAsFixed(2)}.';
              });
              return;
            }
            Navigator.pop(dialogContext, value);
          }

          return AlertDialog(
            title: const Text('Editar nota manual'),
            content: TextField(
              controller: text,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Nota',
                suffixText: '/ ${item.gradeMax.toStringAsFixed(2)}',
                errorText: error,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => save(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(onPressed: save, child: const Text('Salvar')),
            ],
          );
        },
      ),
    ).whenComplete(text.dispose);
    if (grade != null) {
      await controller.submitManualGrade(grade);
    }
  }
}
