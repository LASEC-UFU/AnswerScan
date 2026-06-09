import 'package:answer_scan/data/services/moodle_service.dart';
import 'package:answer_scan/data/models/moodle_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = MoodleService();

  test('carrega nota quando Moodle retorna userid como texto', () {
    final grade = service.parseStudentGradeResponse({
      'assignments': [
        {
          'grades': [
            {'userid': '42', 'grade': '8.50'},
          ],
        },
      ],
    }, 42);

    expect(grade, 8.5);
  });

  test('considera nota negativa do Moodle como ainda não lançada', () {
    final grade = service.parseStudentGradeResponse({
      'assignments': [
        {
          'grades': [
            {'userid': 42, 'grade': '-1.00000'},
          ],
        },
      ],
    }, 42);

    expect(grade, isNull);
  });

  test('não utiliza nota pertencente a outro aluno', () {
    final grade = service.parseStudentGradeResponse({
      'assignments': [
        {
          'grades': [
            {'userid': '7', 'grade': '9.00'},
          ],
        },
      ],
    }, 42);

    expect(grade, isNull);
  });

  test('carrega nota final da tarefa no livro de notas', () {
    const item = MoodleGradeItem(
      id: 82535,
      name: 'Prova',
      itemType: 'assign',
      itemModule: 'assign',
      itemNumber: 0,
      gradeMax: 10,
    );

    final grade = service.parseGradebookGradeResponse({
      'usergrades': [
        {
          'gradeitems': [
            {
              'itemmodule': 'assign',
              'iteminstance': '82535',
              'graderaw': '7.50',
            },
          ],
        },
      ],
    }, item);

    expect(grade, 7.5);
  });
}
