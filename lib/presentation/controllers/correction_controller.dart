import 'package:flutter/foundation.dart';

import '../../domain/entities/sheet_scan_session.dart';
import '../../domain/repositories/sheet_reader_repository.dart';
import '../../domain/usecases/grade_exam_usecase.dart';

class CorrectionController extends ChangeNotifier {
  CorrectionController({
    required SheetReaderRepository repository,
    required GradeExamUseCase gradeExamUseCase,
  }) : _repository = repository,
       _gradeExamUseCase = gradeExamUseCase;

  final SheetReaderRepository _repository;
  final GradeExamUseCase _gradeExamUseCase;

  SheetScanSession? _answerKeyScan;
  SheetScanSession? _studentSheetScan;
  GradeResult? _result;
  String? _errorMessage;
  String? _statusMessage;
  bool _isBusy = false;

  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  String? get statusMessage => _statusMessage;
  GradeResult? get result => _result;
  SheetScanSession? get answerKeyScan => _answerKeyScan;
  SheetScanSession? get studentSheetScan => _studentSheetScan;

  bool get canGrade => _answerKeyScan != null && _studentSheetScan != null;

  String get answerKeySummary => _sheetSummary(_answerKeyScan);
  String get studentSummary => _sheetSummary(_studentSheetScan);

  Future<void> loadAnswerKey(String imagePath, {bool debug = false}) async {
    await _loadSheet(
      imagePath: imagePath,
      debug: debug,
      onSuccess: (session) {
        _answerKeyScan = session;
        _result = null;
      },
    );
  }

  Future<void> loadStudentSheet(String imagePath, {bool debug = false}) async {
    await _loadSheet(
      imagePath: imagePath,
      debug: debug,
      onSuccess: (session) {
        _studentSheetScan = session;
        _result = null;
      },
    );
  }

  GradeResult? grade() {
    _errorMessage = null;

    if (!canGrade) {
      _errorMessage = 'Leia o gabarito e a folha do aluno antes de corrigir.';
      notifyListeners();
      return null;
    }

    _result = _gradeExamUseCase.execute(
      answerKey: _answerKeyScan!.answerSheet,
      studentSheet: _studentSheetScan!.answerSheet,
    );
    _statusMessage =
        'Correcao concluida: ${_result!.correctAnswers} de '
        '${_result!.totalQuestions} questoes corretas.';

    notifyListeners();
    return _result;
  }

  Future<void> _loadSheet({
    required String imagePath,
    required bool debug,
    required void Function(SheetScanSession session) onSuccess,
  }) async {
    _isBusy = true;
    _errorMessage = null;
    _statusMessage = null;
    notifyListeners();

    try {
      final scanResult = await _repository.scanSheet(imagePath, debug: debug);
      if (!scanResult.success) {
        _errorMessage = scanResult.error ?? 'Falha na leitura.';
        return;
      }

      final session = SheetScanSession(
        imagePath: imagePath,
        result: scanResult,
      );
      onSuccess(session);
      _statusMessage = _buildStatusMessage(session);
    } catch (error) {
      _errorMessage = 'Falha na leitura: ${_normalizeError(error)}';
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  String _sheetSummary(SheetScanSession? session) {
    if (session == null) {
      return 'Nenhuma leitura.';
    }

    final buffer = StringBuffer();
    for (var question = 0; question < 20; question++) {
      final answer = session.result.rawAnswers['${question + 1}'] ?? '-';
      buffer.write('${question + 1}:$answer');
      if (question < 19) {
        buffer.write('  ');
      }
    }

    return buffer.toString();
  }

  String _buildStatusMessage(SheetScanSession session) {
    if (session.result.requiresReview) {
      return 'Leitura concluida com revisao manual em '
          '${session.result.unresolvedCount} questoes.';
    }

    return 'Leitura concluida com ${session.result.resolvedCount} respostas '
        'claras e confianca media de '
        '${(session.result.averageConfidence * 100).toStringAsFixed(0)}%.';
  }

  String _normalizeError(Object error) =>
      error.toString().replaceFirst('OmrScanException: ', '');
}
