import 'dart:convert';
import 'dart:io';

import 'package:evo_motor/evo_motor.dart';
import 'package:test/test.dart';

/// Testes do canal de percussão — ver a spec em `parte.dart`
/// (`Atribuicao.percussao`) e a emissão em `compilador.dart`
/// (`_emitirPercussao`). Numeração dos grupos corresponde à lista de
/// "Testes exigidos" da spec.

/// Catálogo de movimentos usado pelos testes de inércia/ortogonalidade —
/// cada entrada é um builder e o conjunto de cadências de ENTRADA válidas
/// para ele (o mesmo padrão de `propriedades_test.dart`).
final List<({Movimento Function() build, Set<Cadencia> entradasValidas})>
_catalogoParaVarredura =
    <({Movimento Function() build, Set<Cadencia> entradasValidas})>[
      (
        build: () => Catalogo.sentido(tempos: 2),
        entradasValidas: Cadencia.values.toSet(),
      ),
      (
        build: () => Catalogo.descansar(tempos: 2),
        entradasValidas: <Cadencia>{
          Cadencia.firme,
          Cadencia.marcandoPasso,
          Cadencia.marchando,
        },
      ),
      (
        build: () => Catalogo.marcarPasso(tempos: 2),
        entradasValidas: Cadencia.values.toSet(),
      ),
      (
        build: () => Catalogo.baterORitmo(tempos: 2),
        entradasValidas: <Cadencia>{Cadencia.firme, Cadencia.marcandoPasso},
      ),
      (
        build: () => Catalogo.emFrenteMarche(
          3,
          aoTerminar: AoTerminarMarche.marchando,
        ),
        entradasValidas: <Cadencia>{
          Cadencia.firme,
          Cadencia.marcandoPasso,
          Cadencia.marchando,
        },
      ),
      (
        build: () => Catalogo.emFrenteMarche(
          3,
          aoTerminar: AoTerminarMarche.marcandoPasso,
        ),
        entradasValidas: <Cadencia>{
          Cadencia.firme,
          Cadencia.marcandoPasso,
          Cadencia.marchando,
        },
      ),
      (
        build: () =>
            Catalogo.emFrenteMarche(3, aoTerminar: AoTerminarMarche.firme),
        entradasValidas: <Cadencia>{
          Cadencia.firme,
          Cadencia.marcandoPasso,
          Cadencia.marchando,
        },
      ),
      (
        build: Catalogo.direitaVolverParado,
        entradasValidas: <Cadencia>{Cadencia.firme},
      ),
      (
        build: Catalogo.esquerdaVolverParado,
        entradasValidas: <Cadencia>{Cadencia.firme},
      ),
      (
        build: Catalogo.meiaVoltaParado,
        entradasValidas: <Cadencia>{Cadencia.firme},
      ),
      (
        build: Catalogo.oitavaDireitaParado,
        entradasValidas: <Cadencia>{Cadencia.firme},
      ),
      (
        build: Catalogo.oitavaEsquerdaParado,
        entradasValidas: <Cadencia>{Cadencia.firme},
      ),
      (build: Catalogo.alto, entradasValidas: <Cadencia>{Cadencia.marchando}),
      (
        build: Catalogo.direitaVolverMarcha,
        entradasValidas: <Cadencia>{Cadencia.marchando},
      ),
      (
        build: Catalogo.esquerdaVolverMarcha,
        entradasValidas: <Cadencia>{Cadencia.marchando},
      ),
      (
        build: Catalogo.meiaVoltaMarcha,
        entradasValidas: <Cadencia>{Cadencia.marchando},
      ),
      (
        build: Catalogo.oitavaDireitaMarcha,
        entradasValidas: <Cadencia>{Cadencia.marchando},
      ),
      (
        build: Catalogo.oitavaEsquerdaMarcha,
        entradasValidas: <Cadencia>{Cadencia.marchando},
      ),
    ];

