import 'dart:convert';
import 'dart:io';

import 'package:evo_app/main.dart';
import 'package:evo_app/modelo/carregador_evolucao.dart';
import 'package:evo_app/pintura/formacao_painter.dart';
import 'package:evo_app/telas/tela_playback.dart';
import 'package:evo_motor/evo_motor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// Espera o `FutureBuilder` de carregamento resolver, sem usar
/// `pumpAndSettle()` — a tela tem um `Ticker` de playback que, uma vez
/// tocando, agenda frames continuamente por design (é uma animação real),
/// então `pumpAndSettle()` pode nunca "assentar" depois de um play. Pumps
/// discretos são o jeito certo de testar uma tela com animação contínua.
Future<void> _esperarCarregar(WidgetTester tester) async {
  for (int i = 0; i < 30; i++) {
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lê e simula o JSON de exemplo direto do disco, sem passar pelo
/// `rootBundle` — usado só pelos testes de INTERAÇÃO (play/pause, faixa,
/// scrub), que não precisam repetir o caminho de I/O de asset a cada
/// teste (esse já tem cobertura dedicada em
/// "carrega o asset de exemplo do rootBundle...", abaixo).
Future<PacoteEvolucao> _carregarPacoteDeTeste() async {
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

void main() {
  testWidgets(
    'carrega o asset de exemplo do rootBundle e mostra o playback pronto',
    (WidgetTester tester) async {
      await tester.pumpWidget(const EvoApp());

      // Estado de carregamento primeiro — cobre o caminho real de I/O (o
      // único do app inteiro), sem mock.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await _esperarCarregar(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
      expect(find.text('Evolução completa'), findsOneWidget);
    },
  );

  testWidgets(
    'JSON inexistente mostra a tela de erro, não uma tela em branco',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TelaPlayback(caminhoAsset: 'assets/evolucoes/nao-existe.json'),
        ),
      );
      await _esperarCarregar(tester);

      expect(find.textContaining('Não deu pra carregar'), findsOneWidget);
    },
  );

  group(
    'interação de playback (evolução pré-carregada do disco, sem rootBundle)',
    () {
      // `File.readAsString` é I/O real (fora da zona de fake-async do
      // `testWidgets`) — precisa rodar dentro de `tester.runAsync`, senão
      // nenhuma quantidade de `pump()` a resolve (só flush de microtask,
      // não do event loop de verdade). Pré-carregamos aqui, fora da árvore,
      // e injetamos como um Future já pronto — mesmo formato que
      // `carregarEvolucaoDoAsset` resolve no caminho real (via `rootBundle`,
      // que em teste é microtask-only e por isso não precisa de `runAsync`).
      Future<void> montar(WidgetTester tester) async {
        final PacoteEvolucao pacote =
            await tester.runAsync(_carregarPacoteDeTeste) as PacoteEvolucao;
        await tester.pumpWidget(
          MaterialApp(
            home: TelaPlayback(
              caminhoAsset: 'assets/evolucoes/exemplo.json',
              carregarParaTeste: () async => pacote,
            ),
          ),
        );
        await _esperarCarregar(tester);
      }

      // Usado tanto pelo grupo de opções de grade quanto pelo de
      // enquadramento/escala, abaixo — por isso vive no escopo do grupo
      // externo, não de um dos dois internos.
      FormacaoPainter painterAtual(WidgetTester tester) =>
          tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((CustomPaint cp) => cp.painter)
              .whereType<FormacaoPainter>()
              .single;

      testWidgets('play alterna pra pause e o tique avança', (
        WidgetTester tester,
      ) async {
        await montar(tester);

        expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
        await tester.tap(find.byIcon(Icons.play_circle_filled));
        await tester.pump();
        expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);

        // Deixa alguns frames rodarem — o tique deve avançar.
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));

        // Pausa de novo pra não deixar o Ticker rodando quando o teste acaba.
        await tester.tap(find.byIcon(Icons.pause_circle_filled));
        await tester.pump();
        expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
      });

      testWidgets(
        'toque numa bolinha em modo evolução completa começa o playback '
        'a partir daquela parte, não do início',
        (WidgetTester tester) async {
          await montar(tester);

          // Modo default é evolução completa — controle inequívoco visível.
          expect(find.text('Evolução completa'), findsOneWidget);
          expect(find.text('Parte isolada'), findsOneWidget);

          final Slider antes = tester.widget<Slider>(find.byType(Slider));
          expect(antes.value, 0);

          // Bolinha "2" (segunda parte) — a fileira tem uma bolinha
          // numerada por parte, ligada por setas.
          await tester.tap(find.text('2'));
          await tester.pump();

          // O toque já inicia o playback sozinho — não fica só selecionado.
          expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);

          final Slider depois = tester.widget<Slider>(find.byType(Slider));
          // Começou a partir da parte 2 (tique > 0), não do início.
          expect(depois.value, greaterThan(0));
          // O intervalo do slider continua sendo a evolução inteira — só
          // o ponto de partida do playhead mudou, o modo não virou
          // "parte isolada".
          expect(depois.min, 0);
          expect(find.text('Evolução completa'), findsOneWidget);

          // Pausa pra não deixar o Ticker rodando quando o teste acabar.
          await tester.tap(find.byIcon(Icons.pause_circle_filled));
          await tester.pump();
        },
      );

      testWidgets(
        'modo "parte isolada": toque numa bolinha restringe o playback a '
        'ela, sem tocar o resto da evolução',
        (WidgetTester tester) async {
          await montar(tester);

          await tester.tap(find.text('Parte isolada'));
          await tester.pump();

          await tester.tap(find.text('3'));
          await tester.pump();

          expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);

          final Slider slider = tester.widget<Slider>(find.byType(Slider));
          // Intervalo restrito à parte 3 — não é mais 0..fim da evolução.
          expect(slider.min, greaterThan(0));
          expect(slider.value, slider.min);

          await tester.tap(find.byIcon(Icons.pause_circle_filled));
          await tester.pump();
        },
      );

      testWidgets('scrub move o tique sem precisar tocar play', (
        WidgetTester tester,
      ) async {
        await montar(tester);

        final Slider slider = tester.widget<Slider>(find.byType(Slider));
        expect(slider.value, 0);

        await tester.drag(find.byType(Slider), const Offset(200, 0));
        await tester.pump();

        final Slider depois = tester.widget<Slider>(find.byType(Slider));
        expect(depois.value, greaterThan(0));
        // Continua pausado — mover o slider não deve iniciar o playback.
        expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
      });

      testWidgets('sair da tela enquanto toca não deixa Ticker pendurado', (
        WidgetTester tester,
      ) async {
        await montar(tester);

        await tester.tap(find.byIcon(Icons.play_circle_filled));
        await tester.pump();

        // Troca a árvore por algo em branco — força o dispose da tela (e do
        // seu Ticker) enquanto ele ainda estava tocando.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        expect(SchedulerBinding.instance.transientCallbackCount, 0);
      });

      group('grade — linhas e pontos são dois toggles independentes', () {
        testWidgets('padrão: pontos ligados, linhas desligadas', (
          WidgetTester tester,
        ) async {
          await montar(tester);

          final FormacaoPainter painter = painterAtual(tester);
          expect(painter.mostrarPontos, isTrue);
          expect(painter.mostrarLinhas, isFalse);
        });

        testWidgets(
          'abrir as opções de grade e ligar as linhas não desliga os '
          'pontos — controle independente',
          (WidgetTester tester) async {
            await montar(tester);

            await tester.tap(find.byTooltip('Opções de grade'));
            await tester.pumpAndSettle();

            expect(find.text('Linhas'), findsOneWidget);
            expect(find.text('Pontos'), findsOneWidget);

            await tester.tap(find.widgetWithText(SwitchListTile, 'Linhas'));
            await tester.pumpAndSettle();

            // Fecha o bottom sheet pra inspecionar o painter por trás dele.
            Navigator.of(tester.element(find.text('Linhas'))).pop();
            await tester.pumpAndSettle();

            final FormacaoPainter painter = painterAtual(tester);
            expect(painter.mostrarLinhas, isTrue);
            expect(painter.mostrarPontos, isTrue);
          },
        );

        testWidgets(
          'os quatro estados funcionam, inclusive ambos desligados '
          '(fundo limpo)',
          (WidgetTester tester) async {
            await montar(tester);

            await tester.tap(find.byTooltip('Opções de grade'));
            await tester.pumpAndSettle();

            // Desliga os pontos (ligados por padrão) sem mexer nas linhas.
            await tester.tap(find.widgetWithText(SwitchListTile, 'Pontos'));
            await tester.pumpAndSettle();

            Navigator.of(tester.element(find.text('Pontos'))).pop();
            await tester.pumpAndSettle();

            final FormacaoPainter painter = painterAtual(tester);
            expect(painter.mostrarLinhas, isFalse);
            expect(painter.mostrarPontos, isFalse);
          },
        );
      });

      group(
        'enquadramento — bounding box de conteúdo, não do campo 20×20 '
        'inteiro (correção de 2026-09-14)',
        () {
          testWidgets(
            'evolução completa: enquadra a faixa de tiques inteira, bem '
            'menor que o campo 20×20 default',
            (WidgetTester tester) async {
              await montar(tester);

              // Medido direto do motor pra este JSON de exemplo (ver
              // `_carregarPacoteDeTeste` acima): linha [-8, 9], coluna
              // [0, 6] — bem menor que o campo default (linha/coluna
              // -10..10). Regressão: com o bug antigo (célula fixa de
              // 36px, sem enquadramento) boa parte disso já não cabia num
              // retrato de celular.
              final FormacaoPainter painter = painterAtual(tester);
              expect(
                painter.enquadramento,
                const Rect.fromLTRB(0, -8, 6, 9),
              );
            },
          );

          testWidgets(
            'o enquadramento não muda tique a tique durante o playback — '
            'a câmera não deve pular a cada frame',
            (WidgetTester tester) async {
              await montar(tester);
              final Rect antes = painterAtual(tester).enquadramento;

              await tester.tap(find.byIcon(Icons.play_circle_filled));
              for (int i = 0; i < 5; i++) {
                await tester.pump(const Duration(milliseconds: 100));
                expect(painterAtual(tester).enquadramento, antes);
              }

              await tester.tap(find.byIcon(Icons.pause_circle_filled));
              await tester.pump();
            },
          );

          testWidgets(
            'parte isolada "marcha diagonal" (única em que só uma fileira '
            'se desloca): enquadra o deslocamento inteiro daquela parte, '
            'não o tique atual nem a evolução completa',
            (WidgetTester tester) async {
              await montar(tester);

              await tester.tap(find.text('Parte isolada'));
              await tester.pump();
              // "Marcha diagonal" é a 5ª parte (ordem 4) no JSON de
              // exemplo.
              await tester.tap(find.text('5'));
              await tester.pump();

              // Medido direto do motor: linha [-7.5, 8.0], coluna
              // [0.0, 5.5] — cobre o deslocamento inteiro da fileira ao
              // longo da parte toda, não só onde ela está no tique em que
              // o playback foi iniciado.
              final FormacaoPainter painter = painterAtual(tester);
              expect(
                painter.enquadramento,
                const Rect.fromLTRB(0, -7.5, 5.5, 8),
              );

              await tester.tap(find.byIcon(Icons.pause_circle_filled));
              await tester.pump();
            },
          );
        },
      );
    },
  );
}
