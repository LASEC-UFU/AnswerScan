import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/moodle_models.dart';
import '../../data/services/moodle_service.dart';
import '../../data/services/moodle_session_store.dart';

enum MoodleConnectionState { disconnected, connecting, connected }

class MoodleController extends ChangeNotifier {
  MoodleController({
    required MoodleService service,
    required MoodleSessionStore store,
  }) : _service = service,
       _store = store;

  final MoodleService _service;
  final MoodleSessionStore _store;

  // ── State ──────────────────────────────────────────────────────────────────
  MoodleConnectionState connectionState = MoodleConnectionState.disconnected;
  MoodleSession? session;
  MoodleCourse? selectedCourse;
  MoodleGradeItem? selectedGradeItem;
  MoodleStudent? selectedStudent;
  List<MoodleCourse> courses = [];
  List<MoodleGradeItem> gradeItems = [];
  List<MoodleStudent> students = [];
  bool isLoading = false;
  String? errorMessage;
  bool isSubmitting = false;
  String? lastSubmitMessage;
  MoodleStudentGrade? selectedStudentGrade;
  bool isLoadingGrade = false;
  String? gradeLoadError;
  final List<String> diagnosticLog = [];
  int _gradeLoadRevision = 0;

  bool get isFullyConfigured =>
      session != null && selectedCourse != null && selectedGradeItem != null;
  bool get isReadyToSubmit => isFullyConfigured && selectedStudent != null;
  bool get supportsGradebookRead =>
      _hasFunction('gradereport_user_get_grade_items');
  bool get supportsDirectGradebookWrite =>
      _hasFunction('core_grades_update_grades');

  // ── Init ───────────────────────────────────────────────────────────────────

  /// Restores session from SharedPreferences and resumes loading as needed.
  Future<void> loadSavedSession() async {
    session = await _store.loadSession();
    if (session == null) {
      notifyListeners();
      return;
    }
    selectedCourse = await _store.loadCourse();
    selectedGradeItem = await _store.loadGradeItem();
    connectionState = MoodleConnectionState.connected;
    notifyListeners();

    if (selectedCourse != null && selectedGradeItem != null) {
      _loadStudents();
    } else if (selectedCourse != null) {
      _loadAssignGradeColumns();
    } else {
      loadCourses();
    }
  }

  // ── Connect ────────────────────────────────────────────────────────────────

