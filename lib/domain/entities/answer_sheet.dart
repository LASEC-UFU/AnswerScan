import 'answer_option.dart';

class AnswerSheet {
  AnswerSheet(List<AnswerOption?> answers, {int? questionCount})
    : _answers = List<AnswerOption?>.unmodifiable(answers),
      questionCount = questionCount ?? _inferQuestionCount(answers) {
    if (_answers.length != maxQuestions) {
      throw ArgumentError(
        'A folha precisa ter exatamente $maxQuestions respostas.',
      );
    }
    if (this.questionCount < 1 || this.questionCount > maxQuestions) {
      throw ArgumentError('Quantidade de questoes invalida.');
    }
  }

  static const int maxQuestions = 20;

  final List<AnswerOption?> _answers;
  final int questionCount;

  List<AnswerOption?> get answers => _answers;

  static int _inferQuestionCount(List<AnswerOption?> answers) {
    for (var index = answers.length - 1; index >= 0; index--) {
      if (answers[index] != null) return index + 1;
    }
    return maxQuestions;
  }
}
