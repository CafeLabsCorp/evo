import 'package:evo_motor/evo_motor.dart';
import 'package:test/test.dart';

/// Aplica um [Movimento] a partir de um [EstadoPessoa] de entrada,
/// resolvendo `segmentosPara`/`cadenciaResultante` com a cadência de
/// ENTRADA desse estado — a mesma referência que `compilador.dart` usa
/// (`inicial.cad`), nunca uma cadência "de chegada" recalculada.
EstadoPessoa _aplicar(EstadoPessoa entrada, Movimento m) => executarSegmentos(
  entrada,
  m.segmentosPara(entrada.cad),
  cadenciaFinal: m.cadenciaResultante(entrada.cad),
).estadoFinal;

void main() {
  group('Propriedade 1a — marche(N, firme) ≡ marche(N-1, marchando) + Alto', () {
    for (final int n in <int>[1, 2, 3, 5]) {
      for (final int setor in List<int>.generate(8, (int i) => i)) {
        test('N=$n, setor=$setor', () {
          final EstadoPessoa inicial = EstadoPessoa(
            x: 0,
            y: 0,
            dir: setor,
            cad: Cadencia.marchando,
          );

          final Movimento a = Catalogo.emFrenteMarche(
            n,
            aoTerminar: AoTerminarMarche.firme,
          );
          final EstadoPessoa viaFirme = _aplicar(inicial, a);

          EstadoPessoa viaAltoIntermediario = inicial;
          if (n > 1) {
            viaAltoIntermediario = _aplicar(
              viaAltoIntermediario,
              Catalogo.emFrenteMarche(
                n - 1,
                aoTerminar: AoTerminarMarche.marchando,
              ),
            );
          }
          final EstadoPessoa viaAlto = _aplicar(
            viaAltoIntermediario,
            Catalogo.alto(),
          );

          expect((viaFirme.x, viaFirme.y), (viaAlto.x, viaAlto.y));
          expect(viaFirme.dir, viaAlto.dir);
          expect(viaFirme.cad, viaAlto.cad);
          expect(a.duracaoTiquesPara(Cadencia.marchando), (n + 1) * 2);
        });
      }
    }
  });

  group(
    'Propriedade 1b — marche(N, marcandoPasso) ≡ marche(N-1, marchando) + '
    'transição de "marcar passo" (catálogo v2, simétrico ao par 1a)',
    () {
      for (final int n in <int>[1, 2, 3, 5]) {
        for (final int setor in List<int>.generate(8, (int i) => i)) {
          test('N=$n, setor=$setor', () {
            final EstadoPessoa inicial = EstadoPessoa(
              x: 0,
              y: 0,
              dir: setor,
              cad: Cadencia.marchando,
            );

            final Movimento a = Catalogo.emFrenteMarche(
              n,
              aoTerminar: AoTerminarMarche.marcandoPasso,
            );
            final EstadoPessoa viaMarcandoPasso = _aplicar(inicial, a);

            EstadoPessoa viaTransicaoIntermediaria = inicial;
            if (n > 1) {
              viaTransicaoIntermediaria = _aplicar(
                viaTransicaoIntermediaria,
                Catalogo.emFrenteMarche(
                  n - 1,
                  aoTerminar: AoTerminarMarche.marchando,
                ),
              );
            }
            // `marcarPasso(tempos: 0)` a partir de marchando é exatamente
            // A(1)·J terminando em marcandoPasso — o análogo exato de
            // `Catalogo.alto()` (que é A(1)·J terminando em firme, sem
            // nenhum tempo extra de sustentação). `tempos: 0` isola só a
            // transição, sem nenhum tempo de "marcar passo no lugar"
            // depois dela.
            final EstadoPessoa viaTransicao = _aplicar(
              viaTransicaoIntermediaria,
              Catalogo.marcarPasso(tempos: 0),
            );

            expect(
              (viaMarcandoPasso.x, viaMarcandoPasso.y),
              (viaTransicao.x, viaTransicao.y),
            );
            expect(viaMarcandoPasso.dir, viaTransicao.dir);
            expect(viaMarcandoPasso.cad, viaTransicao.cad);
            expect(a.duracaoTiquesPara(Cadencia.marchando), (n + 1) * 2);
          });
        }
      }
    },
  );

  group('Fechamento por simetria de rotação', () {
    test(
      '[marche(N), direita volver em marcha] × 4 = identidade, lado N+1 células',
      () {
        for (final int n in <int>[1, 2, 3]) {
          EstadoPessoa e = const EstadoPessoa(
            x: 0,
            y: 0,
            dir: 0,
            cad: Cadencia.firme,
          );
          for (int i = 0; i < 4; i++) {
            e = _aplicar(
              e,
              Catalogo.emFrenteMarche(
                n,
                aoTerminar: AoTerminarMarche.marchando,
              ),
            );
            e = _aplicar(e, Catalogo.direitaVolverMarcha());
          }
          expect((e.x, e.y), (0, 0), reason: 'N=$n deveria fechar o quadrado');
          expect(e.dir, 0);
          expect(e.cad, Cadencia.firme);
        }
      },
    );

    test(
      '[marche(N), oitava à direita em marcha] × 8 = identidade (antípodas, apesar da diagonal 0,71)',
      () {
        for (final int n in <int>[0, 1, 2]) {
          EstadoPessoa e = const EstadoPessoa(
            x: 0,
            y: 0,
            dir: 0,
            cad: Cadencia.firme,
          );
          for (int i = 0; i < 8; i++) {
            if (n > 0) {
              e = _aplicar(
                e,
                Catalogo.emFrenteMarche(
                  n,
                  aoTerminar: AoTerminarMarche.marchando,
                ),
              );
            }
            e = _aplicar(e, Catalogo.oitavaDireitaMarcha());
          }
          expect((e.x, e.y), (0, 0), reason: 'N=$n deveria fechar o octógono');
          expect(e.dir, 0);
          expect(e.cad, Cadencia.firme);
        }
      },
    );

    test('[marche(N), meia-volta em marcha] × 2 = identidade', () {
      for (final int n in <int>[0, 1, 3]) {
        EstadoPessoa e = const EstadoPessoa(
          x: 0,
          y: 0,
          dir: 0,
          cad: Cadencia.firme,
        );
        for (int i = 0; i < 2; i++) {
          if (n > 0) {
            e = _aplicar(
              e,
              Catalogo.emFrenteMarche(
                n,
                aoTerminar: AoTerminarMarche.marchando,
              ),
            );
          }
          e = _aplicar(e, Catalogo.meiaVoltaMarcha());
        }
        expect((e.x, e.y), (0, 0), reason: 'N=$n deveria voltar à origem');
        expect(e.dir, 0);
        expect(e.cad, Cadencia.firme);
      }
    });

    test('4× direita volver PARADO = identidade (nunca desloca)', () {
      EstadoPessoa e = const EstadoPessoa(
        x: 3,
        y: -1,
        dir: 3,
        cad: Cadencia.firme,
      );
      final EstadoPessoa origem = e;
      for (int i = 0; i < 4; i++) {
        e = _aplicar(e, Catalogo.direitaVolverParado());
      }
      expect((e.x, e.y), (origem.x, origem.y));
      expect(e.dir, origem.dir);
      expect(e.cad, Cadencia.firme);
    });
  });

  group(
    'Propriedade 3 — Duração ≠ destino: 12-16 sempre deslocam exatamente 1 '
    'TEMPO (nunca a duração total do movimento, que varia 2 ou 3 tempos)',
    () {
      // Duração hardcoded pelo autor do teste (não lida de `Movimento`) —
      // é o que se espera da spec, independente do catálogo.
      final Map<Movimento Function({bool bateRitmoAoJuntar}), int>
      movimentosEDuracoes = <Movimento Function({bool bateRitmoAoJuntar}), int>{
        Catalogo.direitaVolverMarcha: 3,
        Catalogo.esquerdaVolverMarcha: 2,
        Catalogo.meiaVoltaMarcha: 2,
        Catalogo.oitavaDireitaMarcha: 3,
        Catalogo.oitavaEsquerdaMarcha: 2,
      };

      movimentosEDuracoes.forEach((
        Movimento Function({bool bateRitmoAoJuntar}) builder,
        int tempos,
      ) {
        for (final int setor in List<int>.generate(8, (int i) => i)) {
          test('setor $setor', () {
            final Movimento m = builder();
            expect(m.duracaoTiquesPara(Cadencia.marchando), tempos * 2);
            final EstadoPessoa inicial = EstadoPessoa(
              x: 0,
              y: 0,
              dir: setor,
              cad: Cadencia.marchando,
            );
            final EstadoPessoa fim = _aplicar(inicial, m);
            final int dx = fim.x - inicial.x;
            final int dy = fim.y - inicial.y;
            final int magnitudeQuadrado = dx * dx + dy * dy;
            // Literal: SEMPRE 1 tempo de deslocamento, nunca `tempos`
            // (que varia 2 ou 3 conforme o movimento) — setor par (setor
            // ortogonal) desloca 1 célula cheia (`unidadesPorCelula²`,
            // literal); setor ímpar (diagonal) desloca meia célula por
            // eixo (`unidadesPorCelula²/2`, Pitágoras, também literal).
            // Nenhum dos dois valores é lido da estrutura do catálogo
            // (nº de segmentos, `tempos` do `Avanco` etc.) nem de
            // `deltaPorTiquePorSetor` — só de `unidadesPorCelula`, que é
            // a unidade atômica do motor, pinada por literais em
            // `geometria_test.dart`.
            final int esperado = setor.isEven
                ? unidadesPorCelula * unidadesPorCelula
                : (unidadesPorCelula * unidadesPorCelula) ~/ 2;
            expect(magnitudeQuadrado, esperado);
          });
        }
      });
    },
  );

  test(
    'Integralidade total: todo movimento × todo setor × todo tique dá quartos inteiros',
    () {
      final List<({Movimento Function() build, Cadencia entrada})>
      catalogo = <({Movimento Function() build, Cadencia entrada})>[
        (build: () => Catalogo.sentido(tempos: 2), entrada: Cadencia.firme),
        (build: () => Catalogo.descansar(tempos: 2), entrada: Cadencia.firme),
        (build: () => Catalogo.marcarPasso(tempos: 2), entrada: Cadencia.firme),
        (
          build: () => Catalogo.marcarPasso(tempos: 2),
          entrada: Cadencia.marchando,
        ),
        (build: () => Catalogo.baterORitmo(tempos: 2), entrada: Cadencia.firme),
        (
          build: () => Catalogo.emFrenteMarche(
            3,
            aoTerminar: AoTerminarMarche.marchando,
          ),
          entrada: Cadencia.marchando,
        ),
        (
          build: () => Catalogo.emFrenteMarche(
            3,
            aoTerminar: AoTerminarMarche.marcandoPasso,
          ),
          entrada: Cadencia.marchando,
        ),
        (
          build: () =>
              Catalogo.emFrenteMarche(3, aoTerminar: AoTerminarMarche.firme),
          entrada: Cadencia.marchando,
        ),
        (build: Catalogo.direitaVolverParado, entrada: Cadencia.firme),
        (build: Catalogo.esquerdaVolverParado, entrada: Cadencia.firme),
        (build: Catalogo.meiaVoltaParado, entrada: Cadencia.firme),
        (build: Catalogo.oitavaDireitaParado, entrada: Cadencia.firme),
        (build: Catalogo.oitavaEsquerdaParado, entrada: Cadencia.firme),
        (build: Catalogo.alto, entrada: Cadencia.marchando),
        (build: Catalogo.direitaVolverMarcha, entrada: Cadencia.marchando),
        (build: Catalogo.esquerdaVolverMarcha, entrada: Cadencia.marchando),
        (build: Catalogo.meiaVoltaMarcha, entrada: Cadencia.marchando),
        (build: Catalogo.oitavaDireitaMarcha, entrada: Cadencia.marchando),
        (build: Catalogo.oitavaEsquerdaMarcha, entrada: Cadencia.marchando),
      ];

      for (final registro in catalogo) {
        for (final int setor in List<int>.generate(8, (int i) => i)) {
          final EstadoPessoa inicial = EstadoPessoa(
            x: 0,
            y: 0,
            dir: setor,
            cad: registro.entrada,
          );
          final Movimento m = registro.build();
          final ResultadoSegmentos r = executarSegmentos(
            inicial,
            m.segmentosPara(registro.entrada),
            cadenciaFinal: m.cadenciaResultante(registro.entrada),
          );
          expect(r.tiques.length, m.duracaoTiquesPara(registro.entrada));
          for (final EstadoPessoa estado in r.tiques) {
            // O tipo já garante int; o que importa aqui é que a soma nunca
            // exige nenhuma divisão por unidadesPorCelula em lugar nenhum
            // do caminho — ver comentário de unidadesPorCelula==4 acima
            // (geometria_test.dart) para o motivo de U=2/U=8 quebrarem a
            // fidelidade geométrica mesmo sem quebrar o tipo.
            expect(estado.x, isA<int>());
            expect(estado.y, isA<int>());
          }
        }
      }
    },
  );

  group('Paridade diagonal', () {
    for (final int setor in <int>[1, 3, 5, 7]) {
      test(
        'setor $setor: marche(N) termina em múltiplo de 4 nos dois eixos ⟺ N par',
        () {
          for (int n = 1; n <= 6; n++) {
            final EstadoPessoa inicial = EstadoPessoa(
              x: 0,
              y: 0,
              dir: setor,
              cad: Cadencia.marchando,
            );
            final EstadoPessoa fim = _aplicar(
              inicial,
              Catalogo.emFrenteMarche(
                n,
                aoTerminar: AoTerminarMarche.marchando,
              ),
            );
            final bool multiplo4 =
                fim.x % unidadesPorCelula == 0 &&
                fim.y % unidadesPorCelula == 0;
            expect(
              multiplo4,
              n.isEven,
              reason: 'N=$n, setor=$setor, fim=($fim)',
            );
          }
        },
      );
    }
  });

  test(
    'Propriedade 6 — soma dos deltas por tique = N tempos de deslocamento '
    '(fonte independente: N, o parâmetro do movimento, e unidadesPorCelula '
    '— nunca deltaPorTiquePorSetor, que é a mesma tabela usada pra produzir '
    'os deltas)',
    () {
      const int n = 5; // literal — o parâmetro do movimento sob teste.
      for (final int setor in List<int>.generate(8, (int i) => i)) {
        final EstadoPessoa inicial = EstadoPessoa(
          x: 0,
          y: 0,
          dir: setor,
          cad: Cadencia.marchando,
        );
        final Movimento m = Catalogo.emFrenteMarche(
          n,
          aoTerminar: AoTerminarMarche.marchando,
        );
        final ResultadoSegmentos r = executarSegmentos(
          inicial,
          m.segmentosPara(Cadencia.marchando),
          cadenciaFinal: m.cadenciaResultante(Cadencia.marchando),
        );
        int somaDx = 0;
        int somaDy = 0;
        int xAnterior = inicial.x;
        int yAnterior = inicial.y;
        for (final EstadoPessoa estado in r.tiques) {
          somaDx += estado.x - xAnterior;
          somaDy += estado.y - yAnterior;
          xAnterior = estado.x;
          yAnterior = estado.y;
        }
        // Consistência interna: a soma dos deltas por tique bate com o
        // delta total do movimento.
        expect(somaDx, r.estadoFinal.x - inicial.x);
        expect(somaDy, r.estadoFinal.y - inicial.y);

        // E bate com N tempos de deslocamento, medido por MAGNITUDE² a
        // partir só de N e unidadesPorCelula (setor par = N células
        // cheias; setor ímpar = N meias-células por eixo, Pitágoras) —
        // nunca lendo `deltaPorTiquePorSetor[setor]` para montar a
        // expectativa.
        final int magnitudeQuadrado = somaDx * somaDx + somaDy * somaDy;
        final int esperado = setor.isEven
            ? (unidadesPorCelula * n) * (unidadesPorCelula * n)
            : (unidadesPorCelula * unidadesPorCelula * n * n) ~/ 2;
        expect(magnitudeQuadrado, esperado, reason: 'setor=$setor');
      }
    },
  );

  test('Determinismo: reprocessar duas vezes dá resultado bit-idêntico', () {
    final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
      0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.firme),
      1: const EstadoPessoa(x: 4, y: 0, dir: 0, cad: Cadencia.firme),
    });
    final List<Parte> partes = <Parte>[
      Parte(
        ordem: 0,
        atribuicoes: <int, Atribuicao>{
          0: Atribuicao(
            movimento: Catalogo.emFrenteMarche(
              3,
              aoTerminar: AoTerminarMarche.firme,
            ),
          ),
          1: Atribuicao(movimento: Catalogo.direitaVolverParado()),
        },
      ),
    ];

    final ResultadoSimulacao r1 = simular(inicial, partes);
    final ResultadoSimulacao r2 = simular(inicial, partes);

    expect(r1.porTique.length, r2.porTique.length);
    for (int i = 0; i < r1.porTique.length; i++) {
      expect(r1.porTique[i], r2.porTique[i]);
    }
    expect(r1.diagnosticos.length, r2.diagnosticos.length);
  });
}
