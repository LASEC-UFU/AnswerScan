import 'answer_sheet.dart';
import 'omr_scan_result.dart';

class SheetScanSession {
  const SheetScanSession({required this.imagePath, required this.result});

  final String imagePath;
  final OmrScanResult result;

  AnswerSheet get answerSheet => result.toAnswerSheet();

  AnswerSheet answerSheetWithQuestionCount(int questionCount) =>
      result.toAnswerSheet(questionCount: questionCount);
}
