import 'dart:convert';
import 'dart:io';

import 'package:evo_app/modelo/carregador_evolucao.dart';
import 'package:evo_app/pintura/formacao_painter.dart';
import 'package:evo_app/playback/controlador_playback.dart';
import 'package:evo_app/telas/tela_playback.dart';
import 'package:evo_motor/evo_motor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// `TickerProvider` mínimo pra construir um [ControladorPlayback] fora de
/// uma árvore de widgets — estes testes não precisam de nenhum frame real
/// rodando (não chamam `tocar()`), só de acesso à API pública de
/// interpolação (`estadosRenderizados`/`mudarParaTique`).
class _VSyncFake implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

void main() {
  group(
    'ControladorPlayback._batidasPerto (via estadosRenderizados) — teste 11',
    () {
      test(
        'tique de coexistência (Alto com bateRitmoAoJuntar + percussão de mão) '
        'devolve um conjunto de 2 tipos de batida',
        () {
          final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
            0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.marchando),
          });
          final Parte parte = Parte(
            ordem: 0,
            atribuicoes: <int, Atribuicao>{
              0: Atribuicao(
                movimento: Catalogo.alto(bateRitmoAoJuntar: true),
                percussao: const Percussao(membro: MembroPercussao.mao),
              ),
            },
          );
          final Evolucao evolucao = Evolucao(
            nome: 'teste',
            estadoInicial: inicial,
            partes: <Parte>[parte],
          );
          final ResultadoSimulacao resultado = simular(inicial, <Parte>[parte]);
          final PacoteEvolucao pacote = PacoteEvolucao(
            evolucao: evolucao,
            resultado: resultado,
          );

          final ControladorPlayback controlador = ControladorPlayback(
            pacote: pacote,
            vsync: _VSyncFake(),
          );
          addTearDown(controlador.dispose);

          // Alto: A(1)·J — 4 tiques (índices 0..3 em `porTique`). A junção
          // bate no último tique (`tiqueGlobal == 3`); a percussão cobre
          // TODO T (0..3), inclusive o índice 3 (ímpar) — coincidem no
          // mesmo tique. `_batidasPerto` compara `_tiqueAtual` diretamente
          // contra `tiqueGlobal` (mesma escala 0-based da lista de
          // eventos) — não a escala "1 = após o 1º tique" usada por
          // `_combinados`/interpolação de posição.
          const int tiqueGlobalDaJuncao = 3;
          controlador.mudarParaTique(tiqueGlobalDaJuncao.toDouble());

          final EstadoRenderizado estadoSlot0 = controlador
              .estadosRenderizados()
              .firstWhere((e) => e.slot == 0);

          expect(estadoSlot0.batidas, hasLength(2));
          expect(estadoSlot0.batidas, <TipoBatida>{
            TipoBatida.passo,
            TipoBatida.mao,
          });
        },
      );

      test('tique sem nenhuma batida por perto devolve conjunto vazio', () {
        final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
          0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.firme),
        });
        final Parte parte = Parte(
          ordem: 0,
          atribuicoes: <int, Atribuicao>{
            0: Atribuicao(movimento: Catalogo.sentido(tempos: 4)),
          },
        );
        final Evolucao evolucao = Evolucao(
          nome: 'teste',
          estadoInicial: inicial,
          partes: <Parte>[parte],
        );
        final ResultadoSimulacao resultado = simular(inicial, <Parte>[parte]);
        final PacoteEvolucao pacote = PacoteEvolucao(
          evolucao: evolucao,
          resultado: resultado,
        );
        final ControladorPlayback controlador = ControladorPlayback(
          pacote: pacote,
          vsync: _VSyncFake(),
        );
        addTearDown(controlador.dispose);

        controlador.mudarParaTique(0);
        final EstadoRenderizado estado = controlador
            .estadosRenderizados()
            .firstWhere((e) => e.slot == 0);
        expect(estado.batidas, isEmpty);
      });
    },
  );

  group(
    'tipoBatidaParaDesenhar — regra de precedência de pintura como função pura (teste 11)',
    () {
      test('conjunto vazio: nada para desenhar', () {
        expect(tipoBatidaParaDesenhar(<TipoBatida>{}), isNull);
      });

      test('só passo: desenha passo (anel completo)', () {
        expect(
          tipoBatidaParaDesenhar(<TipoBatida>{TipoBatida.passo}),
          TipoBatida.passo,
        );
      });

      for (final TipoBatida percussao in <TipoBatida>[
        TipoBatida.mao,
        TipoBatida.pernaEsquerda,
        TipoBatida.pernaDireita,
      ]) {
        test('só $percussao: desenha $percussao', () {
          expect(
            tipoBatidaParaDesenhar(<TipoBatida>{percussao}),
            percussao,
          );
        });

        test(
          'passo + $percussao (coexistência): percussão sobrepõe passo',
          () {
            expect(
              tipoBatidaParaDesenhar(<TipoBatida>{TipoBatida.passo, percussao}),
              percussao,
            );
          },
        );
      }
    },
  );

  group('Legenda de percussão no HUD (TelaPlayback)', () {
    Future<PacoteEvolucao> carregarExemplo() async {
      final String texto = await File(
        'assets/evolucoes/exemplo.json',
      ).readAsString();
      final Evolucao evolucao = evolucaoDoJson(
        jsonDecode(texto) as Map<String, dynamic>,
      );
      return PacoteEvolucao(
        evolucao: evolucao,
        resultado: simular(evolucao.estadoInicial, evolucao.partes),
      );
    }

    testWidgets(
      'parte "Marcha diagonal" (percussão em marcha, pernaDireita) mostra a legenda em texto',
      (WidgetTester tester) async {
        final PacoteEvolucao pacote = await tester.runAsync(carregarExemplo)
            as PacoteEvolucao;
        await tester.pumpWidget(
          MaterialApp(
            home: TelaPlayback(
              caminhoAsset: 'assets/evolucoes/exemplo.json',
              carregarParaTeste: () async => pacote,
            ),
          ),
        );
        for (int i = 0; i < 30; i++) {
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
          await tester.pump(const Duration(milliseconds: 50));
        }

        await tester.tap(find.text('Parte isolada'));
        await tester.pump();
        // "Marcha diagonal" é a 5ª parte (ordem 4) no JSON de exemplo.
        await tester.tap(find.text('5'));
        await tester.pump();

        expect(find.textContaining('perna direita'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.pause_circle_filled));
        await tester.pump();
      },
    );

    testWidgets(
      'parte sem percussão nenhuma (ex.: parte 1) não mostra a legenda',
      (WidgetTester tester) async {
        final PacoteEvolucao pacote = await tester.runAsync(carregarExemplo)
            as PacoteEvolucao;
        await tester.pumpWidget(
          MaterialApp(
            home: TelaPlayback(
              caminhoAsset: 'assets/evolucoes/exemplo.json',
              carregarParaTeste: () async => pacote,
            ),
          ),
        );
        for (int i = 0; i < 30; i++) {
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
          await tester.pump(const Duration(milliseconds: 50));
        }

        await tester.tap(find.text('Parte isolada'));
        await tester.pump();
        await tester.tap(find.text('1'));
        await tester.pump();

        expect(find.textContaining('mão'), findsNothing);
        expect(find.textContaining('perna'), findsNothing);

        await tester.tap(find.byIcon(Icons.pause_circle_filled));
        await tester.pump();
      },
    );
  });
}
