import '../entities/answer_sheet.dart';

class GradeExamUseCase {
  GradeResult execute({
    required AnswerSheet answerKey,
    required AnswerSheet studentSheet,
  }) {
    var correctAnswers = 0;

    for (var index = 0; index < answerKey.questionCount; index++) {
      final key = answerKey.answers[index];
      final student = studentSheet.answers[index];

      if (key != null && student != null && key == student) {
        correctAnswers++;
      }
    }

    return GradeResult(
      totalQuestions: answerKey.questionCount,
      correctAnswers: correctAnswers,
    );
  }
}

class GradeResult {
  const GradeResult({
    required this.totalQuestions,
    required this.correctAnswers,
  });

  final int totalQuestions;
  final int correctAnswers;
}
