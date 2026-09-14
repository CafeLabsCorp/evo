import 'package:evo_motor/evo_motor.dart';
import 'package:test/test.dart';

void main() {
  group('Fronteira de serialização: quartos nunca atravessam para JSON', () {
    test('estado alinhado a célula serializa normalmente', () {
      const EstadoPessoa estado = EstadoPessoa(
        x: 3 * unidadesPorCelula,
        y: 2 * unidadesPorCelula,
        dir: 2,
        cad: Cadencia.firme,
      );
      final Map<String, dynamic> json = estadoPessoaParaJson(estado);
      expect(json, <String, dynamic>{
        'linha': 2,
        'coluna': 3,
        'setor': 2,
        'cadencia': 'firme',
      });
    });

    test(
      'estado em posição intermediária (meio passo diagonal) FALHA ao serializar',
      () {
        // 1 tique de setor 1 (NE) a partir de (0,0): (1,-1) quartos — nem
        // perto de uma fronteira de célula.
        const EstadoPessoa intermediario = EstadoPessoa(
          x: 1,
          y: -1,
          dir: 1,
          cad: Cadencia.marchando,
        );
        expect(() => estadoPessoaParaJson(intermediario), throwsStateError);
      },
    );

    test(
      'estado em meio-célula diagonal (1 tempo inteiro, setor ímpar) também FALHA',
      () {
        // 1 tempo (2 tiques) de setor 1: (2,-2) quartos = meia célula em
        // cada eixo — geometricamente real (é o "meio quadrado" descrito na
        // spec), mas não é uma célula INTEIRA, então não serializa.
        const EstadoPessoa meiaCelula = EstadoPessoa(
          x: 2,
          y: -2,
          dir: 1,
          cad: Cadencia.marchando,
        );
        expect(() => estadoPessoaParaJson(meiaCelula), throwsStateError);
      },
    );

    test('round-trip JSON de uma EstadoFormacao inteira preserva os dados', () {
      final EstadoFormacao formacao = EstadoFormacao(<int, EstadoPessoa>{
        0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.firme),
        1: EstadoPessoa(
          x: unidadesPorCelula,
          y: 0,
          dir: 4,
          cad: Cadencia.marchando,
        ),
      });
      final Map<String, dynamic> json = estadoFormacaoParaJson(formacao);
      final EstadoFormacao devolta = estadoFormacaoDoJson(json);
      expect(devolta, formacao);
    });

    test(
      'resultado de uma simulação real (estado final de uma marcha) não serializa até completar tempo inteiro',
      () {
        const EstadoPessoa inicial = EstadoPessoa(
          x: 0,
          y: 0,
          dir: 1,
          cad: Cadencia.marchando,
        );
        final Movimento m = Catalogo.emFrenteMarche(
          1,
          aoTerminar: AoTerminarMarche.marchando,
        );
        final ResultadoSegmentos r = executarSegmentos(
          inicial,
          m.segmentosPara(Cadencia.marchando),
          cadenciaFinal: Cadencia.marchando,
        );
        // Depois de 1 tempo diagonal completo, a pessoa está em meia-célula
        // por eixo — um estado real e válido de simulação, mas que não deve
        // (e não consegue) virar {linha, coluna} no JSON.
        expect(() => estadoPessoaParaJson(r.estadoFinal), throwsStateError);
      },
    );

    test('Cadencia (de)serializa nos dois sentidos para todos os valores', () {
      for (final Cadencia c in Cadencia.values) {
        expect(cadenciaDoJson(cadenciaParaJson(c)), c);
      }
    });
  });

  group(
    'Propriedade 10 — round-trip reconstrói o estado interno em quartos '
    'corretamente (não só "quartos não vazam")',
    () {
      test(
        'EstadoPessoa: {linha, coluna, setor, cadencia} reconstrói x/y em '
        'quartos exatamente (literal, não comparado só por igualdade)',
        () {
          final Map<String, dynamic> json = <String, dynamic>{
            'linha': 3,
            'coluna': -2,
            'setor': 5,
            'cadencia': 'marcandoPasso',
          };
          final EstadoPessoa estado = estadoPessoaDoJson(json);
          // Literal: linha 3 × 4 quartos/célula = 12; coluna -2 × 4 = -8.
          expect(estado.y, 12);
          expect(estado.x, -8);
          expect(estado.dir, 5);
          expect(estado.cad, Cadencia.marcandoPasso);
        },
      );

      test(
        'EstadoFormacao: round-trip reconstrói cada slot em quartos, '
        'chave por chave',
        () {
          final Map<String, dynamic> json = <String, dynamic>{
            'slots': <String, dynamic>{
              '0': <String, dynamic>{
                'linha': 1,
                'coluna': 1,
                'setor': 0,
                'cadencia': 'firme',
              },
              '7': <String, dynamic>{
                'linha': -1,
                'coluna': 0,
                'setor': 4,
                'cadencia': 'descansar',
              },
            },
          };
          final EstadoFormacao formacao = estadoFormacaoDoJson(json);
          expect(formacao.slots.toSet(), <int>{0, 7});
          expect((formacao[0].x, formacao[0].y), (4, 4));
          expect(formacao[0].dir, 0);
          expect(formacao[0].cad, Cadencia.firme);
          expect((formacao[7].x, formacao[7].y), (0, -4));
          expect(formacao[7].dir, 4);
          expect(formacao[7].cad, Cadencia.descansar);
        },
      );
    },
  );

  group(
    'Propriedade 10 — rejeição de JSON malformado com diagnóstico, nunca '
    'aceitação silenciosa',
    () {
      test('setor fora de 0..7 (negativo) lança, não normaliza silenciosamente', () {
        final Map<String, dynamic> json = <String, dynamic>{
          'linha': 0,
          'coluna': 0,
          'setor': -1,
          'cadencia': 'firme',
        };
        expect(
          () => estadoPessoaDoJson(json),
          throwsA(isA<FormatException>()),
        );
      });

      test('setor fora de 0..7 (>= 8) lança, não faz módulo silencioso', () {
        final Map<String, dynamic> json = <String, dynamic>{
          'linha': 0,
          'coluna': 0,
          'setor': 8,
          'cadencia': 'firme',
        };
        expect(
          () => estadoPessoaDoJson(json),
          throwsA(isA<FormatException>()),
        );
      });

      test('cadência desconhecida lança com o valor ofensor na mensagem', () {
        final Map<String, dynamic> json = <String, dynamic>{
          'linha': 0,
          'coluna': 0,
          'setor': 0,
          'cadencia': 'sentado', // não existe no enum Cadencia.
        };
        expect(
          () => estadoPessoaDoJson(json),
          throwsA(
            isA<FormatException>().having(
              (FormatException e) => e.message,
              'message',
              contains('sentado'),
            ),
          ),
        );
      });

      test(
        'movimento de tipo desconhecido no catálogo lança, nunca cai '
        'silenciosamente num movimento default',
        () {
          expect(
            () => movimentoDoJson(<String, dynamic>{'tipo': 'voarParaLua'}),
            throwsA(isA<FormatException>()),
          );
        },
      );
    },
  );

  test(
    '"marcarPasso" no JSON repassa bateRitmoAoJuntar (regressão: esse campo '
    'era ignorado nesse case antes da correção de catálogo v2)',
    () {
      final Movimento comBatida = movimentoDoJson(<String, dynamic>{
        'tipo': 'marcarPasso',
        'tempos': 1,
        'bateRitmoAoJuntar': true,
      });
      final Movimento semBatida = movimentoDoJson(<String, dynamic>{
        'tipo': 'marcarPasso',
        'tempos': 1,
      });
      const EstadoPessoa marchando = EstadoPessoa(
        x: 0,
        y: 0,
        dir: 0,
        cad: Cadencia.marchando,
      );
      final ResultadoSegmentos rComBatida = executarSegmentos(
        marchando,
        comBatida.segmentosPara(Cadencia.marchando),
        cadenciaFinal: comBatida.cadenciaResultante(Cadencia.marchando),
      );
      final ResultadoSegmentos rSemBatida = executarSegmentos(
        marchando,
        semBatida.segmentosPara(Cadencia.marchando),
        cadenciaFinal: semBatida.cadenciaResultante(Cadencia.marchando),
      );
      expect(rComBatida.batidas.length, rSemBatida.batidas.length + 1);
    },
  );
}
