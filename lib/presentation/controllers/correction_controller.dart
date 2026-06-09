import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/omr_scan_result.dart';
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
  String? _answerKeyMessage;
  String? _answerKeyError;
  String? _studentMessage;
  String? _studentError;
  bool _answerKeyValidated = false;
  bool _isBusy = false;

  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  String? get statusMessage => _statusMessage;
  GradeResult? get result => _result;
  SheetScanSession? get answerKeyScan => _answerKeyScan;
  SheetScanSession? get studentSheetScan => _studentSheetScan;
  String? get answerKeyMessage => _answerKeyMessage;
  String? get answerKeyError => _answerKeyError;
  String? get studentMessage => _studentMessage;
  String? get studentError => _studentError;
  bool get answerKeyValidated => _answerKeyValidated;

  bool get canGrade =>
      _answerKeyScan != null &&
      _studentSheetScan != null &&
      _answerKeyValidated;

  String get answerKeySummary => _sheetSummary(_answerKeyScan);
  String get studentSummary => _sheetSummary(_studentSheetScan);

  Future<void> loadAnswerKey(String imagePath, {bool debug = false}) async {
    await _loadSheet(
      imagePath: imagePath,
      debug: debug,
      onSuccess: (session) {
        _answerKeyScan = session;
        _answerKeyValidated = false;
        _answerKeyMessage = _buildStatusMessage(session);
        _answerKeyError = null;
        _result = null;
      },
      onError: (message) => _answerKeyError = message,
    );
  }

  Future<void> loadStudentSheet(String imagePath, {bool debug = false}) async {
    await _loadSheet(
      imagePath: imagePath,
      debug: debug,
      onSuccess: (session) {
        _studentSheetScan = session;
        _studentMessage = _buildStatusMessage(session);
        _studentError = null;
        _result = null;
      },
      onError: (message) => _studentError = message,
    );
  }

  void updateAnswerKey(int question, String answer) {
    final session = _answerKeyScan;
    if (session == null) return;
    _answerKeyScan = SheetScanSession(
      imagePath: session.imagePath,
      result: session.result.withAnswer(question, answer),
    );
    _answerKeyValidated = false;
    _answerKeyMessage = 'Gabarito alterado. Valide e salve antes de corrigir.';
    notifyListeners();
  }

  Future<void> validateAnswerKey() async {
    if (_answerKeyScan == null) return;
    if (_answerKeyScan!.result.unresolvedCount > 0) {
      _answerKeyValidated = false;
      _answerKeyError =
          'Revise todas as questões em branco, múltiplas ou ambíguas antes de salvar.';
      notifyListeners();
      return;
    }
    _answerKeyValidated = true;
    _answerKeyError = null;
    _answerKeyMessage = 'Gabarito validado e salvo para correção.';
    final prefs = await SharedPreferences.getInstance();
    final session = _answerKeyScan!;
    await prefs.setString('answer_key_source_path', session.imagePath);
    await prefs.setString(
      'answer_key_corrected_path',
      session.result.correctedImagePath ?? '',
    );
    await prefs.setStringList(
      'answer_key_answers',
      List.generate(
        20,
        (index) => session.result.rawAnswers['${index + 1}'] ?? 'EM_BRANCO',
      ),
    );
    notifyListeners();
  }

  Future<void> loadSavedAnswerKey() async {
    final prefs = await SharedPreferences.getInstance();
    final answers = prefs.getStringList('answer_key_answers');
    final sourcePath = prefs.getString('answer_key_source_path');
    final correctedPath = prefs.getString('answer_key_corrected_path');
    if (answers == null || answers.length != 20 || sourcePath == null) return;
    final rawAnswers = {
      for (var index = 0; index < answers.length; index++)
        '${index + 1}': answers[index],
    };
    _answerKeyScan = SheetScanSession(
      imagePath: sourcePath,
      result: OmrScanResult(
        success: true,
        status: 'OK',
        message: 'Gabarito salvo',
        sheetStatus: 'ok',
        rawAnswers: rawAnswers,
        confidence: {for (var index = 1; index <= 20; index++) '$index': 1},
        scores: const {},
        questionDetails: const {},
        markersDetected: 4,
        perspectiveCorrected: true,
        correctedImagePath: correctedPath == null || correctedPath.isEmpty
            ? null
            : correctedPath,
      ),
    );
    _answerKeyValidated = true;
    _answerKeyMessage = 'Gabarito salvo carregado.';
    notifyListeners();
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
    _studentMessage = _statusMessage;

    notifyListeners();
    return _result;
  }

  Future<void> _loadSheet({
    required String imagePath,
    required bool debug,
    required void Function(SheetScanSession session) onSuccess,
    required void Function(String message) onError,
  }) async {
    _isBusy = true;
    _errorMessage = null;
    _statusMessage = null;
    notifyListeners();

    try {
      final scanResult = await _repository.scanSheet(imagePath, debug: debug);
      if (!scanResult.success) {
        _errorMessage = scanResult.error ?? 'Falha na leitura.';
        onError(_errorMessage!);
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
      onError(_errorMessage!);
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
