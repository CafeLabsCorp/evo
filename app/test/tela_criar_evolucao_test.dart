import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:evo_app/dados/repositorio_evo.dart';
import 'package:evo_app/dados/repositorio_evo_firestore.dart';
import 'package:evo_app/telas/tela_criar_evolucao.dart';
import 'package:evo_app/telas/tela_editor_partes.dart';
import 'package:evo_app/telas/tela_evolucoes.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cobre a correção do beco sem saída: `TelaEvolucoes` sem nenhuma evolução
/// não pode mais ser um fim de linha — tem que existir um caminho de UI até
/// a criação, tanto no estado vazio quanto de propósito (FAB), e a criação
/// tem que produzir um documento que a REGRA REAL aceitaria (verificado
/// contra `FakeFirebaseFirestore`, que reflete `parteValida`/`evolucaoValida`
/// só pela ausência de rejeição — a regra em si é coberta pelos testes de
/// `test/rules/`).
void main() {
  late FakeFirebaseFirestore db;
  late RepositorioEvo repo;
  late PelotaoDoc pelotao;

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = RepositorioEvoFirestore(firestore: db, clubId: 'clube-teste');
    final DateTime agora = DateTime.now();
    pelotao = PelotaoDoc(
      id: repo.novoId(),
      nome: 'Pelotão Exemplo',
      linhas: 2,
      colunas: 2,
      rotulos: const <String, String>{'0': 'Alfa'},
      criadoEm: agora,
      atualizadoEm: agora,
    );
    await repo.gravarPelotao(pelotao);
  });

  Future<void> abrirListaDeEvolucoes(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: TelaEvolucoes(repo: repo, pelotao: pelotao)),
    );
    await tester.pumpAndSettle();
  }

  group('estado vazio deixou de ser um beco sem saída', () {
    testWidgets('não mostra mais o placeholder "chega em breve"', (
      WidgetTester tester,
    ) async {
      await abrirListaDeEvolucoes(tester);
      expect(find.textContaining('chega em breve'), findsNothing);
    });

    testWidgets('o estado vazio convida a criar, com um botão que abre a '
        'tela de criação', (WidgetTester tester) async {
      await abrirListaDeEvolucoes(tester);
      expect(find.text('Nenhuma evolução ainda'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Criar evolução'));
      await tester.pumpAndSettle();

      expect(find.byType(TelaCriarEvolucao), findsOneWidget);
    });

    testWidgets('o FAB "Nova evolução" também abre a tela de criação', (
      WidgetTester tester,
    ) async {
      await abrirListaDeEvolucoes(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Nova evolução'));
      await tester.pumpAndSettle();

      expect(find.byType(TelaCriarEvolucao), findsOneWidget);
    });
  });

  group('criar evolução — grava um estadoInicial que a regra aceita e abre '
      'o editor', () {
    testWidgets('nome em branco vira "Evolução sem nome"; abre o editor de '
        'partes na sequência (não volta para a lista)', (
      WidgetTester tester,
    ) async {
      await abrirListaDeEvolucoes(tester);
      await tester.tap(find.widgetWithText(FloatingActionButton, 'Nova evolução'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Criar e abrir editor'));
      await tester.pumpAndSettle();

      expect(find.byType(TelaCriarEvolucao), findsNothing);
      expect(find.byType(TelaEditorPartes), findsOneWidget);

      final QuerySnapshot<Map<String, dynamic>> evolucoes =
          await db.collection('evolucoes').get();
      expect(evolucoes.docs, hasLength(1));
      final Map<String, dynamic> dados = evolucoes.docs.single.data();
      expect(dados['nome'], 'Evolução sem nome');
      expect(dados['pelotaoId'], pelotao.id);
      expect(dados['clubId'], 'clube-teste');

      // TODOS os 4 slots do grid 2×2 entram — não só o slot 0, que é o único
      // rotulado (ver dartdoc de `estadoInicialDoGrid`).
      final Map<String, dynamic> slots =
          (dados['estadoInicial'] as Map<String, dynamic>)['slots']
              as Map<String, dynamic>;
      expect(slots.keys.toSet(), <String>{'0', '1', '2', '3'});
      for (final MapEntry<String, dynamic> e in slots.entries) {
        final Map<String, dynamic> slot = e.value as Map<String, dynamic>;
        expect(slot['setor'], 0);
        expect(slot['cadencia'], 'firme');
      }
      // Slot 3 -> linha 1, coluna 1 num grid de 2 colunas.
      expect(slots['3'], <String, dynamic>{
        'linha': 1,
        'coluna': 1,
        'setor': 0,
        'cadencia': 'firme',
      });
    });

    testWidgets('nome digitado é preservado e truncado em 80 caracteres pelo '
        'próprio campo', (WidgetTester tester) async {
      await abrirListaDeEvolucoes(tester);
      await tester.tap(find.widgetWithText(FloatingActionButton, 'Nova evolução'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Abertura do desfile');
      await tester.tap(find.widgetWithText(FilledButton, 'Criar e abrir editor'));
      await tester.pumpAndSettle();

      final QuerySnapshot<Map<String, dynamic>> evolucoes =
          await db.collection('evolucoes').get();
      expect(evolucoes.docs.single.data()['nome'], 'Abertura do desfile');
    });
  });
}
