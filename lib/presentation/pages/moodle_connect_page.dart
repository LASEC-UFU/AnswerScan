import 'package:flutter/material.dart';

import '../../data/models/moodle_models.dart';
import '../controllers/moodle_controller.dart';

class MoodleConnectPage extends StatefulWidget {
  const MoodleConnectPage({super.key, required this.controller});

  final MoodleController controller;

  @override
  State<MoodleConnectPage> createState() => _MoodleConnectPageState();
}

class _MoodleConnectPageState extends State<MoodleConnectPage> {
  final _urlCtrl = TextEditingController(text: 'https://moodle.ufu.br');
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _serviceCtrl = TextEditingController(text: 'moodle_mobile_app');
  bool _obscure = true;
  bool _showAdvanced = false;

  MoodleController get ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    final s = ctrl.session;
    if (s != null) {
      _urlCtrl.text = s.baseUrl;
      _serviceCtrl.text = s.serviceName;
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _serviceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Conexão Moodle'),
          actions: [
            if (ctrl.session != null)
              TextButton.icon(
                onPressed: () async {
                  await ctrl.disconnect();
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.logout),
                label: const Text('Desconectar'),
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    // Not yet connected — show login form.
    if (ctrl.connectionState == MoodleConnectionState.disconnected) {
      return _LoginForm(
        urlCtrl: _urlCtrl,
        userCtrl: _userCtrl,
        passCtrl: _passCtrl,
        serviceCtrl: _serviceCtrl,
        obscure: _obscure,
        showAdvanced: _showAdvanced,
        onToggle: () => setState(() => _obscure = !_obscure),
        onToggleAdvanced: () => setState(() => _showAdvanced = !_showAdvanced),
        onConnect: _connect,
        isLoading: ctrl.isLoading,
        error: ctrl.errorMessage,
      );
    }

    // Connected, no course selected — show course list.
    if (ctrl.selectedCourse == null) {
      return _CourseList(
        connectedAs: ctrl.session?.fullname ?? '',
        courses: ctrl.courses,
        isLoading: ctrl.isLoading,
        onSelect: ctrl.selectCourse,
        onReload: ctrl.loadCourses,
      );
    }

    // Course selected, no grade item — show grade item list.
    if (ctrl.selectedGradeItem == null) {
      return _GradeItemList(
        course: ctrl.selectedCourse!,
        items: ctrl.gradeItems,
        isLoading: ctrl.isLoading,
        error: ctrl.errorMessage,
        onSelect: (item) async {
          await ctrl.selectGradeItem(item);
          if (mounted) Navigator.of(context).pop();
        },
        onBack: ctrl.resetCourseSelection,
      );
    }

    // Fully configured — show summary.
    return _ConfiguredSummary(ctrl: ctrl);
  }

  void _connect() => ctrl.connect(
    baseUrl: _urlCtrl.text.trim(),
    username: _userCtrl.text.trim(),
    password: _passCtrl.text,
    serviceName: _serviceCtrl.text.trim().isEmpty
        ? 'moodle_mobile_app'
        : _serviceCtrl.text.trim(),
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// Login form
// ──────────────────────────────────────────────────────────────────────────────

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.urlCtrl,
    required this.userCtrl,
    required this.passCtrl,
    required this.serviceCtrl,
    required this.obscure,
    required this.showAdvanced,
    required this.onToggle,
    required this.onToggleAdvanced,
    required this.onConnect,
    required this.isLoading,
    this.error,
  });

  final TextEditingController urlCtrl;
  final TextEditingController userCtrl;
  final TextEditingController passCtrl;
  final TextEditingController serviceCtrl;
  final bool obscure;
  final bool showAdvanced;
  final VoidCallback onToggle;
  final VoidCallback onToggleAdvanced;
  final VoidCallback onConnect;
  final bool isLoading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const Icon(Icons.school, size: 64, color: Colors.teal),
        const SizedBox(height: 24),
        TextField(
          controller: urlCtrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'URL do Moodle',
            hintText: 'https://moodle.suainstituicao.edu.br',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: userCtrl,
          decoration: const InputDecoration(
            labelText: 'Usuário',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: passCtrl,
          obscureText: obscure,
          decoration: InputDecoration(
            labelText: 'Senha',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: onToggle,
            ),
          ),
        ),
        const SizedBox(height: 4),
        // ── Advanced settings ──────────────────────────────────────────
        TextButton.icon(
          onPressed: onToggleAdvanced,
          icon: Icon(showAdvanced ? Icons.expand_less : Icons.expand_more),
          label: const Text('Configurações avançadas'),
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.zero,
          ),
        ),
        if (showAdvanced) ...[
          TextField(
            controller: serviceCtrl,
            decoration: const InputDecoration(
              labelText: 'Nome do serviço Moodle',
              hintText: 'moodle_mobile_app',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.settings_ethernet),
              helperText:
                  'Para ler e lançar notas diretamente: crie um Serviço '
                  'Externo\ncom gradereport_user_get_grade_items e '
                  'core_grades_update_grades.',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (error != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              error!,
              style: TextStyle(color: Colors.red.shade800, fontSize: 13),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: isLoading ? null : onConnect,
          icon: isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.login),
          label: const Text('Conectar'),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Course list
// ──────────────────────────────────────────────────────────────────────────────

class _CourseList extends StatelessWidget {
  const _CourseList({
    required this.connectedAs,
    required this.courses,
    required this.isLoading,
    required this.onSelect,
    required this.onReload,
  });

  final String connectedAs;
  final List<MoodleCourse> courses;
  final bool isLoading;
  final void Function(MoodleCourse) onSelect;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Conectado como: $connectedAs',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Selecione o curso:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              onPressed: onReload,
              icon: const Icon(Icons.refresh),
              tooltip: 'Recarregar',
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (isLoading) const Center(child: CircularProgressIndicator()),
        if (!isLoading && courses.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Nenhum curso encontrado. Toque em atualizar.'),
          ),
        for (final c in courses)
          Card(
            child: ListTile(
              leading: const Icon(Icons.book_outlined),
              title: Text(c.fullname),
              subtitle: Text(c.shortname),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onSelect(c),
            ),
          ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Grade item list
// ──────────────────────────────────────────────────────────────────────────────

class _GradeItemList extends StatelessWidget {
  const _GradeItemList({
    required this.course,
    required this.items,
    required this.isLoading,
    required this.onSelect,
    required this.onBack,
    this.error,
  });

  final MoodleCourse course;
  final List<MoodleGradeItem> items;
  final bool isLoading;
  final void Function(MoodleGradeItem) onSelect;
  final VoidCallback onBack;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
            Expanded(
              child: Text(
                course.fullname,
                style: Theme.of(context).textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Text(
          'Selecione o item de nota:',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (isLoading) const Center(child: CircularProgressIndicator()),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(error!, style: const TextStyle(color: Colors.red)),
          ),
        if (!isLoading && items.isEmpty && error == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Nenhum item de nota disponível neste curso.\n'
              'Verifique se você tem permissão de professor.',
            ),
          ),
        for (final item in items)
          Card(
            child: ListTile(
              leading: const Icon(Icons.grade_outlined),
              title: Text(item.name),
              subtitle: Text(
                '${item.displayType}  •  máx ${item.gradeMax.toStringAsFixed(0)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onSelect(item),
            ),
          ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Configured summary
// ──────────────────────────────────────────────────────────────────────────────

class _ConfiguredSummary extends StatelessWidget {
  const _ConfiguredSummary({required this.ctrl});

  final MoodleController ctrl;

  @override
  Widget build(BuildContext context) {
    final session = ctrl.session!;
    final course = ctrl.selectedCourse!;
    final item = ctrl.selectedGradeItem!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const Icon(Icons.check_circle, size: 56, color: Colors.green),
        const SizedBox(height: 8),
        const Text(
          'Moodle configurado',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        _InfoRow('Servidor', session.baseUrl),
        _InfoRow('Usuário', session.fullname),
        _InfoRow('Curso', course.fullname),
        _InfoRow(
          'Item de nota',
          '${item.name}  (máx ${item.gradeMax.toStringAsFixed(0)})',
        ),
        _InfoRow('Alunos carregados', '${ctrl.students.length}'),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () {
            ctrl.resetCourseSelection();
            ctrl.loadCourses();
          },
          icon: const Icon(Icons.edit),
          label: const Text('Alterar configuração'),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
