import 'package:flutter/foundation.dart';

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

  bool get isFullyConfigured =>
      session != null && selectedCourse != null && selectedGradeItem != null;
  bool get isReadyToSubmit => isFullyConfigured && selectedStudent != null;

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
    selectedCourse = course;
    selectedGradeItem = null;
    selectedStudent = null;
    gradeItems = [];
    notifyListeners();
    await _store.saveCourse(course);
    await _loadAssignGradeColumns();
  }

  Future<void> selectGradeItem(MoodleGradeItem item) async {
    selectedGradeItem = item;
    selectedStudent = null;
    notifyListeners();
    await _store.saveGradeItem(item);
    await _loadStudents();
  }

  /// Goes back to course selection (keeps session).
  void resetCourseSelection() {
    selectedCourse = null;
    selectedGradeItem = null;
    selectedStudent = null;
    gradeItems = [];
    notifyListeners();
  }

  // ── Students ───────────────────────────────────────────────────────────────

  Future<void> reloadStudents() => _loadStudents();

  void selectStudent(MoodleStudent? student) {
    selectedStudent = student;
    lastSubmitMessage = null;
    notifyListeners();
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
  }) async {
    final s = session;
    final item = selectedGradeItem;
    if (s == null || item == null) return false;

    isSubmitting = true;
    lastSubmitMessage = null;
    notifyListeners();

    try {
      final grade =
          gradeOverride ?? (correctAnswers / totalQuestions) * item.gradeMax;
      if (grade < 0 || grade > item.gradeMax) {
        lastSubmitMessage =
            'A nota deve estar entre 0 e ${item.gradeMax.toStringAsFixed(2)}.';
        return false;
      }
      await _service.submitGrade(
        baseUrl: s.baseUrl,
        token: s.token,
        item: item,
        studentId: studentId,
        grade: grade,
      );
      lastSubmitMessage = 'Nota enviada com sucesso!';
      return true;
    } on MoodleException catch (e) {
      lastSubmitMessage = 'Erro: ${e.message}';
      return false;
    } catch (e) {
      lastSubmitMessage = 'Erro ao enviar nota: $e';
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  // ── Disconnect ─────────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    await _store.clear();
    session = null;
    selectedCourse = null;
    selectedGradeItem = null;
    courses = [];
    gradeItems = [];
    students = [];
    selectedStudent = null;
    connectionState = MoodleConnectionState.disconnected;
    notifyListeners();
  }
}
