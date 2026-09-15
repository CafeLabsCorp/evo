import 'package:evo_motor/evo_motor.dart';
import 'package:test/test.dart';

/// Testes do "buraco fechado": antes de [ComandoDoCatalogo] existir, um
/// [Movimento] não tinha volta para JSON (guardava `nome` como rótulo
/// humano e `segmentos` como closure — nenhum dos dois é um discriminador
/// serializável). Este arquivo é o teste que garante que o buraco não
/// reabre: para cada um dos 16 movimentos do catálogo, com cada combinação
/// relevante de parâmetro, serializar → desserializar → serializar produz
/// JSON byte-idêntico (não só "objetos equivalentes").
void _verificaRoundTripTotal(ComandoDoCatalogo comando) {
  final Map<String, dynamic> j1 = comando.paraJson();
  final ComandoDoCatalogo devolta = ComandoDoCatalogo.doJson(j1);
  final Map<String, dynamic> j2 = devolta.paraJson();
  expect(
    j2,
    equals(j1),
    reason: 'round-trip não fechou para $comando — j1=$j1, j2=$j2',
  );
  // Também prova que o comando lido de volta ainda materializa (não ficou
  // "meio" reconstruído) — sem isso, um round-trip de JSON poderia fechar
  // sintaticamente e mesmo assim produzir um comando inutilizável.
  expect(devolta.materializar(), isA<Movimento>());
}

void main() {
  group('Round-trip total do catálogo — os 16 movimentos, exaustivo', () {
    const List<String> tiposComTempos = <String>[
      'sentido',
      'descansar',
      'baterORitmo',
    ];
    const List<int> temposVariados = <int>[1, 2, 5];

    for (final String tipo in tiposComTempos) {
      for (final int tempos in temposVariados) {
        test('$tipo, tempos=$tempos', () {
          _verificaRoundTripTotal(ComandoDoCatalogo(tipo: tipo, tempos: tempos));
        });
      }
    }

    for (final int tempos in temposVariados) {
      for (final bool bate in <bool>[true, false]) {
        test('marcarPasso, tempos=$tempos, bateRitmoAoJuntar=$bate', () {
          _verificaRoundTripTotal(
            ComandoDoCatalogo(
              tipo: 'marcarPasso',
              tempos: tempos,
              bateRitmoAoJuntar: bate,
            ),
          );
        });
      }
    }

    const List<String> tiposComSoBatida = <String>[
      'direitaVolverParado',
      'esquerdaVolverParado',
      'meiaVoltaParado',
      'oitavaDireitaParado',
      'oitavaEsquerdaParado',
      'alto',
      'direitaVolverMarcha',
      'esquerdaVolverMarcha',
      'meiaVoltaMarcha',
      'oitavaDireitaMarcha',
      'oitavaEsquerdaMarcha',
    ];
    for (final String tipo in tiposComSoBatida) {
      for (final bool bate in <bool>[true, false]) {
        test('$tipo, bateRitmoAoJuntar=$bate', () {
          _verificaRoundTripTotal(
            ComandoDoCatalogo(tipo: tipo, bateRitmoAoJuntar: bate),
          );
        });
      }
    }

    for (final AoTerminarMarche aoTerminar in AoTerminarMarche.values) {
      for (final bool bate in <bool>[true, false]) {
        for (final int n in <int>[1, 4, 8]) {
          test(
            'emFrenteMarche, n=$n, aoTerminar=$aoTerminar, '
            'bateRitmoAoJuntar=$bate',
            () {
              _verificaRoundTripTotal(
                ComandoDoCatalogo(
                  tipo: 'emFrenteMarche',
                  n: n,
                  aoTerminar: aoTerminar,
                  bateRitmoAoJuntar: bate,
                ),
              );
            },
          );
        }
      }
    }

    test(
      'os 16 tipos acima cobrem exatamente o catálogo (nenhum esquecido, '
      'nenhum a mais)',
      () {
        final Set<String> cobertos = <String>{
          ...tiposComTempos,
          'marcarPasso',
          ...tiposComSoBatida,
          'emFrenteMarche',
        };
        expect(cobertos, hasLength(16));
      },
    );
  });

  group('Tipo desconhecido nunca cai em default silencioso', () {
    test('ComandoDoCatalogo.doJson(...).materializar() lança FormatException', () {
      final ComandoDoCatalogo comando = ComandoDoCatalogo.doJson(
        <String, dynamic>{'tipo': 'voarParaLua'},
      );
      expect(() => comando.materializar(), throwsA(isA<FormatException>()));
    });

    test('ComandoDoCatalogo.paraJson() também lança para tipo desconhecido', () {
      const ComandoDoCatalogo comando = ComandoDoCatalogo(tipo: 'voarParaLua');
      expect(() => comando.paraJson(), throwsA(isA<FormatException>()));
    });

    test('aoTerminar desconhecido em doJson lança FormatException', () {
      expect(
        () => ComandoDoCatalogo.doJson(<String, dynamic>{
          'tipo': 'emFrenteMarche',
          'n': 1,
          'aoTerminar': 'pulando',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'movimentoDoJson (a função antiga, agora um atalho) continua '
      'lançando para tipo desconhecido — regressão',
      () {
        expect(
          () => movimentoDoJson(<String, dynamic>{'tipo': 'voarParaLua'}),
          throwsA(isA<FormatException>()),
        );
      },
    );
  });
}
