import 'answer_option.dart';
import 'answer_sheet.dart';

class OmrScanResult {
  const OmrScanResult({
    required this.success,
    required this.status,
    required this.message,
    required this.sheetStatus,
    required this.rawAnswers,
    required this.confidence,
    required this.scores,
    required this.questionDetails,
    required this.markersDetected,
    required this.perspectiveCorrected,
    this.debugImagePath,
    this.error,
  });

  final bool success;
  final String status;
  final String message;
  final String sheetStatus;
  final Map<String, String> rawAnswers;
  final Map<String, double> confidence;
  final Map<String, List<double>> scores;
  final Map<String, OmrQuestionDetail> questionDetails;
  final int markersDetected;
  final bool perspectiveCorrected;
  final String? debugImagePath;
  final String? error;

  AnswerSheet toAnswerSheet() {
    final answers = List<AnswerOption?>.generate(AnswerSheet.totalQuestions, (
      index,
    ) {
      final raw = rawAnswers['${index + 1}'];
      return _parseOption(raw);
    });

    return AnswerSheet(answers);
  }

  bool get requiresReview =>
      reviewQuestionNumbers.isNotEmpty || sheetStatus == 'review_required';

  int get unresolvedCount => reviewQuestionNumbers.length;

  int get resolvedCount =>
      rawAnswers.values.where(_isResolvedAnswerLabel).length;

  double get averageConfidence {
    if (confidence.isEmpty) {
      return 0;
    }

    final total = confidence.values.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    return total / confidence.length;
  }

  List<int> get reviewQuestionNumbers {
    final questions = <int>[];

    for (final entry in rawAnswers.entries) {
      if (!_isResolvedAnswerLabel(entry.value)) {
        final question = int.tryParse(entry.key);
        if (question != null) {
          questions.add(question);
        }
      }
    }

    questions.sort();
    return questions;
  }

  String get summary {
    if (!success) {
      return error ?? message;
    }

    final buffer = StringBuffer();
    for (var question = 1; question <= AnswerSheet.totalQuestions; question++) {
      final answer = rawAnswers['$question'] ?? '?';
      buffer.write('$question:$answer');
      if (question < AnswerSheet.totalQuestions) {
        buffer.write('  ');
      }
    }
    return buffer.toString();
  }

  static OmrScanResult fromMap(Map<Object?, Object?> raw) {
    final success = raw['success'] as bool? ?? false;
    final debug = raw['debug'] as Map<Object?, Object?>? ?? {};
    final questionDetails = _parseQuestionDetails(raw['questoes']);

    if (!success) {
      return OmrScanResult(
        success: false,
        status: raw['status']?.toString() ?? 'ERRO',
        message: raw['mensagem']?.toString() ?? raw['error']?.toString() ?? 'Falha na leitura',
        sheetStatus: raw['sheetStatus']?.toString() ?? 'error',
        rawAnswers: const {},
        confidence: const {},
        scores: const {},
        questionDetails: const {},
        markersDetected: (debug['markersDetected'] as int?) ?? 0,
        perspectiveCorrected: (debug['perspectiveCorrected'] as bool?) ?? false,
        error: raw['error'] as String? ?? 'Unknown error',
      );
    }

    final rawAnswers = questionDetails.isNotEmpty
        ? questionDetails.map(
            (key, value) => MapEntry(key, value.answer),
          )
        : _parseStringMap(raw['answers']);
    final confidence = questionDetails.isNotEmpty
        ? questionDetails.map(
            (key, value) => MapEntry(key, value.confidence),
          )
        : _parseDoubleMap(raw['confidence']);
    final scores = questionDetails.isNotEmpty
        ? questionDetails.map(
            (key, value) => MapEntry(key, value.fillByOption.values.toList()),
          )
        : _parseScoresMap(raw['scores']);

    return OmrScanResult(
      success: true,
      status: raw['status']?.toString() ?? 'OK',
      message: raw['mensagem']?.toString() ?? 'Cartao lido com sucesso',
      sheetStatus: raw['sheetStatus']?.toString() ?? 'ok',
      rawAnswers: rawAnswers,
      confidence: confidence,
      scores: scores,
      questionDetails: questionDetails,
      markersDetected: (debug['markersDetected'] as int?) ?? 0,
      perspectiveCorrected: (debug['perspectiveCorrected'] as bool?) ?? false,
      debugImagePath: raw['debugImagePath'] as String?,
    );
  }

  static Map<String, String> _parseStringMap(Object? raw) {
    if (raw == null) {
      return const {};
    }

    return (raw as Map<Object?, Object?>).map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    );
  }

  static Map<String, double> _parseDoubleMap(Object? raw) {
    if (raw == null) {
      return const {};
    }

    return (raw as Map<Object?, Object?>).map(
      (key, value) =>
          MapEntry(key.toString(), (value as num?)?.toDouble() ?? 0),
    );
  }

  static Map<String, List<double>> _parseScoresMap(Object? raw) {
    if (raw == null) {
      return const {};
    }

    return (raw as Map<Object?, Object?>).map((key, value) {
      final parsedList = (value as List<dynamic>? ?? const [])
          .map((item) => (item as num).toDouble())
          .toList(growable: false);
      return MapEntry(key.toString(), parsedList);
    });
  }

  static Map<String, OmrQuestionDetail> _parseQuestionDetails(Object? raw) {
    if (raw == null) {
      return const {};
    }

    final map = raw as Map<Object?, Object?>;
    return map.map((key, value) {
      final entry = value as Map<Object?, Object?>? ?? const {};
      final fillMap = _parseDoubleMap(entry['preenchimentos']);
      return MapEntry(
        key.toString(),
        OmrQuestionDetail(
          answer: entry['resposta']?.toString() ?? '',
          confidence: (entry['confianca'] as num?)?.toDouble() ?? 0,
          fillByOption: fillMap,
        ),
      );
    });
  }

  static AnswerOption? _parseOption(String? label) {
    switch (label) {
      case 'A':
        return AnswerOption.a;
      case 'B':
        return AnswerOption.b;
      case 'C':
        return AnswerOption.c;
      case 'D':
        return AnswerOption.d;
      case 'E':
        return AnswerOption.e;
      default:
        return null;
    }
  }

  static bool _isResolvedAnswerLabel(String label) {
    switch (label) {
      case 'A':
      case 'B':
      case 'C':
      case 'D':
      case 'E':
        return true;
      default:
        return false;
    }
  }
}

class OmrQuestionDetail {
  const OmrQuestionDetail({
    required this.answer,
    required this.confidence,
    required this.fillByOption,
  });

  final String answer;
  final double confidence;
  final Map<String, double> fillByOption;
}
