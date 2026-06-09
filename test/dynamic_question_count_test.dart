import 'package:answer_scan/domain/entities/answer_option.dart';
import 'package:answer_scan/domain/entities/answer_sheet.dart';
import 'package:answer_scan/domain/entities/omr_scan_result.dart';
import 'package:answer_scan/domain/usecases/grade_exam_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('brancos finais definem quantidade real da prova', () {
    final result = _resultWith({
      for (var question = 1; question <= 10; question++) '$question': 'A',
    });

    expect(result.lastResolvedQuestion, 10);
    expect(result.answerKeyInvalidQuestions, isEmpty);
  });

  test('lacuna entre respostas preenchidas invalida gabarito', () {
    final result = _resultWith({
      '1': 'A',
      '2': 'B',
      '3': 'EM_BRANCO',
      '4': 'D',
    });

    expect(result.lastResolvedQuestion, 4);
    expect(result.answerKeyInvalidQuestions, [3]);
  });

  test('marcacao invalida apos ultima resposta preenchida nao e ignorada', () {
    final result = _resultWith({'1': 'A', '2': 'B', '3': 'MULTIPLA'});

    expect(result.lastResolvedQuestion, 2);
    expect(result.answerKeyInvalidQuestions, [3]);
  });

  test('correcao ignora posicoes posteriores ao total do gabarito', () {
    final keyAnswers = List<AnswerOption?>.filled(
      AnswerSheet.maxQuestions,
      null,
    );
    final studentAnswers = List<AnswerOption?>.filled(
      AnswerSheet.maxQuestions,
      AnswerOption.b,
    );
    for (var index = 0; index < 10; index++) {
      keyAnswers[index] = AnswerOption.a;
      studentAnswers[index] = AnswerOption.a;
    }

    final result = GradeExamUseCase().execute(
      answerKey: AnswerSheet(keyAnswers, questionCount: 10),
      studentSheet: AnswerSheet(studentAnswers),
    );

    expect(result.totalQuestions, 10);
    expect(result.correctAnswers, 10);
  });
}

OmrScanResult _resultWith(Map<String, String> answers) {
  return OmrScanResult(
    success: true,
    status: 'OK',
    message: 'ok',
    sheetStatus: 'ok',
    rawAnswers: {
      for (var question = 1; question <= AnswerSheet.maxQuestions; question++)
        '$question': answers['$question'] ?? 'EM_BRANCO',
    },
    confidence: const {},
    scores: const {},
    questionDetails: const {},
    markersDetected: 4,
    perspectiveCorrected: true,
  );
}