  Future<void> connect({
    required String baseUrl,
    required String username,
    required String password,
    String serviceName = 'moodle_mobile_app',
  }) async {
    isLoading = true;
    errorMessage = null;
    connectionState = MoodleConnectionState.connecting;
    notifyListeners();

    try {
      final (token, userId, fullname, fns) = await _service.login(
        baseUrl: baseUrl,
        username: username,
        password: password,
        serviceName: serviceName,
      );
      session = MoodleSession(
        baseUrl: baseUrl,
        token: token,
        userId: userId,
        fullname: fullname,
        serviceName: serviceName,
        availableFunctions: fns,
      );
      await _store.saveSession(session!);
      courses = await _service.getCourses(
        baseUrl: baseUrl,
        token: token,
        userId: userId,
      );
      connectionState = MoodleConnectionState.connected;
    } on MoodleException catch (e) {
      errorMessage = e.message;
      connectionState = MoodleConnectionState.disconnected;
    } catch (e) {
      errorMessage = 'Erro de conexão: $e';
      connectionState = MoodleConnectionState.disconnected;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadCourses() async {
    final s = session;
    if (s == null) return;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      courses = await _service.getCourses(
        baseUrl: s.baseUrl,
        token: s.token,
        userId: s.userId,
      );
    } on MoodleException catch (e) {
      errorMessage = e.message;
    } catch (e) {
      errorMessage = 'Erro ao carregar cursos: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // ── Course & grade-item selection ──────────────────────────────────────────

  Future<void> selectCourse(MoodleCourse course) async {
    _gradeLoadRevision++;
    selectedCourse = course;
    selectedGradeItem = null;
    selectedStudent = null;
    selectedStudentGrade = null;
    gradeItems = [];
    notifyListeners();
    await _store.saveCourse(course);
    await _loadAssignGradeColumns();
  }

  Future<void> selectGradeItem(MoodleGradeItem item) async {
    _gradeLoadRevision++;
    selectedGradeItem = item;
    selectedStudent = null;
    selectedStudentGrade = null;
    notifyListeners();
    await _store.saveGradeItem(item);
    await _loadStudents();
  }

  /// Goes back to course selection (keeps session).
  void resetCourseSelection() {
    _gradeLoadRevision++;
    selectedCourse = null;
    selectedGradeItem = null;
    selectedStudent = null;
    selectedStudentGrade = null;
    gradeItems = [];
    notifyListeners();
  }

  // ── Students ───────────────────────────────────────────────────────────────

  Future<void> reloadStudents() => _loadStudents();

  void selectStudent(MoodleStudent? student) {
    _gradeLoadRevision++;
    selectedStudent = student;
    selectedStudentGrade = null;
    gradeLoadError = null;
    isLoadingGrade = false;
    lastSubmitMessage = null;
    _diagnostic(
      student == null
          ? 'Seleção de aluno limpa.'
          : 'Aluno selecionado: ${student.fullname} (ID ${student.id}).',
    );
    notifyListeners();
    if (student != null) {
      _loadSelectedStudentGrade();
    }
  }

  Future<void> reloadSelectedStudentGrade() => _loadSelectedStudentGrade();

  Future<void> _loadSelectedStudentGrade() async {
    final s = session;
    final item = selectedGradeItem;
    final student = selectedStudent;
    if (s == null || item == null || student == null) return;
    final revision = _gradeLoadRevision;
    isLoadingGrade = true;
    gradeLoadError = null;
    _diagnostic(
      'Buscando nota atual: atividade ${item.id}, aluno ${student.id}.',
    );
    notifyListeners();
    try {
      final value = await _getCurrentGrade(s, item, student.id);
      final prefs = await SharedPreferences.getInstance();
      if (revision != _gradeLoadRevision ||
          selectedStudent?.id != student.id ||
          selectedGradeItem?.id != item.id) {
        return;
      }
      final sourceName = prefs.getString(_gradeSourceKey(item.id, student.id));
      selectedStudentGrade = MoodleStudentGrade(
        value: value,
        source: MoodleGradeSource.values.firstWhere(
          (source) => source.name == sourceName,
          orElse: () => MoodleGradeSource.unknown,
        ),
      );
      _diagnostic(
        value == null
            ? 'Moodle não possui nota para o aluno ${student.id}.'
            : 'Nota atual recebida do Moodle: ${value.toStringAsFixed(2)}.',
      );
    } on MoodleException catch (e) {
      if (revision != _gradeLoadRevision) return;
      gradeLoadError = e.message;
      selectedStudentGrade = const MoodleStudentGrade(
        value: null,
        source: MoodleGradeSource.unknown,
      );
      _diagnostic('Erro ao buscar nota: ${e.message}');
    } catch (e) {
      if (revision != _gradeLoadRevision) return;
      gradeLoadError = 'Erro ao buscar nota atual: $e';
      selectedStudentGrade = const MoodleStudentGrade(
        value: null,
        source: MoodleGradeSource.unknown,
      );
      _diagnostic(gradeLoadError!);
    } finally {
      if (revision == _gradeLoadRevision) {
        isLoadingGrade = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadStudents() async {
    final s = session;
    final c = selectedCourse;
    if (s == null || c == null) return;
    isLoading = true;
    notifyListeners();
    try {
      students = await _service.getStudents(
        baseUrl: s.baseUrl,
        token: s.token,
        courseId: c.id,
      );
    } catch (_) {
      // Non-fatal: the user can retry from the dialog.
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadAssignGradeColumns() async {
    final s = session;
    final c = selectedCourse;
    if (s == null || c == null) return;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      gradeItems = await _service.getAssignGradeColumns(
        baseUrl: s.baseUrl,
        token: s.token,
        courseId: c.id,
      );
    } on MoodleException catch (e) {
      errorMessage = e.message;
    } catch (e) {
      errorMessage = 'Erro ao carregar colunas de nota: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // ── Submit grade ───────────────────────────────────────────────────────────

  /// Normalises [correctAnswers]/[totalQuestions] to the item's gradeMax
  /// and posts the result to Moodle.
  Future<bool> submitGrade({
    required int studentId,
    required int correctAnswers,
    required int totalQuestions,
    double? gradeOverride,
    MoodleGradeSource source = MoodleGradeSource.automatic,
  }) async {
    final s = session;
    final item = selectedGradeItem;
    if (s == null || item == null) return false;

    isSubmitting = true;
    lastSubmitMessage = null;
    notifyListeners();

    try {
      if (!item.isSubmittable) {
        lastSubmitMessage =
            'Este item não é uma Tarefa compatível com lançamento de nota.';
        _diagnostic(lastSubmitMessage!);
        return false;
      }
      final grade =
          gradeOverride ?? (correctAnswers / totalQuestions) * item.gradeMax;
      if (grade < 0 || grade > item.gradeMax) {
        lastSubmitMessage =
            'A nota deve estar entre 0 e ${item.gradeMax.toStringAsFixed(2)}.';
        return false;
      }
      final timestamp = DateTime.now().toIso8601String();
      final sourceLabel = source == MoodleGradeSource.manual
          ? 'manual'
          : 'automatica';
      final useDirectGradebook = _hasFunction('core_grades_update_grades');
      final method = useDirectGradebook
          ? 'core_grades_update_grades'
          : 'mod_assign_save_grade';
      _requireAssignmentFunction(method);
      _diagnostic(
        'Enviando nota $sourceLabel ${grade.toStringAsFixed(2)}: '
        'atividade ${item.id}, aluno $studentId, método $method.',
      );
      final response = useDirectGradebook
          ? await _service.updateGradebookGrade(
              baseUrl: s.baseUrl,
              token: s.token,
              courseId: selectedCourse!.id,
              item: item,
              studentId: studentId,
              grade: grade,
            )
          : await _service.submitGrade(
              baseUrl: s.baseUrl,
              token: s.token,
              item: item,
              studentId: studentId,
              grade: grade,
            );
      _diagnostic('Resposta de $method: ${jsonEncode(response)}');

      final savedGrade = await _getCurrentGrade(s, item, studentId);
      _diagnostic(
        'Verificação após envio: '
        '${savedGrade?.toStringAsFixed(2) ?? 'sem nota retornada'}.',
      );
      if (savedGrade == null || (savedGrade - grade).abs() > 0.011) {
        lastSubmitMessage =
            'O Moodle recebeu a solicitação, mas a nota não foi confirmada. '
            'Para lançamento direto, habilite core_grades_update_grades e '
            'gradereport_user_get_grade_items no Serviço Externo.';
        return false;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_gradeSourceKey(item.id, studentId), source.name);
      final auditLog = prefs.getStringList('grade_audit_log') ?? <String>[];
      auditLog.add(
        jsonEncode({
          'timestamp': timestamp,
          'source': source.name,
          'teacher': s.fullname,
          'courseId': selectedCourse?.id,
          'itemId': item.id,
          'itemName': item.name,
          'studentId': studentId,
          'grade': grade,
        }),
      );
      final trimmedLog = auditLog.length > 500
          ? auditLog.sublist(auditLog.length - 500)
          : auditLog;
      await prefs.setStringList('grade_audit_log', trimmedLog);
      selectedStudentGrade = MoodleStudentGrade(
        value: savedGrade,
        source: source,
      );
      lastSubmitMessage = source == MoodleGradeSource.manual
          ? 'Nota manual salva com sucesso!'
          : 'Nota automática enviada com sucesso!';
      return true;
    } on MoodleException catch (e) {
      lastSubmitMessage = 'Erro: ${e.message}';
      _diagnostic(lastSubmitMessage!);
      return false;
    } catch (e) {
      lastSubmitMessage = 'Erro ao enviar nota: $e';
      _diagnostic(lastSubmitMessage!);
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<bool> submitManualGrade(double grade) {
    final student = selectedStudent;
    if (student == null) return Future.value(false);
    return submitGrade(
      studentId: student.id,
      correctAnswers: 0,
      totalQuestions: 1,
      gradeOverride: grade,
      source: MoodleGradeSource.manual,
    );
  }

  String _gradeSourceKey(int itemId, int studentId) =>
      'grade_source_${selectedCourse?.id ?? 0}_${itemId}_$studentId';

  void _requireAssignmentFunction(String function) {
    final functions = session?.availableFunctions ?? const <String>{};
    if (functions.isNotEmpty && !functions.contains(function)) {
      throw MoodleException(
        'O serviço externo conectado não disponibiliza $function. '
        'Adicione essa função ao serviço no Moodle e conecte novamente.',
        errorCode: 'invalidfunction',
      );
    }
  }

  bool _hasFunction(String function) =>
      session?.availableFunctions.contains(function) ?? false;

  Future<double?> _getCurrentGrade(
    MoodleSession session,
    MoodleGradeItem item,
    int studentId,
  ) async {
    if (_hasFunction('gradereport_user_get_grade_items')) {
      _diagnostic(
        'Consultando livro de notas: curso ${selectedCourse!.id}, '
        'atividade ${item.id}, aluno $studentId.',
      );
      return _service.getStudentGradebookGrade(
        baseUrl: session.baseUrl,
        token: session.token,
        courseId: selectedCourse!.id,
        item: item,
        studentId: studentId,
      );
    }
    _requireAssignmentFunction('mod_assign_get_grades');
    _diagnostic(
      'gradereport_user_get_grade_items indisponível; '
      'consultando mod_assign_get_grades.',
    );
    return _service.getStudentGrade(
      baseUrl: session.baseUrl,
      token: session.token,
      item: item,
      studentId: studentId,
    );
  }

  void _diagnostic(String message) {
    final entry = '${DateTime.now().toIso8601String()}  $message';
    diagnosticLog.add(entry);
    if (diagnosticLog.length > 100) diagnosticLog.removeAt(0);
    debugPrint('[MoodleController] $entry');
  }

  // ── Disconnect ─────────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    _gradeLoadRevision++;
    await _store.clear();
    session = null;
    selectedCourse = null;
    selectedGradeItem = null;
    courses = [];
    gradeItems = [];
    students = [];
    selectedStudent = null;
    selectedStudentGrade = null;
    connectionState = MoodleConnectionState.disconnected;
    notifyListeners();
  }
}
