import 'package:evo_motor/evo_motor.dart';
import 'package:test/test.dart';

/// Executa um [Movimento] isolado a partir de (0,0), setor e cadência de
/// entrada dados, e devolve o [ResultadoSegmentos]. `segmentosPara` e
/// `cadenciaResultante` recebem a MESMA `entrada` — é assim que o motor
/// realmente monta e roda um movimento (ver `compilador.dart`).
ResultadoSegmentos _rodar(
  Movimento m, {
  required int setor,
  required Cadencia entrada,
}) {
  final EstadoPessoa inicial = EstadoPessoa(
    x: 0,
    y: 0,
    dir: setor,
    cad: entrada,
  );
  return executarSegmentos(
    inicial,
    m.segmentosPara(entrada),
    cadenciaFinal: m.cadenciaResultante(entrada),
  );
}

void main() {
  group('#1 Sentido/firme', () {
    test('N tempos, 0 deslocamento, cadência firme', () {
      final Movimento m = Catalogo.sentido(tempos: 3);
      final r = _rodar(m, setor: 0, entrada: Cadencia.descansar);
      expect(m.duracaoTiquesPara(Cadencia.descansar), 6);
      expect(r.estadoFinal.x, 0);
      expect(r.estadoFinal.y, 0);
      expect(r.estadoFinal.cad, Cadencia.firme);
    });

    test(
      'qualquer cadência de entrada é aceita; a partir de marchando emite aviso',
      () {
        expect(
          Catalogo.sentido().checarPrecondicao(Cadencia.descansar).ok,
          isTrue,
        );
        final ResultadoPrecondicao p = Catalogo.sentido().checarPrecondicao(
          Cadencia.marchando,
        );
        expect(p.ok, isTrue);
        expect(p.avisoTeleporte, isTrue);
      },
    );
  });

  group('#2 Descansar', () {
    test('N tempos, 0 deslocamento, cadência descansar', () {
      final Movimento m = Catalogo.descansar(tempos: 2);
      final r = _rodar(m, setor: 0, entrada: Cadencia.firme);
      expect(m.duracaoTiquesPara(Cadencia.firme), 4);
      expect((r.estadoFinal.x, r.estadoFinal.y), (0, 0));
      expect(r.estadoFinal.cad, Cadencia.descansar);
    });

    test(
      'exige firme ou marcandoPasso; marchando é teleporte com aviso; descansar->descansar é impossível',
      () {
        final Movimento m = Catalogo.descansar();
        expect(m.checarPrecondicao(Cadencia.firme).ok, isTrue);
        expect(m.checarPrecondicao(Cadencia.marcandoPasso).ok, isTrue);
        final ResultadoPrecondicao teleporte = m.checarPrecondicao(
          Cadencia.marchando,
        );
        expect(teleporte.ok, isTrue);
        expect(teleporte.avisoTeleporte, isTrue);
        expect(m.checarPrecondicao(Cadencia.descansar).ok, isFalse);
      },
    );
  });

  group('#3 Marcar passo', () {
    test(
      'de firme/descansar/marcandoPasso (já parado): P(N), N tempos, 0 deslocamento',
      () {
        for (final Cadencia entrada in <Cadencia>[
          Cadencia.firme,
          Cadencia.descansar,
          Cadencia.marcandoPasso,
        ]) {
          final Movimento m = Catalogo.marcarPasso(tempos: 2);
          final r = _rodar(m, setor: 0, entrada: entrada);
          expect(
            m.duracaoTiquesPara(entrada),
            4,
            reason: 'entrada=$entrada deveria custar só os 2 tempos pedidos',
          );
          expect(
            (r.estadoFinal.x, r.estadoFinal.y),
            (0, 0),
            reason: 'entrada=$entrada não deveria deslocar nada',
          );
          expect(r.estadoFinal.cad, Cadencia.marcandoPasso);
          expect(r.batidas.length, 2);
        }
      },
    );

    test(
      'de marchando: A(1)·J de transição + P(N) no lugar — N+2 tempos, desloca 1 célula',
      () {
        final Movimento m = Catalogo.marcarPasso(tempos: 2);
        final r = _rodar(m, setor: 0, entrada: Cadencia.marchando);
        expect(m.duracaoTiquesPara(Cadencia.marchando), 8); // (2+2)*2
        // Setor 0 = Norte: 1 célula = (0, -unidadesPorCelula).
        expect((r.estadoFinal.x, r.estadoFinal.y), (0, -unidadesPorCelula));
        expect(r.estadoFinal.dir, 0);
        expect(r.estadoFinal.cad, Cadencia.marcandoPasso);
        // 2 tempos de "marcar passo no lugar" == 2 batidas; a junção de
        // transição não bate ritmo por padrão.
        expect(r.batidas.length, 2);
      },
    );

    test(
      'de marchando com bateRitmoAoJuntar: a junção de transição também bate',
      () {
        final Movimento m = Catalogo.marcarPasso(
          tempos: 1,
          bateRitmoAoJuntar: true,
        );
        final r = _rodar(m, setor: 0, entrada: Cadencia.marchando);
        // 1 batida da junção de transição + 1 batida do tempo de marcar
        // passo = 2.
        expect(r.batidas.length, 2);
      },
    );

    test(
      'bateRitmoAoJuntar não tem efeito partindo de parado (não há junção)',
      () {
        final semBatida = _rodar(
          Catalogo.marcarPasso(tempos: 1),
          setor: 0,
          entrada: Cadencia.firme,
        );
        final comBatida = _rodar(
          Catalogo.marcarPasso(tempos: 1, bateRitmoAoJuntar: true),
          setor: 0,
          entrada: Cadencia.firme,
        );
        expect(comBatida.batidas, semBatida.batidas);
        expect(
          comBatida.tiques.map((e) => (e.x, e.y, e.dir, e.cad)).toList(),
          semBatida.tiques.map((e) => (e.x, e.y, e.dir, e.cad)).toList(),
        );
      },
    );

    test('aceita qualquer cadência de entrada', () {
      for (final Cadencia c in Cadencia.values) {
        expect(Catalogo.marcarPasso().checarPrecondicao(c).ok, isTrue);
      }
    });
  });

  group('#4 Bater o ritmo', () {
    test('mantém a cadência de entrada', () {
      final Movimento m = Catalogo.baterORitmo(tempos: 2);
      final r1 = _rodar(m, setor: 0, entrada: Cadencia.firme);
      expect(r1.estadoFinal.cad, Cadencia.firme);
      final r2 = _rodar(m, setor: 0, entrada: Cadencia.marcandoPasso);
      expect(r2.estadoFinal.cad, Cadencia.marcandoPasso);
    });

    test('exige firme ou marcandoPasso, sem exceção de teleporte', () {
      final Movimento m = Catalogo.baterORitmo();
      expect(m.checarPrecondicao(Cadencia.firme).ok, isTrue);
      expect(m.checarPrecondicao(Cadencia.marcandoPasso).ok, isTrue);
      expect(m.checarPrecondicao(Cadencia.marchando).ok, isFalse);
      expect(m.checarPrecondicao(Cadencia.descansar).ok, isFalse);
    });
  });

  group('#5 Em frente, marche', () {
    test(
      'aoTerminar: marchando — N tempos, desloca N células, permanece marchando',
      () {
        final Movimento m = Catalogo.emFrenteMarche(
          3,
          aoTerminar: AoTerminarMarche.marchando,
        );
        final r = _rodar(m, setor: 0, entrada: Cadencia.marchando);
        expect(m.duracaoTiquesPara(Cadencia.marchando), 6);
        expect((r.estadoFinal.x, r.estadoFinal.y), (0, -12));
        expect(r.estadoFinal.cad, Cadencia.marchando);
      },
    );

    test(
      'aoTerminar: marcandoPasso — A(N)·J (catálogo v2): N+1 tempos, desloca N (a junção não anda)',
      () {
        final Movimento m = Catalogo.emFrenteMarche(
          3,
          aoTerminar: AoTerminarMarche.marcandoPasso,
        );
        final r = _rodar(m, setor: 0, entrada: Cadencia.marchando);
        expect(m.duracaoTiquesPara(Cadencia.marchando), 8); // (3+1)*2
        expect((r.estadoFinal.x, r.estadoFinal.y), (0, -12)); // ainda 3 células
        expect(r.estadoFinal.cad, Cadencia.marcandoPasso);
      },
    );

    test(
      'aoTerminar: firme — N+1 tempos, deslocamento continua N (a junção não anda)',
      () {
        final Movimento m = Catalogo.emFrenteMarche(
          3,
          aoTerminar: AoTerminarMarche.firme,
        );
        final r = _rodar(m, setor: 0, entrada: Cadencia.marchando);
        expect(m.duracaoTiquesPara(Cadencia.marchando), 8); // (3+1) tempos * 2
        expect((r.estadoFinal.x, r.estadoFinal.y), (0, -12)); // ainda 3 células
        expect(r.estadoFinal.cad, Cadencia.firme);
      },
    );

    test(
      'marcandoPasso e firme têm a MESMA duração e o MESMO deslocamento (simétricos, só a cadência final muda)',
      () {
        final Movimento viaMarcandoPasso = Catalogo.emFrenteMarche(
          4,
          aoTerminar: AoTerminarMarche.marcandoPasso,
        );
        final Movimento viaFirme = Catalogo.emFrenteMarche(
          4,
          aoTerminar: AoTerminarMarche.firme,
        );
        expect(
          viaMarcandoPasso.duracaoTiquesPara(Cadencia.marchando),
          viaFirme.duracaoTiquesPara(Cadencia.marchando),
        );
        final rMp = _rodar(viaMarcandoPasso, setor: 2, entrada: Cadencia.marchando);
        final rFirme = _rodar(viaFirme, setor: 2, entrada: Cadencia.marchando);
        expect(
          (rMp.estadoFinal.x, rMp.estadoFinal.y),
          (rFirme.estadoFinal.x, rFirme.estadoFinal.y),
        );
      },
    );

    test('exige firme, marcandoPasso ou marchando', () {
      final Movimento m = Catalogo.emFrenteMarche(
        1,
        aoTerminar: AoTerminarMarche.marchando,
      );
      expect(m.checarPrecondicao(Cadencia.firme).ok, isTrue);
      expect(m.checarPrecondicao(Cadencia.marcandoPasso).ok, isTrue);
      expect(m.checarPrecondicao(Cadencia.marchando).ok, isTrue);
      expect(m.checarPrecondicao(Cadencia.descansar).ok, isFalse);
    });
  });

  group(
    '#6-#10 Volver/oitava parados — 2 tempos (pivô + junção), 0 deslocamento',
    () {
      final Map<String, (Movimento Function({bool bateRitmoAoJuntar}), int)>
      casos = <String, (Movimento Function({bool bateRitmoAoJuntar}), int)>{
        'Direita volver': (Catalogo.direitaVolverParado, 2),
        'Esquerda volver': (Catalogo.esquerdaVolverParado, 6), // -2 mod 8
        'Meia-volta': (Catalogo.meiaVoltaParado, 4),
        'Oitava à direita': (Catalogo.oitavaDireitaParado, 1),
        'Oitava à esquerda': (Catalogo.oitavaEsquerdaParado, 7), // -1 mod 8
      };

      casos.forEach((
        String nome,
        (Movimento Function({bool bateRitmoAoJuntar}), int) caso,
      ) {
        test(nome, () {
          final Movimento m = caso.$1();
          expect(m.duracaoTiquesPara(Cadencia.firme), 4); // 2 tempos
          final r = _rodar(m, setor: 0, entrada: Cadencia.firme);
          expect((r.estadoFinal.x, r.estadoFinal.y), (0, 0));
          expect(r.estadoFinal.dir, caso.$2);
          expect(r.estadoFinal.cad, Cadencia.firme);
          expect(m.checarPrecondicao(Cadencia.firme).ok, isTrue);
          expect(m.checarPrecondicao(Cadencia.marchando).ok, isFalse);
        });
      });

      test('bateRitmoAoJuntar é aceito (6-16, não só 11-16)', () {
        final Movimento m = Catalogo.direitaVolverParado(
          bateRitmoAoJuntar: true,
        );
        final r = _rodar(m, setor: 0, entrada: Cadencia.firme);
        expect(r.batidas, isNotEmpty);
      });
    },
  );

  group('#11 Alto', () {
    test('A(1)·J — 2 tempos, desloca 1 célula, termina firme', () {
      final Movimento m = Catalogo.alto();
      final r = _rodar(m, setor: 0, entrada: Cadencia.marchando);
      expect(m.duracaoTiquesPara(Cadencia.marchando), 4);
      expect((r.estadoFinal.x, r.estadoFinal.y), (0, -4));
      expect(r.estadoFinal.dir, 0);
      expect(r.estadoFinal.cad, Cadencia.firme);
    });

    test('exige marchando', () {
      expect(Catalogo.alto().checarPrecondicao(Cadencia.marchando).ok, isTrue);
      expect(Catalogo.alto().checarPrecondicao(Cadencia.firme).ok, isFalse);
    });
  });

  group(
    '#12-#16 Volver/oitava em marcha — sempre 1 célula na direção ANTIGA',
    () {
      final Map<
        String,
        (
          Movimento Function({bool bateRitmoAoJuntar}),
          int tempos,
          int setorFinal,
        )
      >
      casos =
          <String, (Movimento Function({bool bateRitmoAoJuntar}), int, int)>{
            'Direita volver (marcha)': (Catalogo.direitaVolverMarcha, 3, 2),
            'Esquerda volver (marcha)': (Catalogo.esquerdaVolverMarcha, 2, 6),
            'Meia-volta (marcha)': (Catalogo.meiaVoltaMarcha, 2, 4),
            'Oitava à direita (marcha)': (Catalogo.oitavaDireitaMarcha, 3, 1),
            'Oitava à esquerda (marcha)': (Catalogo.oitavaEsquerdaMarcha, 2, 7),
          };

      casos.forEach((
        String nome,
        (Movimento Function({bool bateRitmoAoJuntar}), int, int) caso,
      ) {
        test(nome, () {
          final Movimento m = caso.$1();
          expect(m.duracaoTiquesPara(Cadencia.marchando), caso.$2 * 2);
          final r = _rodar(m, setor: 0, entrada: Cadencia.marchando);
          // Sempre 1 célula (4 quartos, setor 0 = Norte) na direção ANTIGA,
          // nunca a nova — nenhuma linha do catálogo desloca na direção nova.
          expect((r.estadoFinal.x, r.estadoFinal.y), (0, -4));
          expect(r.estadoFinal.dir, caso.$3);
          expect(r.estadoFinal.cad, Cadencia.firme);
          expect(m.checarPrecondicao(Cadencia.marchando).ok, isTrue);
          expect(m.checarPrecondicao(Cadencia.firme).ok, isFalse);
        });
      });
    },
  );

  test('todo movimento 11-16 termina em firme', () {
    final List<Movimento> onzeASedezesseis = <Movimento>[
      Catalogo.alto(),
      Catalogo.direitaVolverMarcha(),
      Catalogo.esquerdaVolverMarcha(),
      Catalogo.meiaVoltaMarcha(),
      Catalogo.oitavaDireitaMarcha(),
      Catalogo.oitavaEsquerdaMarcha(),
    ];
    for (final Movimento m in onzeASedezesseis) {
      expect(m.cadenciaResultante(Cadencia.marchando), Cadencia.firme);
    }
  });

  test('#4 preserva a cadência de entrada firme', () {
    expect(
      Catalogo.baterORitmo().cadenciaResultante(Cadencia.firme),
      Cadencia.firme,
    );
  });

  test('#4 preserva a cadência de entrada marcandoPasso', () {
    expect(
      Catalogo.baterORitmo().cadenciaResultante(Cadencia.marcandoPasso),
      Cadencia.marcandoPasso,
    );
  });

  test(
    'bateRitmoAoJuntar é inerte: alternar a flag não muda nenhum tique de posição/direção/cadência',
    () {
      final List<Movimento Function({bool bateRitmoAoJuntar})> builders =
          <Movimento Function({bool bateRitmoAoJuntar})>[
            Catalogo.direitaVolverParado,
            Catalogo.esquerdaVolverParado,
            Catalogo.meiaVoltaParado,
            Catalogo.oitavaDireitaParado,
            Catalogo.oitavaEsquerdaParado,
            Catalogo.alto,
            Catalogo.direitaVolverMarcha,
            Catalogo.esquerdaVolverMarcha,
            Catalogo.meiaVoltaMarcha,
            Catalogo.oitavaDireitaMarcha,
            Catalogo.oitavaEsquerdaMarcha,
          ];
      for (final builder in builders) {
        final Cadencia entrada =
            builder == Catalogo.alto ||
                builder == Catalogo.direitaVolverMarcha ||
                builder == Catalogo.esquerdaVolverMarcha ||
                builder == Catalogo.meiaVoltaMarcha ||
                builder == Catalogo.oitavaDireitaMarcha ||
                builder == Catalogo.oitavaEsquerdaMarcha
            ? Cadencia.marchando
            : Cadencia.firme;
        for (final int setor in List<int>.generate(8, (i) => i)) {
          final semBatida = _rodar(
            builder(bateRitmoAoJuntar: false),
            setor: setor,
            entrada: entrada,
          );
          final comBatida = _rodar(
            builder(bateRitmoAoJuntar: true),
            setor: setor,
            entrada: entrada,
          );
          expect(
            comBatida.tiques.map((e) => (e.x, e.y, e.dir, e.cad)).toList(),
            semBatida.tiques.map((e) => (e.x, e.y, e.dir, e.cad)).toList(),
          );
        }
      }
    },
  );
}
