import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:evo_app/dados/controle_edicao.dart';
import 'package:evo_app/dados/repositorio_evo.dart';
import 'package:evo_app/dados/repositorio_evo_firestore.dart';
import 'package:evo_app/editor/pintura_slot_editor.dart';
import 'package:evo_app/telas/tela_editor_partes.dart';
import 'package:evo_motor/evo_motor.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';

/// `BehaviorSubject` (não um `StreamController.broadcast` cru) porque quem
/// assina precisa receber o valor CORRENTE na hora de assinar, não só
/// eventos futuros — exatamente a mesma forma que uma trava real com
/// presença se comportaria (`dono()` é consultado a qualquer momento, não
/// só logo após uma mudança).
class _ControleFake implements ControleDeEdicao {
  final BehaviorSubject<DonoDaTrava> _sujeito = BehaviorSubject<DonoDaTrava>.seeded(
    DonoDaTrava.minha,
  );

  void definir(DonoDaTrava d) => _sujeito.add(d);

  @override
  Stream<DonoDaTrava> dono() => _sujeito.stream;

  @override
  Future<bool> pedir() async => true;
}

void main() {
  late FakeFirebaseFirestore db;
  late RepositorioEvo repo;
  late String pelotaoId;
  late String evolucaoId;
  late String parteId;

  Map<String, dynamic> estadoInicial3x3() => <String, dynamic>{
    'slots': <String, dynamic>{
      for (int i = 0; i < 9; i++)
        '$i': <String, dynamic>{'linha': 0, 'coluna': 0, 'setor': 0, 'cadencia': 'firme'},
    },
  };

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = RepositorioEvoFirestore(firestore: db, clubId: 'clube-teste');
    final DateTime agora = DateTime.now();
    pelotaoId = repo.novoId();
    await repo.gravarPelotao(
      PelotaoDoc(
        id: pelotaoId,
        nome: 'Pelotão Exemplo',
        linhas: 3,
        colunas: 3,
        rotulos: const <String, String>{'0': 'Alfa'},
        criadoEm: agora,
        atualizadoEm: agora,
      ),
    );
    evolucaoId = repo.novoId();
    await repo.gravarEvolucao(
      EvolucaoDoc(
        id: evolucaoId,
        nome: 'Evolução Exemplo',
        pelotaoId: pelotaoId,
        estadoInicial: estadoInicial3x3(),
        versaoCatalogo: versaoCatalogo,
        criadoEm: agora,
        atualizadoEm: agora,
      ),
    );
    parteId = repo.novoId();
    await repo.gravarParte(
      ParteDoc(
        id: parteId,
        evolucaoId: evolucaoId,
        ordem: 1,
        atribuicoes: const <String, dynamic>{},
        atualizadoEm: agora,
      ),
    );
  });

  Future<void> abrirTela(WidgetTester tester, {ControleDeEdicao? controle}) async {
    // Largura ampla (desktop/tablet-paisagem) — o alvo primário do editor,
    // ver dartdoc de `_AreaDeEdicao`: acima de 900px o painel fica inline,
    // sem precisar abrir o bottom sheet.
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: TelaEditorPartes(
          repo: repo,
          evolucaoId: evolucaoId,
          controleEdicao: controle ?? const TravaSempreMinha(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('carregamento e grid', () {
    testWidgets('mostra o grid 3×3 com o rótulo do slot 0', (WidgetTester tester) async {
      await abrirTela(tester);
      expect(find.text('Alfa'), findsOneWidget);
      expect(find.text('Slot 1'), findsOneWidget);
    });
  });

  group('seleção + painel filtrado + aplicação ao vivo', () {
    testWidgets('selecionar fileira 1 e escolher "Sentido" grava a atribuição na parte', (
      WidgetTester tester,
    ) async {
      await abrirTela(tester);

      await tester.tap(find.widgetWithText(ActionChip, 'Fileira 1'));
      await tester.pumpAndSettle();

      // Painel filtrado: só os 10 válidos de firme aparecem, "Alto" não.
      expect(find.widgetWithText(ChoiceChip, 'Sentido'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Alto'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Sentido'));
      await tester.pumpAndSettle();

      final DocumentSnapshot<Map<String, dynamic>> doc = await db
          .collection('partes')
          .doc(parteId)
          .get();
      final Map<String, dynamic> atribs = doc.data()!['atribuicoes'] as Map<String, dynamic>;
      expect(atribs.containsKey('0'), isTrue);
      expect(atribs.containsKey('3'), isFalse); // fora da fileira 1.
    });

    testWidgets('quadrado de continuação aparece só em quem recebeu atribuição nesta parte', (
      WidgetTester tester,
    ) async {
      await abrirTela(tester);
      await tester.tap(find.widgetWithText(ActionChip, 'Fileira 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Sentido'));
      await tester.pumpAndSettle();

      final List<SlotEditorPainter> pintores = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((CustomPaint c) => c.painter)
          .whereType<SlotEditorPainter>()
          .toList();
      // 3 slots da fileira 1 receberam atribuição explícita nesta parte;
      // os 6 restantes continuam em continuação implícita.
      expect(pintores.where((SlotEditorPainter p) => p.recebeuInstrucao).length, 3);
      expect(pintores.where((SlotEditorPainter p) => !p.recebeuInstrucao).length, 6);
    });
  });

  group('trava — modo somente leitura', () {
    testWidgets('banner aparece e o painel fica desabilitado quando a trava é de outra pessoa', (
      WidgetTester tester,
    ) async {
      final _ControleFake controle = _ControleFake()..definir(DonoDaTrava.deOutraPessoa);
      await abrirTela(tester, controle: controle);

      expect(find.textContaining('Outra pessoa está editando'), findsOneWidget);

      await tester.tap(find.widgetWithText(ActionChip, 'Fileira 1'));
      await tester.pumpAndSettle();
      // Chips de seleção continuam visíveis (útil para inspecionar o
      // estado travado), mas nenhum toque no GRID muda a seleção enquanto
      // travado — ver `_CelulaSlot.onTap: controlador.podeEditar ? ... :
      // null`. O painel de atribuição nunca chega a aparecer porque a
      // seleção nunca sai de vazio.
      expect(find.textContaining('selecionado(s)'), findsNothing);
      expect(
        find.text(
          'Selecione alguém no grid (ou use os chips de fileira/coluna) para '
          'ver os movimentos disponíveis.',
        ),
        findsOneWidget,
      );
    });
  });

  group('microcopy de compliance do rótulo — herdada de TelaConfiguracaoPelotao', () {
    testWidgets('rótulos do grid nunca mostram mais que o apelido configurado', (
      WidgetTester tester,
    ) async {
      await abrirTela(tester);
      // O editor não tem campo de digitação de rótulo (isso é
      // responsabilidade de `TelaConfiguracaoPelotao`, já coberta em
      // `tela_configuracao_pelotao_test.dart`) — aqui só confirmamos que o
      // editor EXIBE o rótulo já validado, nunca um dado bruto adicional.
      expect(find.text('Alfa'), findsOneWidget);
    });
  });
}
