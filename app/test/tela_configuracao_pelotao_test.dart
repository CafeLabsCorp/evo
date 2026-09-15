import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:evo_app/dados/repositorio_evo.dart';
import 'package:evo_app/dados/repositorio_evo_firestore.dart';
import 'package:evo_app/telas/tela_configuracao_pelotao.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore db;
  late RepositorioEvo repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = RepositorioEvoFirestore(firestore: db, clubId: 'clube-teste');
  });

  Future<void> abrirTela(WidgetTester tester, {PelotaoDoc? existente}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    TelaConfiguracaoPelotao(repo: repo, pelotaoExistente: existente),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  group('microcopy de compliance — fixo, sempre visível junto do grid', () {
    testWidgets('o texto de orientação aparece sem nenhuma ação do usuário', (
      WidgetTester tester,
    ) async {
      await abrirTela(tester);
      expect(
        find.textContaining('Use apelido ou primeiro nome'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Não use nome completo, idade, contato'),
        findsOneWidget,
      );
    });
  });

  group('teto de 24 caracteres por rótulo — reflexo do que a regra do '
      'servidor também impõe', () {
    testWidgets('digitar mais de 24 caracteres num slot trunca em 24, não '
        'só na tela: o Salvar também respeita o teto', (
      WidgetTester tester,
    ) async {
      await abrirTela(tester);

      // TextField 0 é o nome do pelotão; TextField 1 é o slot 0 (grid
      // 3×3 default, primeiro item de `GridView.builder`).
      final Finder campoSlot0 = find.byType(TextField).at(1);
      await tester.enterText(campoSlot0, 'Um nome bem longo demais para um apelido');
      await tester.pump();

      final TextField widget = tester.widget<TextField>(campoSlot0);
      expect(widget.controller!.text.length, lessThanOrEqualTo(24));

      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      final QuerySnapshot<Map<String, dynamic>> pelotoes =
          await db.collection('pelotoes').get();
      expect(pelotoes.docs, hasLength(1));
      final String rotuloGravado = (pelotoes.docs.single.data()['rotulos']
          as Map<String, dynamic>)['0'] as String;
      expect(rotuloGravado.length, lessThanOrEqualTo(24));
    });
  });

  group('salvar — cria o pelotão e some da tela (não fica "renderizando o '
      'que acabou de escrever")', () {
    testWidgets('grid 3×3 default, sem rótulos: salva com rotulos vazio e '
        'volta para a tela anterior', (WidgetTester tester) async {
      await abrirTela(tester);

      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      // Voltou: a tela de trás ("abrir") está de volta na árvore.
      expect(find.text('abrir'), findsOneWidget);
      expect(find.byType(TelaConfiguracaoPelotao), findsNothing);

      final QuerySnapshot<Map<String, dynamic>> pelotoes =
          await db.collection('pelotoes').get();
      expect(pelotoes.docs, hasLength(1));
      expect(pelotoes.docs.single.data()['linhas'], 3);
      expect(pelotoes.docs.single.data()['colunas'], 3);
      expect(pelotoes.docs.single.data()['clubId'], 'clube-teste');
    });
  });

  group('apagar pelotão (Etapa 5) — exige confirmação explícita', () {
    testWidgets('editando um pelotão existente, apagar some com o '
        'documento depois de confirmado', (WidgetTester tester) async {
      final DateTime agora = DateTime.now();
      final PelotaoDoc existente = PelotaoDoc(
        id: repo.novoId(),
        nome: 'Para apagar',
        linhas: 1,
        colunas: 1,
        rotulos: const <String, String>{'0': 'Alfa'},
        criadoEm: agora,
        atualizadoEm: agora,
      );
      await repo.gravarPelotao(existente);

      await abrirTela(tester, existente: existente);

      await tester.tap(find.byTooltip('Apagar pelotão'));
      await tester.pumpAndSettle();
      expect(find.text('Apagar pelotão?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Apagar'));
      await tester.pumpAndSettle();

      expect(
        (await db.collection('pelotoes').doc(existente.id).get()).exists,
        isFalse,
      );
    });
  });
}