/// Simula uma parte de UM slot com o movimento/entrada/setor dados,
/// opcionalmente com percussão.
ResultadoSimulacao _simularUmSlot(
  Movimento movimento,
  Cadencia entrada,
  int setor, {
  Percussao? percussao,
}) {
  final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
    0: EstadoPessoa(x: 0, y: 0, dir: setor, cad: entrada),
  });
  final Parte parte = Parte(
    ordem: 0,
    atribuicoes: <int, Atribuicao>{
      0: Atribuicao(movimento: movimento, percussao: percussao),
    },
  );
  return simular(inicial, <Parte>[parte]);
}

List<String> _diagsComoTexto(List<Diagnostico> d) =>
    d.map((e) => e.toString()).toList();

void main() {
  group('1 — Inércia total: percussão nunca muda um tique nem um diagnóstico', () {
    for (final registro in _catalogoParaVarredura) {
      for (final Cadencia entrada in registro.entradasValidas) {
        for (final int setor in List<int>.generate(8, (int i) => i)) {
          test(
            '${registro.build().nome}, entrada=$entrada, setor=$setor',
            () {
              final Movimento semPerc = registro.build();
              final Movimento comPerc = registro.build();
              if (!semPerc.checarPrecondicao(entrada).ok) {
                return; // combinação inválida, fora do escopo do teste.
              }
              // Combinações que a REGRA DE ACEITAÇÃO de percussão rejeita
              // (cadência de entrada ou resultante == descansar) ficam fora
              // deste teste de propósito: ali a percussão É diferente com
              // e sem (aparece um `DiagnosticoPercussaoInvalida`) — essa é
              // exatamente a garantia coberta pelo grupo 6 ("Rejeição em
              // descansar"), não uma contradição com a inércia total.
              final bool seriaRejeitada =
                  entrada == Cadencia.descansar ||
                  semPerc.cadenciaResultante(entrada) == Cadencia.descansar;
              if (seriaRejeitada) return;

              final ResultadoSimulacao a = _simularUmSlot(
                semPerc,
                entrada,
                setor,
              );
              final ResultadoSimulacao b = _simularUmSlot(
                comPerc,
                entrada,
                setor,
                percussao: const Percussao(membro: MembroPercussao.mao),
              );

              expect(a.porTique.length, b.porTique.length);
              for (int i = 0; i < a.porTique.length; i++) {
                expect(
                  b.porTique[i],
                  a.porTique[i],
                  reason: 'tique $i divergiu com percussão ligada',
                );
              }
              expect(_diagsComoTexto(b.diagnosticos), _diagsComoTexto(a.diagnosticos));
            },
          );
        }
      }
    }
  });

  group('2 — Ortogonalidade: trocar o membro não muda tique nenhum', () {
    test('mao vs pernaEsquerda: mesmos tiques, mesma contagem de eventos, só o tipo muda', () {
      final ResultadoSimulacao comMao = _simularUmSlot(
        Catalogo.baterORitmo(tempos: 2),
        Cadencia.firme,
        0,
        percussao: const Percussao(membro: MembroPercussao.mao),
      );
      final ResultadoSimulacao comPernaEsquerda = _simularUmSlot(
        Catalogo.baterORitmo(tempos: 2),
        Cadencia.firme,
        0,
        percussao: const Percussao(membro: MembroPercussao.pernaEsquerda),
      );

      expect(comPernaEsquerda.porTique.length, comMao.porTique.length);
      for (int i = 0; i < comMao.porTique.length; i++) {
        expect(comPernaEsquerda.porTique[i], comMao.porTique[i]);
      }

      // Filtra só os eventos de PERCUSSÃO (exclui os de passo que
      // `baterORitmo` já emite sozinho) — o ponto do teste é que trocar o
      // membro não mexe em mais nada, não que não existam outros eventos.
      final List<EventoBatida> eventosMao = comMao.eventos
          .whereType<EventoBatida>()
          .where((e) => e.tipo != TipoBatida.passo)
          .toList()
        ..sort((a, b) => a.tiqueGlobal.compareTo(b.tiqueGlobal));
      final List<EventoBatida> eventosPerna = comPernaEsquerda.eventos
          .whereType<EventoBatida>()
          .where((e) => e.tipo != TipoBatida.passo)
          .toList()
        ..sort((a, b) => a.tiqueGlobal.compareTo(b.tiqueGlobal));

      expect(eventosPerna.length, eventosMao.length);
      for (int i = 0; i < eventosMao.length; i++) {
        expect(eventosPerna[i].tiqueGlobal, eventosMao[i].tiqueGlobal);
        expect(eventosPerna[i].slot, eventosMao[i].slot);
        expect(eventosMao[i].tipo, TipoBatida.mao);
        expect(eventosPerna[i].tipo, TipoBatida.pernaEsquerda);
      }
    });
  });

  group('3 — Grade de tempos, de fonte independente', () {
    test(
      'toda batida de percussão cai em tiqueGlobal ímpar, contagem == T~/2 '
      '(T calculado pelo autor do teste, nunca lido do emissor)',
      () {
        // T calculado à mão: emFrenteMarche(3, marchando) = 3 tempos = 6
        // tiques (não há junção quando termina marchando).
        const int tCalculadoPelaMao = 6;
        final ResultadoSimulacao r = _simularUmSlot(
          Catalogo.emFrenteMarche(3, aoTerminar: AoTerminarMarche.marchando),
          Cadencia.marchando,
          0,
          percussao: const Percussao(membro: MembroPercussao.pernaDireita),
        );
        final List<EventoBatida> percussao = r.eventos
            .whereType<EventoBatida>()
            .where((e) => e.tipo == TipoBatida.pernaDireita)
            .toList();
        expect(percussao.length, tCalculadoPelaMao ~/ 2);
        for (final EventoBatida e in percussao) {
          expect(e.tiqueGlobal.isOdd, isTrue, reason: 'tique ${e.tiqueGlobal}');
        }
      },
    );

    test(
      'movimento com junção (Alto: A(1)·J, T calculado = 4 tiques) também bate a grade',
      () {
        const int tCalculadoPelaMao = 4; // (1+1) tempos * 2
        final ResultadoSimulacao r = _simularUmSlot(
          Catalogo.alto(),
          Cadencia.marchando,
          2,
          percussao: const Percussao(membro: MembroPercussao.mao),
        );
        final List<EventoBatida> percussao = r.eventos
            .whereType<EventoBatida>()
            .where((e) => e.tipo == TipoBatida.mao)
            .toList();
        expect(percussao.length, tCalculadoPelaMao ~/ 2);
        for (final EventoBatida e in percussao) {
          expect(e.tiqueGlobal.isOdd, isTrue);
        }
      },
    );
  });

  group('4 — Coexistência: passo e percussão no mesmo tique', () {
    test(
      'baterORitmo(tempos: 2) + percussão: 2 EventoBatida no mesmo tique, tipos distintos',
      () {
        final ResultadoSimulacao r = _simularUmSlot(
          Catalogo.baterORitmo(tempos: 2),
          Cadencia.firme,
          0,
          percussao: const Percussao(membro: MembroPercussao.pernaEsquerda),
        );
        final List<EventoBatida> batidas = r.eventos
            .whereType<EventoBatida>()
            .toList();
        // 2 tempos de "bater o ritmo" = 2 batidas de passo + 2 de percussão.
        expect(batidas.length, 4);

        final Map<int, Set<TipoBatida>> porTique = <int, Set<TipoBatida>>{};
        for (final EventoBatida b in batidas) {
          porTique.putIfAbsent(b.tiqueGlobal, () => <TipoBatida>{}).add(b.tipo);
        }
        // Todo tique de batida tem AS DUAS: passo (de bateRitmo) e percussão.
        expect(porTique.length, 2);
        for (final Set<TipoBatida> tipos in porTique.values) {
          expect(tipos, <TipoBatida>{TipoBatida.passo, TipoBatida.pernaEsquerda});
        }
      },
    );
  });

  group('5 — Junção: bateRitmoAoJuntar e percussão coexistem', () {
    test('bateRitmoAoJuntar: true — no tique da junção há passo E percussão', () {
      final ResultadoSimulacao r = _simularUmSlot(
        Catalogo.alto(bateRitmoAoJuntar: true),
        Cadencia.marchando,
        0,
        percussao: const Percussao(membro: MembroPercussao.mao),
      );
      final List<EventoBatida> batidas = r.eventos.whereType<EventoBatida>().toList();
      // Alto: A(1)·J — junção no último tique (índice 3, 0-based), que é
      // ímpar e portanto também recebe percussão.
      final int tiqueJuncao = r.porTique.length - 1;
      final Set<TipoBatida> noTiqueDaJuncao = batidas
          .where((b) => b.tiqueGlobal == tiqueJuncao)
          .map((b) => b.tipo)
          .toSet();
      expect(noTiqueDaJuncao, <TipoBatida>{TipoBatida.passo, TipoBatida.mao});
    });

    test('bateRitmoAoJuntar: false — só percussão no tique da junção, e ela existe', () {
      final ResultadoSimulacao r = _simularUmSlot(
        Catalogo.alto(),
        Cadencia.marchando,
        0,
        percussao: const Percussao(membro: MembroPercussao.mao),
      );
      final List<EventoBatida> batidas = r.eventos.whereType<EventoBatida>().toList();
      final int tiqueJuncao = r.porTique.length - 1;
      final Set<TipoBatida> noTiqueDaJuncao = batidas
          .where((b) => b.tiqueGlobal == tiqueJuncao)
          .map((b) => b.tipo)
          .toSet();
      expect(noTiqueDaJuncao, <TipoBatida>{TipoBatida.mao});
    });
  });

  group('6 — Rejeição em descansar', () {
    test(
      'movimento que termina em descansar + percussão: diagnóstico, zero '
      'eventos de percussão, porTique bit-idêntico ao da parte sem percussão',
      () {
        final ResultadoSimulacao semPercussao = _simularUmSlot(
          Catalogo.descansar(tempos: 2),
          Cadencia.firme,
          0,
        );
        final ResultadoSimulacao comPercussao = _simularUmSlot(
          Catalogo.descansar(tempos: 2),
          Cadencia.firme,
          0,
          percussao: const Percussao(membro: MembroPercussao.mao),
        );

        expect(comPercussao.porTique.length, semPercussao.porTique.length);
        for (int i = 0; i < semPercussao.porTique.length; i++) {
          expect(comPercussao.porTique[i], semPercussao.porTique[i]);
        }

        expect(comPercussao.eventos.whereType<EventoBatida>().where((e) => e.tipo != TipoBatida.passo), isEmpty);
        expect(
          comPercussao.diagnosticos.whereType<DiagnosticoPercussaoInvalida>(),
          hasLength(1),
        );
      },
    );

    test('entrada JÁ em descansar + percussão também rejeita', () {
      final ResultadoSimulacao r = _simularUmSlot(
        Catalogo.sentido(tempos: 2), // aceita "qualquer" entrada
        Cadencia.descansar,
        0,
        percussao: const Percussao(membro: MembroPercussao.pernaDireita),
      );
      expect(
        r.diagnosticos.whereType<DiagnosticoPercussaoInvalida>(),
        hasLength(1),
      );
      expect(r.eventos.whereType<EventoBatida>().where((e) => e.tipo != TipoBatida.passo), isEmpty);
    });
  });

  group('7 — Comando impossível descarta a percussão junto', () {
    test(
      'slot em firme recebendo "direita volver em marcha" (exige marchando) '
      'com percussão anexada: só o diagnóstico de comando impossível, zero '
      'eventos de percussão',
      () {
        final ResultadoSimulacao r = _simularUmSlot(
          Catalogo.direitaVolverMarcha(),
          Cadencia.firme,
          0,
          percussao: const Percussao(membro: MembroPercussao.mao),
        );
        expect(
          r.diagnosticos.whereType<DiagnosticoComandoImpossivel>(),
          hasLength(1),
        );
        expect(r.diagnosticos.whereType<DiagnosticoPercussaoInvalida>(), isEmpty);
        expect(r.eventos.whereType<EventoBatida>(), isEmpty);
      },
    );
  });

  group('8 — Round-trip JSON', () {
    test('percussão sobrevive ao round-trip', () {
      final Atribuicao a = atribuicaoDoJson(<String, dynamic>{
        'movimento': <String, dynamic>{'tipo': 'baterORitmo', 'tempos': 2},
        'percussao': <String, dynamic>{'membro': 'pernaEsquerda'},
      });
      expect(a.percussao, isNotNull);
      expect(a.percussao!.membro, MembroPercussao.pernaEsquerda);
      expect(a.percussao!.tipoBatida, TipoBatida.pernaEsquerda);
    });

    test('ausente lê null', () {
      final Atribuicao a = atribuicaoDoJson(<String, dynamic>{
        'movimento': <String, dynamic>{'tipo': 'baterORitmo', 'tempos': 2},
      });
      expect(a.percussao, isNull);
    });

    test('membro desconhecido lança FormatException, nunca cai num default', () {
      expect(
        () => atribuicaoDoJson(<String, dynamic>{
          'movimento': <String, dynamic>{'tipo': 'baterORitmo', 'tempos': 2},
          'percussao': <String, dynamic>{'membro': 'peDireito'},
        }),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'message',
            contains('peDireito'),
          ),
        ),
      );
    });
  });

  group('9 — Golden invariante: percussão nunca muda a saída (porTique)', () {
    test(
      'exemplo.json com percussão produz o MESMO porTique que a mesma '
      'evolução com todo campo "percussao" removido — prova mecânica de '
      'que não há bump de catálogo',
      () {
        final File arquivo = File('../../app/assets/evolucoes/exemplo.json');
        final Map<String, dynamic> comPercussao =
            jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>;
        final Map<String, dynamic> semPercussao = _removerPercussao(
          jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>,
        );

        final Evolucao evoCom = evolucaoDoJson(comPercussao);
        final Evolucao evoSem = evolucaoDoJson(semPercussao);

        final ResultadoSimulacao rCom = simular(evoCom.estadoInicial, evoCom.partes);
        final ResultadoSimulacao rSem = simular(evoSem.estadoInicial, evoSem.partes);

        expect(rCom.porTique.length, rSem.porTique.length);
        for (int i = 0; i < rCom.porTique.length; i++) {
          expect(rCom.porTique[i], rSem.porTique[i]);
        }
        expect(versaoCatalogo, 2, reason: 'percussão não bumpa o catálogo');
      },
    );
  });
}

/// Devolve uma cópia profunda do JSON de evolução com todo campo
/// `percussao` removido de toda atribuição — usado só pelo teste 9 (golden
/// invariante) para provar que a saída de tiques é idêntica com/sem
/// percussão.
Map<String, dynamic> _removerPercussao(Map<String, dynamic> evolucaoJson) {
  final Map<String, dynamic> copia =
      jsonDecode(jsonEncode(evolucaoJson)) as Map<String, dynamic>;
  final List<dynamic> partes = copia['partes'] as List<dynamic>;
  for (final dynamic parte in partes) {
    final Map<String, dynamic> atribuicoes =
        (parte as Map<String, dynamic>)['atribuicoes'] as Map<String, dynamic>;
    for (final dynamic atribuicao in atribuicoes.values) {
      (atribuicao as Map<String, dynamic>).remove('percussao');
    }
  }
  return copia;
}
