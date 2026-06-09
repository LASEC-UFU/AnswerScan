import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/moodle_models.dart';

class MoodleException implements Exception {
  const MoodleException(this.message, {this.errorCode});
  final String message;

  /// Moodle machine-readable error code, e.g. 'accessdenied', 'nopermissions'.
  final String? errorCode;

  @override
  String toString() => message;
}

class MoodleService {
  // ──────────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────────

  /// Authenticates and returns (token, userId, fullname, availableFunctions).
  /// [serviceName] must match an External Service configured in Moodle.
  Future<(String token, int userId, String fullname, Set<String> fns)> login({
    required String baseUrl,
    required String username,
    required String password,
    String serviceName = 'moodle_mobile_app',
  }) async {
    final resp = await http.post(
      _uri(baseUrl, 'login/token.php'),
      body: {
        'username': username,
        'password': password,
        'service': serviceName,
      },
    );
    _checkStatus(resp);
    final data = _decode(resp.body) as Map<String, dynamic>;
    if (data.containsKey('error')) {
      throw MoodleException(
        (data['error'] as String?) ?? 'Usuário ou senha inválidos.',
        errorCode: data['errorcode'] as String?,
      );
    }
    final token = data['token'] as String;

    final info =
        await _ws(baseUrl, token, 'core_webservice_get_site_info')
            as Map<String, dynamic>;

    // Extract the list of WS functions enabled in this external service.
    final fns = ((info['functions'] as List?) ?? [])
        .map((f) => (f as Map)['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toSet();

    return (
      token,
      info['userid'] as int,
      (info['fullname'] as String?) ?? '',
      fns,
    );
  }

  Future<List<MoodleCourse>> getCourses({
    required String baseUrl,
    required String token,
    required int userId,
  }) async {
    final data =
        await _ws(baseUrl, token, 'core_enrol_get_users_courses', {
              'userid': '$userId',
            })
            as List<dynamic>;
    return data
        .map((e) => MoodleCourse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Returns assignments configured as grade columns (no student submission).
  ///
  /// Uses [mod_assign_get_assignments] and filters by ALL criteria:
  ///   • nosubmissions = 1  OR  assignsubmission_file/onlinetext disabled
  ///   • grade > 0  (numeric, not a scale)
  ///   • markingworkflow = 0  AND  markingallocation = 0
  Future<List<MoodleGradeItem>> getAssignGradeColumns({
    required String baseUrl,
    required String token,
    required int courseId,
  }) async {
    final data =
        await _ws(baseUrl, token, 'mod_assign_get_assignments', {
              'courseids[0]': '$courseId',
            })
            as Map<String, dynamic>;

    final courses = (data['courses'] as List?) ?? [];
    if (courses.isEmpty) return [];
    final assignments = ((courses[0] as Map)['assignments'] as List?) ?? [];

    return assignments
        .map((a) => a as Map<String, dynamic>)
        .where(_isGradeColumn)
        .map(MoodleGradeItem.fromAssignment)
        .toList();
  }

  /// Returns true when the assignment is a pure grade column:
  /// no student interaction, only the teacher writes a grade via the API.
  bool _isGradeColumn(Map<String, dynamic> a) {
    // Numeric grade required (negative value = scale, not supported)
    final grade = (a['grade'] as num?)?.toDouble() ?? 0;
    if (grade <= 0) return false;

    // No complex marking workflow
    if ((a['markingworkflow'] as int?) == 1) return false;
    if ((a['markingallocation'] as int?) == 1) return false;

    // Explicitly configured as "no submissions" → grade column
    if ((a['nosubmissions'] as int?) == 1) return true;

    // Otherwise pass only when BOTH submission plugins are disabled
    final configs = (a['configs'] as List?) ?? [];
    bool subEnabled(String plugin) => configs.any(
      (c) =>
          (c as Map)['subtype'] == 'assignsubmission' &&
          c['plugin'] == plugin &&
          c['name'] == 'enabled' &&
          c['value'] == '1',
    );
    return grade > 0 || (!subEnabled('file') && !subEnabled('onlinetext'));
  }

  Future<List<MoodleStudent>> getStudents({
    required String baseUrl,
    required String token,
    required int courseId,
  }) async {
    final data =
        await _ws(baseUrl, token, 'core_enrol_get_enrolled_users', {
              'courseid': '$courseId',
            })
            as List<dynamic>;
    final users = data.map((e) => e as Map<String, dynamic>).toList();
    final hasRoleInformation = users.any(
      (user) => ((user['roles'] as List?) ?? const []).isNotEmpty,
    );
    final candidates = hasRoleInformation
        ? users.where((user) {
            final roles = (user['roles'] as List?) ?? const [];
            return roles.any((role) {
              final shortname = (role as Map)['shortname']?.toString() ?? '';
              return shortname == 'student';
            });
          })
        : users;
    return candidates.map(MoodleStudent.fromJson).toList();
  }

  Future<double?> getStudentGrade({
    required String baseUrl,
    required String token,
    required MoodleGradeItem item,
    required int studentId,
  }) async {
    final data =
        await _ws(baseUrl, token, 'mod_assign_get_grades', {
              'assignmentids[0]': '${item.id}',
            })
            as Map<String, dynamic>;
    return parseStudentGradeResponse(data, studentId);
  }

  Future<double?> getStudentGradebookGrade({
    required String baseUrl,
    required String token,
    required int courseId,
    required MoodleGradeItem item,
    required int studentId,
  }) async {
    final data =
        await _ws(baseUrl, token, 'gradereport_user_get_grade_items', {
              'courseid': '$courseId',
              'userid': '$studentId',
            })
            as Map<String, dynamic>;
    return parseGradebookGradeResponse(data, item);
  }

  @visibleForTesting
  double? parseGradebookGradeResponse(
    Map<String, dynamic> data,
    MoodleGradeItem item,
  ) {
    final userGrades = (data['usergrades'] as List?) ?? const [];
    if (userGrades.isEmpty) return null;
    final gradeItems =
        ((userGrades.first as Map)['gradeitems'] as List?) ?? const [];
    for (final raw in gradeItems) {
      final gradeItem = raw as Map;
      final module = gradeItem['itemmodule']?.toString();
      final instance = _asInt(gradeItem['iteminstance']);
      if (module == 'assign' && instance == item.id) {
        return _nonNegativeDouble(gradeItem['graderaw']);
      }
    }
    return null;
  }

  @visibleForTesting
  double? parseStudentGradeResponse(Map<String, dynamic> data, int studentId) {
    final assignments = (data['assignments'] as List?) ?? const [];
    if (assignments.isEmpty) return null;
    final grades = ((assignments.first as Map)['grades'] as List?) ?? const [];
    for (final raw in grades) {
      final grade = raw as Map;
      if (_asInt(grade['userid']) == studentId) {
        final value = grade['grade'];
        final parsed = value is num
            ? value.toDouble()
            : double.tryParse(value?.toString() ?? '');
        return parsed != null && parsed >= 0 ? parsed : null;
      }
    }
    return null;
  }

  /// Submits a grade for an assignment-as-grade-column via [mod_assign_save_grade].
  ///
  /// Only call this for items returned by [getAssignGradeColumns] (itemType='assign').
  /// [item.id] must be the assignment INSTANCE ID.
  Future<dynamic> submitGrade({
    required String baseUrl,
    required String token,
    required MoodleGradeItem item,
    required int studentId,
    required double grade,
  }) async {
    return _ws(baseUrl, token, 'mod_assign_save_grade', {
      'assignmentid': '${item.id}',
      'userid': '$studentId',
      'grade': grade.toStringAsFixed(2),
      'attemptnumber': '-1',
      'addattempt': '0',
      'workflowstate': 'released',
      'applytoall': '0',
    });
  }

  Future<dynamic> updateGradebookGrade({
    required String baseUrl,
    required String token,
    required int courseId,
    required MoodleGradeItem item,
    required int studentId,
    required double grade,
  }) {
    return _ws(baseUrl, token, 'core_grades_update_grades', {
      'source': 'answer_scan',
      'courseid': '$courseId',
      'component': 'mod_assign',
      'activityid': '${item.id}',
      'itemnumber': '${item.itemNumber}',
      'grades[0][studentid]': '$studentId',
      'grades[0][grade]': grade.toStringAsFixed(2),
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────────────

  // ──────────────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────────────

  Uri _uri(String baseUrl, String path) {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse('$base$path');
  }

  void _checkStatus(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw MoodleException('Erro HTTP ${resp.statusCode}');
    }
  }

  dynamic _decode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      throw const MoodleException('Resposta inválida do servidor.');
    }
  }

  Future<dynamic> _ws(
    String baseUrl,
    String token,
    String function, [
    Map<String, String> extra = const {},
  ]) async {
    _log('Enviando $function: ${jsonEncode(extra)}');
    final resp = await http.post(
      _uri(baseUrl, 'webservice/rest/server.php'),
      body: {
        'wstoken': token,
        'moodlewsrestformat': 'json',
        'wsfunction': function,
        ...extra,
      },
    );
    _log(
      'Resposta $function HTTP ${resp.statusCode}: '
      '${_abbreviate(resp.body)}',
    );
    _checkStatus(resp);
    final decoded = _decode(resp.body);
    if (decoded is Map && decoded.containsKey('exception')) {
      final errorCode = decoded['errorcode'] as String?;
      final message =
          (decoded['message'] as String?) ?? decoded['exception'].toString();
      throw MoodleException(
        _friendlyMessage(message, errorCode),
        errorCode: errorCode,
      );
    }
    return decoded;
  }

  int? _asInt(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');

  double? _nonNegativeDouble(dynamic value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  String _abbreviate(String value) =>
      value.length <= 1200 ? value : '${value.substring(0, 1200)}...';

  void _log(String message) {
    debugPrint('[MoodleService] $message');
  }

  /// Turns Moodle machine error codes into actionable Portuguese messages.
  String _friendlyMessage(String original, String? errorCode) {
    switch (errorCode) {
      case 'accessdenied':
      case 'webserviceaccessexception':
        return 'Função não autorizada no serviço Moodle.\n'
            'Adicione gradereport_user_get_grade_items e '
            'core_grades_update_grades ao seu '
            'Serviço Externo em:\n'
            'Admin → Servidor → Web services → Serviços externos\n'
            'Use o token deste serviço ao conectar.';
      case 'nopermissions':
        return 'Sem permissão para editar notas neste curso.\n'
            'Verifique se você tem o papel de Professor com edição.';
      case 'invalidrecordunknown':
        return 'Aluno ou item de avaliação não encontrado no Moodle.\n'
            'Verifique se o e-mail do aluno está cadastrado e se o nome do '
            'item de nota é idêntico ao exibido no Moodle.';
      case 'servicenotavailable':
        return 'Serviço Moodle não encontrado.\n'
            'Verifique o endereço do servidor nas configurações.';
      case 'invalidfunction':
        return 'A função necessária para ler ou salvar notas não '
            'existe neste Moodle ou não foi adicionada ao Serviço Externo.\n'
            'Verifique com o administrador do Moodle.';
      default:
        return errorCode != null ? '$original [$errorCode]' : original;
    }
  }
}
