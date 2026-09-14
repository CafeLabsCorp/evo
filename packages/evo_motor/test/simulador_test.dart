import 'package:evo_motor/evo_motor.dart';
import 'package:test/test.dart';

void main() {
  group('Continuação implícita', () {
    test('slot sem atribuição em firme fica parado pelo T da parte', () {
      final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
        0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.firme),
        1: const EstadoPessoa(x: 8, y: 0, dir: 0, cad: Cadencia.firme),
      });
      final Parte parte = Parte(
        ordem: 0,
        atribuicoes: <int, Atribuicao>{
          0: Atribuicao(
            movimento: Catalogo.emFrenteMarche(
              2,
              aoTerminar: AoTerminarMarche.firme,
            ),
          ),
          // slot 1 sem atribuição.
        },
      );
      final ResultadoSimulacao r = simular(inicial, <Parte>[parte]);
      for (final EstadoFormacao f in r.porTique) {
        expect(f[1].x, 8);
        expect(f[1].y, 0);
        expect(f[1].cad, Cadencia.firme);
      }
    });

    test(
      'slot sem atribuição marchando continua marchando (EmFrenteMarche T/2)',
      () {
        final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
          0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.marchando),
          1: const EstadoPessoa(x: 8, y: 0, dir: 0, cad: Cadencia.marchando),
        });
        // T = 8 tiques (definido pelo slot 0: emFrenteMarche(4, marchando)).
        final Parte parte = Parte(
          ordem: 0,
          atribuicoes: <int, Atribuicao>{
            0: Atribuicao(
              movimento: Catalogo.emFrenteMarche(
                4,
                aoTerminar: AoTerminarMarche.marchando,
              ),
            ),
          },
        );
        final ResultadoSimulacao r = simular(inicial, <Parte>[parte]);
        final EstadoPessoa fimSlot1 = r.porTique.last[1];
        // T=8 tiques => 4 tempos de continuação, mesmo delta do setor 0.
        expect((fimSlot1.x, fimSlot1.y), (8, -16));
        expect(fimSlot1.cad, Cadencia.marchando);
      },
    );
  });

  group('Checagem 1 — Comando impossível', () {
    test(
      'direita volver parado a partir de descansar é bloqueado; cai em continuação implícita',
      () {
        final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
          0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.descansar),
        });
        final Parte parte = Parte(
          ordem: 0,
          atribuicoes: <int, Atribuicao>{
            0: Atribuicao(movimento: Catalogo.direitaVolverParado()),
          },
        );
        final ResultadoSimulacao r = simular(inicial, <Parte>[parte]);

        final erros = r.diagnosticos
            .whereType<DiagnosticoComandoImpossivel>()
            .toList();
        expect(erros, hasLength(1));
        expect(erros.first.severidade, SeveridadeDiagnostico.erro);

        // Continuação implícita de "descansar": parado, cadência mantida —
        // o giro NÃO acontece.
        for (final EstadoFormacao f in r.porTique) {
          expect(f[0].dir, 0);
          expect(f[0].cad, Cadencia.descansar);
          expect((f[0].x, f[0].y), (0, 0));
        }
      },
    );

    test(
      'Sentido a partir de marchando é permitido, mas emite aviso de teleporte',
      () {
        final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
          0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.marchando),
        });
        final Parte parte = Parte(
          ordem: 0,
          atribuicoes: <int, Atribuicao>{
            0: Atribuicao(movimento: Catalogo.sentido(tempos: 2)),
          },
        );
        final ResultadoSimulacao r = simular(inicial, <Parte>[parte]);

        final avisos = r.diagnosticos
            .whereType<DiagnosticoComandoImpossivel>()
            .where((d) => d.severidade == SeveridadeDiagnostico.aviso)
            .toList();
        expect(avisos, hasLength(1));
        expect(r.porTique.last[0].cad, Cadencia.firme);
      },
    );
  });

  group('Checagem 2 — Encadeamento', () {
    test(
      'detecta divergência de cadência entre o fim real e o início exigido',
      () {
        final EstadoFormacao fim = EstadoFormacao(<int, EstadoPessoa>{
          0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.marchando),
        });
        final EstadoFormacao proximoInicioExigido = EstadoFormacao(
          <int, EstadoPessoa>{
            0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.firme),
          },
        );
        final diags = verificarEncadeamento(fim, proximoInicioExigido);
        expect(diags, hasLength(1));
        expect(diags.first, isA<DiagnosticoEncadeamento>());
        expect(
          (diags.first as DiagnosticoEncadeamento).motivo,
          contains('cadência diverge'),
        );
      },
    );

    test('detecta diferença de conjunto de slots', () {
      final EstadoFormacao fim = EstadoFormacao(<int, EstadoPessoa>{
        0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.firme),
      });
      final EstadoFormacao proximoInicioExigido =
          EstadoFormacao(<int, EstadoPessoa>{
            0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.firme),
            1: const EstadoPessoa(x: 4, y: 0, dir: 0, cad: Cadencia.firme),
          });
      final diags = verificarEncadeamento(fim, proximoInicioExigido);
      expect(diags, hasLength(1));
    });

    test(
      'simularSequencia: modo declarado vs encadeado divergem quando o fim real não bate com o gravado',
      () {
        final Evolucao evo1 = Evolucao(
          nome: 'Evolução 1',
          estadoInicial: EstadoFormacao(<int, EstadoPessoa>{
            0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.firme),
          }),
          partes: <Parte>[
            Parte(
              ordem: 0,
              atribuicoes: <int, Atribuicao>{
                0: Atribuicao(
                  movimento: Catalogo.emFrenteMarche(
                    2,
                    aoTerminar: AoTerminarMarche.marchando,
                  ),
                ),
              },
            ),
          ],
        );
        // Evolução 2 foi PROJETADA para começar de (0,0) firme — mas na
        // vida real o pelotão vai chegar em (0,-8) marchando.
        final Evolucao evo2 = Evolucao(
          nome: 'Evolução 2',
          estadoInicial: EstadoFormacao(<int, EstadoPessoa>{
            0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.firme),
          }),
          partes: <Parte>[
            Parte(
              ordem: 0,
              atribuicoes: <int, Atribuicao>{
                0: Atribuicao(movimento: Catalogo.direitaVolverParado()),
              },
            ),
          ],
        );

        final ResultadoSequencia declarado = simularSequencia(<Evolucao>[
          evo1,
          evo2,
        ], ModoSequencia.declarado);
        final ResultadoSequencia encadeado = simularSequencia(<Evolucao>[
          evo1,
          evo2,
        ], ModoSequencia.encadeado);

        // O diagnóstico de encadeamento aparece nos dois modos (é uma
        // comparação fixa entre fim real e início gravado).
        expect(declarado.diagnosticosEncadeamento, isNotEmpty);
        expect(encadeado.diagnosticosEncadeamento, isNotEmpty);

        // Mas o RESULTADO da evolução 2 diverge entre os modos: em
        // "declarado" ela recebe (0,0) firme (o que foi planejado) e o
        // direita-volver roda normalmente, virando pra setor 2. Em
        // "encadeado" ela recebe o fim REAL da evolução 1 — marchando, sem
        // ter dado Alto — então o direita-volver (que exige firme) é um
        // comando impossível ali: emite diagnóstico e o slot cai em
        // continuação implícita (segue marchando, nunca vira).
        expect(declarado.porEvolucao[1].porTique.last[0].dir, 2);
        expect(
          declarado.porEvolucao[1].diagnosticos
              .whereType<DiagnosticoComandoImpossivel>(),
          isEmpty,
        );

        expect(encadeado.porEvolucao[1].porTique.last[0].dir, 0);
        expect(
          encadeado.porEvolucao[1].porTique.last[0].cad,
          Cadencia.marchando,
        );
        expect(
          encadeado.porEvolucao[1].diagnosticos
              .whereType<DiagnosticoComandoImpossivel>(),
          isNotEmpty,
        );
      },
    );
  });

  group('Checagem 3 — Colisão', () {
    test(
      'formação inteira marchando em diagonal em uníssono: zero falso positivo',
      () {
        final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
          0: const EstadoPessoa(x: 0, y: 0, dir: 1, cad: Cadencia.marchando),
          1: EstadoPessoa(
            x: unidadesPorCelula,
            y: 0,
            dir: 1,
            cad: Cadencia.marchando,
          ),
          2: EstadoPessoa(
            x: 0,
            y: unidadesPorCelula,
            dir: 1,
            cad: Cadencia.marchando,
          ),
        });
        final Parte parte = Parte(
          ordem: 0,
          atribuicoes: <int, Atribuicao>{
            0: Atribuicao(
              movimento: Catalogo.emFrenteMarche(
                4,
                aoTerminar: AoTerminarMarche.marchando,
              ),
            ),
            1: Atribuicao(
              movimento: Catalogo.emFrenteMarche(
                4,
                aoTerminar: AoTerminarMarche.marchando,
              ),
            ),
            2: Atribuicao(
              movimento: Catalogo.emFrenteMarche(
                4,
                aoTerminar: AoTerminarMarche.marchando,
              ),
            ),
          },
        );
        final ResultadoSimulacao r = simular(inicial, <Parte>[parte]);
        expect(r.diagnosticos.whereType<DiagnosticoColisao>(), isEmpty);
      },
    );

    test('dois slots que se cruzam de frente disparam erro de colisão', () {
      final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
        0: const EstadoPessoa(
          x: 0,
          y: 0,
          dir: 2,
          cad: Cadencia.marchando,
        ), // Leste
        1: EstadoPessoa(
          x: 2 * unidadesPorCelula,
          y: 0,
          dir: 6,
          cad: Cadencia.marchando,
        ), // Oeste
      });
      final Parte parte = Parte(
        ordem: 0,
        atribuicoes: <int, Atribuicao>{
          0: Atribuicao(
            movimento: Catalogo.emFrenteMarche(
              1,
              aoTerminar: AoTerminarMarche.marchando,
            ),
          ),
          1: Atribuicao(
            movimento: Catalogo.emFrenteMarche(
              1,
              aoTerminar: AoTerminarMarche.marchando,
            ),
          ),
        },
      );
      final ResultadoSimulacao r = simular(inicial, <Parte>[parte]);
      final colisoes = r.diagnosticos.whereType<DiagnosticoColisao>().toList();
      expect(
        colisoes.any((c) => c.severidade == SeveridadeDiagnostico.erro),
        isTrue,
      );
    });

    test(
      'espaçamento de exatamente 1 célula em fileira nunca gera aviso (limiar estrito)',
      () {
        final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
          0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.marchando),
          1: EstadoPessoa(
            x: unidadesPorCelula,
            y: 0,
            dir: 0,
            cad: Cadencia.marchando,
          ),
        });
        final Parte parte = Parte(
          ordem: 0,
          atribuicoes: <int, Atribuicao>{
            0: Atribuicao(
              movimento: Catalogo.emFrenteMarche(
                3,
                aoTerminar: AoTerminarMarche.marchando,
              ),
            ),
            1: Atribuicao(
              movimento: Catalogo.emFrenteMarche(
                3,
                aoTerminar: AoTerminarMarche.marchando,
              ),
            ),
          },
        );
        final ResultadoSimulacao r = simular(inicial, <Parte>[parte]);
        expect(r.diagnosticos.whereType<DiagnosticoColisao>(), isEmpty);
      },
    );
  });

  group('Checagem 4 — Fora dos limites', () {
    test('sai de um campo pequeno e configurável', () {
      final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
        0: const EstadoPessoa(
          x: 0,
          y: 0,
          dir: 4,
          cad: Cadencia.marchando,
        ), // Sul
      });
      final Parte parte = Parte(
        ordem: 0,
        atribuicoes: <int, Atribuicao>{
          0: Atribuicao(
            movimento: Catalogo.emFrenteMarche(
              3,
              aoTerminar: AoTerminarMarche.marchando,
            ),
          ),
        },
      );
      const Config cfgPequena = Config(
        campo: Campo(larguraCelulas: 4, alturaCelulas: 4),
      );
      final ResultadoSimulacao r = simular(inicial, <Parte>[parte], cfgPequena);
      expect(r.diagnosticos.whereType<DiagnosticoForaDosLimites>(), isNotEmpty);
    });

    test('dentro de um campo grande, não dispara nada', () {
      final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
        0: const EstadoPessoa(x: 0, y: 0, dir: 4, cad: Cadencia.marchando),
      });
      final Parte parte = Parte(
        ordem: 0,
        atribuicoes: <int, Atribuicao>{
          0: Atribuicao(
            movimento: Catalogo.emFrenteMarche(
              3,
              aoTerminar: AoTerminarMarche.marchando,
            ),
          ),
        },
      );
      final ResultadoSimulacao r = simular(inicial, <Parte>[parte]);
      expect(r.diagnosticos.whereType<DiagnosticoForaDosLimites>(), isEmpty);
    });
  });

  group('Faixas de playback', () {
    test('faixas cobrem porTique sem sobreposição e na ordem certa', () {
      final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
        0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.firme),
      });
      final List<Parte> partes = <Parte>[
        Parte(
          ordem: 0,
          atribuicoes: <int, Atribuicao>{
            0: Atribuicao(movimento: Catalogo.marcarPasso(tempos: 2)),
          },
        ),
        Parte(
          ordem: 1,
          atribuicoes: <int, Atribuicao>{
            0: Atribuicao(
              movimento: Catalogo.emFrenteMarche(
                2,
                aoTerminar: AoTerminarMarche.firme,
              ),
            ),
          },
        ),
      ];
      final ResultadoSimulacao r = simular(inicial, partes);
      expect(r.faixas, hasLength(2));
      expect(r.faixas[0].tiqueInicio, 0);
      expect(r.faixas[0].tiqueFim, r.faixas[1].tiqueInicio);
      expect(r.faixas[1].tiqueFim, r.porTique.length);
    });
  });
}
