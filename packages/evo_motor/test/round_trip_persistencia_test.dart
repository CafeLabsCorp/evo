import 'dart:convert';
import 'dart:io';

import 'package:evo_motor/evo_motor.dart';
import 'package:test/test.dart';

/// Round-trip de [Atribuicao], [Parte] e [Evolucao] inteiras — a metade de
/// escrita do codec que faltava (ver dartdoc de `Atribuicao` e
/// `ComandoDoCatalogo`). Cada teste parte de um JSON escrito à mão (no
/// mesmo formato de `evolucao_json.dart`/`exemplo.json`), lê com a função
/// `xDoJson`, escreve de volta com `xParaJson`, e exige o mesmo JSON —
/// prova que "gravar a parte que o usuário editou" já funciona.
void main() {
  group('Round-trip de Atribuicao', () {
    test('sem percussão, sem preenchimento explícito, offset zero', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'movimento': <String, dynamic>{'tipo': 'sentido', 'tempos': 2},
      };
      final Atribuicao atribuicao = atribuicaoDoJson(json);
      expect(atribuicaoParaJson(atribuicao), equals(json));
    });

    test('com percussão, sem preenchimento explícito, offset zero', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'movimento': <String, dynamic>{'tipo': 'baterORitmo', 'tempos': 2},
        'percussao': <String, dynamic>{'membro': 'mao'},
      };
      final Atribuicao atribuicao = atribuicaoDoJson(json);
      expect(atribuicaoParaJson(atribuicao), equals(json));
    });

    test('sem percussão, com preenchimento explícito, offset NÃO-zero', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'movimento': <String, dynamic>{
          'tipo': 'meiaVoltaParado',
          'bateRitmoAoJuntar': false,
        },
        'offsetInicialTiques': 4,
        'preenchimento': <String, dynamic>{'cadencia': 'firme'},
      };
      final Atribuicao atribuicao = atribuicaoDoJson(json);
      expect(atribuicaoParaJson(atribuicao), equals(json));
    });

    test('com percussão E preenchimento explícito, offset NÃO-zero', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'movimento': <String, dynamic>{
          'tipo': 'emFrenteMarche',
          'n': 3,
          'aoTerminar': 'marchando',
          'bateRitmoAoJuntar': false,
        },
        'offsetInicialTiques': 2,
        'preenchimento': <String, dynamic>{'cadencia': 'marchando'},
        'percussao': <String, dynamic>{'membro': 'pernaDireita'},
      };
      final Atribuicao atribuicao = atribuicaoDoJson(json);
      expect(atribuicaoParaJson(atribuicao), equals(json));
    });

    test(
      'Atribuicao construída com `movimento` compilado direto (o atalho '
      'que os testes do motor usam) não serializa — StateError explícito, '
      'nunca um JSON incompleto ou inventado',
      () {
        final Atribuicao atribuicao = Atribuicao(movimento: Catalogo.sentido());
        expect(() => atribuicaoParaJson(atribuicao), throwsStateError);
      },
    );
  });

  group('Round-trip de Parte e de evolução inteira', () {
    test(
      'Parte com múltiplos slots — combina offset, percussão e '
      'preenchimento default (ausente) no mesmo objeto',
      () {
        final Map<String, dynamic> json = <String, dynamic>{
          'ordem': 2.0,
          'nome': 'Parte de teste',
          'atribuicoes': <String, dynamic>{
            '0': <String, dynamic>{
              'movimento': <String, dynamic>{'tipo': 'sentido', 'tempos': 1},
            },
            '1': <String, dynamic>{
              'movimento': <String, dynamic>{
                'tipo': 'alto',
                'bateRitmoAoJuntar': true,
              },
              'percussao': <String, dynamic>{'membro': 'mao'},
            },
            '2': <String, dynamic>{
              'movimento': <String, dynamic>{
                'tipo': 'meiaVoltaParado',
                'bateRitmoAoJuntar': false,
              },
              'offsetInicialTiques': 6,
            },
          },
        };
        final Parte parte = parteDoJson(json);
        expect(parteParaJson(parte), equals(json));
      },
    );

    test('Parte sem `nome` (opcional) round-trippa sem inventar o campo', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'ordem': 0.0,
        'atribuicoes': <String, dynamic>{
          '0': <String, dynamic>{
            'movimento': <String, dynamic>{'tipo': 'descansar', 'tempos': 1},
          },
        },
      };
      final Parte parte = parteDoJson(json);
      expect(parte.nome, isNull);
      expect(parteParaJson(parte), equals(json));
    });

    test('Evolução inteira pequena — nome, estadoInicial, várias partes', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'nome': 'Evolução de teste',
        'estadoInicial': <String, dynamic>{
          'slots': <String, dynamic>{
            '0': <String, dynamic>{
              'linha': 0,
              'coluna': 0,
              'setor': 0,
              'cadencia': 'firme',
            },
          },
        },
        'partes': <dynamic>[
          <String, dynamic>{
            'ordem': 0.0,
            'atribuicoes': <String, dynamic>{
              '0': <String, dynamic>{
                'movimento': <String, dynamic>{
                  'tipo': 'emFrenteMarche',
                  'n': 2,
                  'aoTerminar': 'marchando',
                  'bateRitmoAoJuntar': false,
                },
              },
            },
          },
          <String, dynamic>{
            'ordem': 1.0,
            'nome': 'Segunda parte',
            'atribuicoes': <String, dynamic>{
              '0': <String, dynamic>{
                'movimento': <String, dynamic>{
                  'tipo': 'descansar',
                  'tempos': 2,
                },
              },
            },
          },
        ],
      };
      final Evolucao evolucao = evolucaoDoJson(json);
      expect(evolucaoParaJson(evolucao), equals(json));
    });
  });

  group('exemplo.json — round-trip do arquivo real do app', () {
    test(
      'evolucaoDoJson → evolucaoParaJson produz conteúdo semanticamente '
      'igual ao original (ordem das chaves pode mudar; conteúdo não)',
      () {
        final File arquivo = File('../../app/assets/evolucoes/exemplo.json');
        final Map<String, dynamic> original =
            jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>;

        // `_avisoDadosSinteticos` é um aviso para humanos lendo o arquivo
        // no editor de texto — nunca foi lido por `evolucaoDoJson` (não
        // faz parte do modelo `Evolucao`), então não há de onde ele
        // voltaria no round-trip. Removido do esperado por essa razão, não
        // por ser uma exceção da regra "conteúdo não muda".
        final Map<String, dynamic> esperado = Map<String, dynamic>.of(original)
          ..remove('_avisoDadosSinteticos');

        final Evolucao evolucao = evolucaoDoJson(original);
        final Map<String, dynamic> obtido = evolucaoParaJson(evolucao);

        expect(obtido, equals(esperado));
      },
    );
  });
}
