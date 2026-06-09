import 'package:flutter_test/flutter_test.dart';

import 'package:answer_scan/data/services/moodle_service.dart';
import 'package:answer_scan/data/services/moodle_session_store.dart';
import 'package:answer_scan/domain/entities/omr_scan_result.dart';
import 'package:answer_scan/domain/repositories/sheet_reader_repository.dart';
import 'package:answer_scan/domain/usecases/grade_exam_usecase.dart';
import 'package:answer_scan/main.dart';
import 'package:answer_scan/presentation/controllers/correction_controller.dart';
import 'package:answer_scan/presentation/controllers/moodle_controller.dart';

void main() {
  testWidgets('exibe titulo principal', (WidgetTester tester) async {
    final controller = CorrectionController(
      repository: _FakeSheetReaderRepository(),
      gradeExamUseCase: GradeExamUseCase(),
    );
    final moodleController = MoodleController(
      service: MoodleService(),
      store: MoodleSessionStore(),
    );

    await tester.pumpWidget(
      CorretorProvaApp(
        controller: controller,
        moodleController: moodleController,
        camera: null,
      ),
    );

    expect(find.text('Corretor de Provas OMR'), findsOneWidget);
  });
}

class _FakeSheetReaderRepository implements SheetReaderRepository {
  @override
  Future<OmrScanResult> scanSheet(
    String imagePath, {
    bool debug = false,
  }) async {
    return const OmrScanResult(
      success: false,
      status: 'ERRO',
      message: 'unused',
      sheetStatus: 'idle',
      rawAnswers: {},
      confidence: {},
      scores: {},
      questionDetails: {},
      markersDetected: 0,
      perspectiveCorrected: false,
      error: 'unused',
    );
  }
}
