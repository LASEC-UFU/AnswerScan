import 'package:answer_scan/domain/entities/omr_scan_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseia payload estruturado de questoes', () {
    final result = OmrScanResult.fromMap({
      'success': true,
      'status': 'OK',
      'mensagem': 'Cartao lido com sucesso',
      'sheetStatus': 'ok',
      'questoes': {
        '1': {
          'resposta': 'C',
          'confianca': 0.98,
          'preenchimentos': {
            'A': 0.05,
            'B': 0.04,
            'C': 0.91,
            'D': 0.03,
            'E': 0.04,
          },
        },
        '2': {
          'resposta': 'EM_BRANCO',
          'confianca': 0.90,
          'preenchimentos': {
            'A': 0.01,
            'B': 0.02,
            'C': 0.03,
            'D': 0.02,
            'E': 0.01,
          },
        },
      },
      'debug': {'markersDetected': 4, 'perspectiveCorrected': true},
    });

    expect(result.success, isTrue);
    expect(result.status, 'OK');
    expect(result.message, 'Cartao lido com sucesso');
    expect(result.rawAnswers['1'], 'C');
    expect(result.rawAnswers['2'], 'EM_BRANCO');
    expect(result.confidence['1'], closeTo(0.98, 0.0001));
    expect(
      result.questionDetails['1']?.fillByOption['C'],
      closeTo(0.91, 0.0001),
    );
    expect(result.scores['1'], orderedEquals([0.05, 0.04, 0.91, 0.03, 0.04]));
    expect(result.requiresReview, isTrue);
  });

  test('questao com multiplas marcacoes e nula para correcao', () {
    final result = OmrScanResult.fromMap({
      'success': true,
      'status': 'REVISAO_MANUAL',
      'mensagem': 'Leitura concluida com itens para revisao manual',
      'sheetStatus': 'review_required',
      'questoes': {
        '1': {
          'resposta': 'MULTIPLA',
          'confianca': 0.90,
          'preenchimentos': {
            'A': 0.92,
            'B': 0.08,
            'C': 0.79,
            'D': 0.04,
            'E': 0.05,
          },
        },
      },
      'debug': {'markersDetected': 4, 'perspectiveCorrected': true},
    });

    expect(result.rawAnswers['1'], 'MULTIPLA');
    expect(result.toAnswerSheet().answers.first, isNull);
    expect(result.requiresReview, isTrue);
  });
}
