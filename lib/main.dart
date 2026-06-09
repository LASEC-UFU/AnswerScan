import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/repositories/sheet_reader_repository_impl.dart';
import 'data/services/moodle_service.dart';
import 'data/services/moodle_session_store.dart';
import 'domain/usecases/grade_exam_usecase.dart';
import 'presentation/controllers/correction_controller.dart';
import 'presentation/controllers/moodle_controller.dart';
import 'presentation/pages/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  final cameras = await availableCameras();
  final backCamera = cameras.where((camera) {
    return camera.lensDirection == CameraLensDirection.back;
  }).firstOrNull;

  final repository = SheetReaderRepositoryImpl();
  final useCase = GradeExamUseCase();
  final controller = CorrectionController(
    repository: repository,
    gradeExamUseCase: useCase,
  );
  await controller.loadSavedAnswerKey();

  final moodleController = MoodleController(
    service: MoodleService(),
    store: MoodleSessionStore(),
  );
  await moodleController.loadSavedSession();

  runApp(
    CorretorProvaApp(
      controller: controller,
      moodleController: moodleController,
      camera: backCamera,
    ),
  );
}

class CorretorProvaApp extends StatelessWidget {
  const CorretorProvaApp({
    super.key,
    required this.controller,
    required this.moodleController,
    required this.camera,
  });

  final CorrectionController controller;
  final MoodleController moodleController;
  final CameraDescription? camera;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Corretor de Provas',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D6E5B)),
      ),
      home: HomePage(
        controller: controller,
        moodleController: moodleController,
        camera: camera,
      ),
    );
  }
}
