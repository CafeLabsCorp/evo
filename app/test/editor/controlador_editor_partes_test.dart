import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:evo_app/dados/controle_edicao.dart';
import 'package:evo_app/dados/duplicar_evolucao.dart';
import 'package:evo_app/dados/repositorio_evo.dart';
import 'package:evo_app/dados/repositorio_evo_firestore.dart';
import 'package:evo_app/editor/controlador_editor_partes.dart';
import 'package:evo_app/editor/descritores_movimento.dart';
import 'package:evo_motor/evo_motor.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore db;
  late RepositorioEvo repo;
  late String pelotaoId;
  late String evolucaoId;

  Map<String, dynamic> estadoInicial5x5Firme() => <String, dynamic>{
    'slots': <String, dynamic>{
      for (int i = 0; i < 25; i++)
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
        linhas: 5,
        colunas: 5,
        rotulos: const <String, String>{'0': 'Alfa-1'},
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
        estadoInicial: estadoInicial5x5Firme(),
        versaoCatalogo: versaoCatalogo,
        criadoEm: agora,
        atualizadoEm: agora,
      ),
    );
  });

  Future<ControladorEditorPartes> montarControlador({
    Duration debounce = Duration.zero,
  }) async {
    final ControladorEditorPartes c = ControladorEditorPartes(
      repo: repo,
      evolucaoId: evolucaoId,
      duracaoDebounce: debounce,
    );
    c.atualizarEvolucao(await repo.evolucao(evolucaoId).first);
    c.atualizarPelotao(await repo.pelotao(pelotaoId).first);
    c.atualizarPartes(await repo.partes(evolucaoId).first);
    c.atualizarDono(DonoDaTrava.minha);
    return c;
  }

  group('geometria do grid — slot é identidade, layout fixo por índice', () {
    test('linha/coluna derivadas de colunas do pelotão (5×5)', () async {
      final ControladorEditorPartes c = await montarControlador();
      expect(c.linhaDoSlot(0), 0);
      expect(c.colunaDoSlot(0), 0);
      expect(c.linhaDoSlot(5), 1);
      expect(c.colunaDoSlot(5), 0);
      expect(c.linhaDoSlot(24), 4);
      expect(c.colunaDoSlot(24), 4);
      expect(c.slotDe(1, 0), 5);
    });
  });

  group('seleção — chips substituem, toque individual é aditivo', () {
    test('selecionarFileira substitui a seleção corrente pela fileira inteira', () async {
      final ControladorEditorPartes c = await montarControlador();
      c.alternarSlot(20); // um slot fora da fileira 0, pra provar substituição.
      c.selecionarFileira(0);
      expect(c.selecionados, unorderedEquals(<int>[0, 1, 2, 3, 4]));
    });

    test('alternarSlot é aditivo (toggle) dentro da seleção corrente', () async {
      final ControladorEditorPartes c = await montarControlador();
      c.selecionarFileira(0);
      c.alternarSlot(10);
      expect(c.selecionados, unorderedEquals(<int>[0, 1, 2, 3, 4, 10]));
      c.alternarSlot(10);
      expect(c.selecionados, unorderedEquals(<int>[0, 1, 2, 3, 4]));
    });

    test('inverter inverte a seleção corrente sobre os 25 slots', () async {
      final ControladorEditorPartes c = await montarControlador();
      c.selecionarFileira(0);
      c.inverterSelecao();
      expect(c.selecionados, hasLength(20));
      expect(c.selecionados, isNot(contains(0)));
      expect(c.selecionados, contains(24));
    });
  });

  group('painel filtrado — nunca oferece um movimento inválido para a '
      'cadência corrente', () {
    test('parte 1 (tudo firme no estadoInicial): só os 10 válidos de firme', () async {
      final ControladorEditorPartes c = await montarControlador();
      await c.adicionarParteVazia();
      c.atualizarPartes(await repo.partes(evolucaoId).first);
      c.selecionarParte(0);
      c.selecionarFileira(0);
      expect(c.movimentosValidos, hasLength(10));
      expect(
        c.movimentosValidos.map((MovimentoValido m) => m.descritor.tipo),
        isNot(contains('alto')),
      );
    });
  });

  group('aplicar movimento — escreve granular, respeita debounce, nunca '
      'renderiza antes de escrever (buffer só pré-escrita)', () {
    test('escolher um movimento grava a parte com a atribuição certa (debounce zero)', () async {
      final ControladorEditorPartes c = await montarControlador();
      await c.adicionarParteVazia();
      c.atualizarPartes(await repo.partes(evolucaoId).first);
      final String parteId = c.partes.single.id;
      c.selecionarParte(0);
      c.selecionarFileira(0);
      c.escolherMovimento('sentido');
      c.definirQuantidade(4);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final DocumentSnapshot<Map<String, dynamic>> doc = await db
          .collection('partes')
          .doc(parteId)
          .get();
      final Map<String, dynamic> atribs = doc.data()!['atribuicoes'] as Map<String, dynamic>;
      for (int slot = 0; slot < 5; slot++) {
        final Map<String, dynamic> a = atribs['$slot'] as Map<String, dynamic>;
        expect((a['movimento'] as Map<String, dynamic>)['tipo'], 'sentido');
        expect((a['movimento'] as Map<String, dynamic>)['tempos'], 4);
      }
      // Ajustar 3 vezes seguidas (movimento, depois quantidade) — dentro do
      // mesmo debounce — ainda é UMA escrita granular por parte, nunca uma
      // por toque: confirmado indiretamente pelo doc final acima já refletir
      // o ÚLTIMO estado, sem exceção por escritas concorrentes.
    });

    test('continuação implícita: slot fora da seleção nunca ganha atribuicao', () async {
      final ControladorEditorPartes c = await montarControlador();
      await c.adicionarParteVazia();
      c.atualizarPartes(await repo.partes(evolucaoId).first);
      final String parteId = c.partes.single.id;
      c.selecionarParte(0);
      c.selecionarFileira(0); // só slots 0..4
      c.escolherMovimento('sentido');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final DocumentSnapshot<Map<String, dynamic>> doc = await db
          .collection('partes')
          .doc(parteId)
          .get();
      final Map<String, dynamic> atribs = doc.data()!['atribuicoes'] as Map<String, dynamic>;
      expect(atribs.containsKey('10'), isFalse);
      // Regra de disciplina #3: só depois que a tela recebe o snapshot de
      // volta do stream (aqui, simulado por `atualizarPartes`) é que
      // `recebeuAtribuicaoNestaParte` reflete a escrita — nunca antes.
      c.atualizarPartes(await repo.partes(evolucaoId).first);
      expect(c.recebeuAtribuicaoNestaParte(0), isTrue);
      expect(c.recebeuAtribuicaoNestaParte(10), isFalse);
    });

    test('percussão fica desabilitada quando o movimento é Descansar', () async {
      final ControladorEditorPartes c = await montarControlador();
      await c.adicionarParteVazia();
      c.atualizarPartes(await repo.partes(evolucaoId).first);
      c.selecionarParte(0);
      c.selecionarFileira(0);
      c.escolherMovimento('descansar');
      expect(c.percussaoDesabilitada, isTrue);
    });

    test('debounce coalesce múltiplos ajustes rápidos numa escrita só', () async {
      final ControladorEditorPartes c = await montarControlador(
        debounce: const Duration(milliseconds: 200),
      );
      await c.adicionarParteVazia();
      c.atualizarPartes(await repo.partes(evolucaoId).first);
      final String parteId = c.partes.single.id;
      c.selecionarParte(0);
      c.selecionarFileira(0);
      c.escolherMovimento('emFrenteMarche');
      c.definirQuantidade(2);
      c.definirQuantidade(4);
      c.definirAoTerminar(AoTerminarMarche.firme);

      // Antes do debounce disparar, o documento no "servidor" (fake, sem
      // pending writes reais) ainda não tem a atribuição.
      final DocumentSnapshot<Map<String, dynamic>> antes = await db
          .collection('partes')
          .doc(parteId)
          .get();
      expect((antes.data()!['atribuicoes'] as Map<String, dynamic>).containsKey('0'), isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 350));

      final DocumentSnapshot<Map<String, dynamic>> depois = await db
          .collection('partes')
          .doc(parteId)
          .get();
      final Map<String, dynamic> a0 =
          (depois.data()!['atribuicoes'] as Map<String, dynamic>)['0'] as Map<String, dynamic>;
      expect((a0['movimento'] as Map<String, dynamic>)['n'], 4);
      expect((a0['movimento'] as Map<String, dynamic>)['aoTerminar'], 'firme');
    });
  });

  group('undo em memória — inverso de gravar é gravar o anterior', () {
    test('desfazer restaura as atribuições de antes da última ação', () async {
      final ControladorEditorPartes c = await montarControlador();
      await c.adicionarParteVazia();
      c.atualizarPartes(await repo.partes(evolucaoId).first);
      final String parteId = c.partes.single.id;
      c.selecionarParte(0);
      c.selecionarFileira(0);
      c.escolherMovimento('sentido');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      c.atualizarPartes(await repo.partes(evolucaoId).first);

      expect(c.temUndo, isTrue);
      await c.desfazer();

      final DocumentSnapshot<Map<String, dynamic>> doc = await db
          .collection('partes')
          .doc(parteId)
          .get();
      expect((doc.data()!['atribuicoes'] as Map<String, dynamic>), isEmpty);
    });
  });

  group('duplicar parte', () {
    test('copia atribuicoes cruas para uma parte nova, inserida depois', () async {
      final ControladorEditorPartes c = await montarControlador();
      await c.adicionarParteVazia();
      c.atualizarPartes(await repo.partes(evolucaoId).first);
      c.selecionarParte(0);
      c.selecionarFileira(0);
      c.escolherMovimento('sentido');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      c.atualizarPartes(await repo.partes(evolucaoId).first);

      final ParteDoc copia = await c.duplicarParte(0);
      expect(copia.atribuicoes, isNotEmpty);
      expect(copia.ordem, greaterThan(c.partes[0].ordem));
    });
  });

  group('subgrupos salvos e nomeáveis (session-only)', () {
    test('salvar e reaplicar um subgrupo', () async {
      final ControladorEditorPartes c = await montarControlador();
      c.selecionarFileira(1);
      c.salvarSubgrupoAtual('Bravo');
      c.limparSelecao();
      expect(c.selecionados, isEmpty);
      c.aplicarSubgrupo('Bravo');
      expect(c.selecionados, unorderedEquals(<int>[5, 6, 7, 8, 9]));
    });
  });

  group('cadência mista — dividir seleção por estado em 1 toque', () {
    test('reduz a seleção ao maior subconjunto homogêneo', () async {
      final ControladorEditorPartes c = await montarControlador();
      await c.adicionarParteVazia();
      c.atualizarPartes(await repo.partes(evolucaoId).first);
      c.selecionarParte(0);
      // Slots 0..2 recebem "em frente, marche" terminando marchando; 3..4
      // ficam em continuação (firme, do estadoInicial).
      c.alternarSlot(0);
      c.alternarSlot(1);
      c.alternarSlot(2);
      c.escolherMovimento('emFrenteMarche');
      c.definirAoTerminar(AoTerminarMarche.marchando);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      c.atualizarPartes(await repo.partes(evolucaoId).first);

      // Nova parte: 0..2 agora marchando (da parte anterior), 3..4 firme.
      await c.adicionarParteVazia();
      c.atualizarPartes(await repo.partes(evolucaoId).first);
      c.selecionarParte(1);
      c.selecionarFileira(0); // slots 0..4, cadência mista.
      expect(c.selecaoTemCadenciaMista, isTrue);
      c.dividirSelecaoPorEstado();
      expect(c.selecaoTemCadenciaMista, isFalse);
      expect(c.selecionados, unorderedEquals(<int>[0, 1, 2]));
    });
  });

  group('duplicar evolução para outro pelotão — create, nunca update', () {
    test('copia estadoInicial e partes com pelotaoId novo, sem tocar a original', () async {
      await repo.gravarParte(
        ParteDoc(
          id: repo.novoId(),
          evolucaoId: evolucaoId,
          ordem: 1,
          atribuicoes: <String, dynamic>{
            '0': <String, dynamic>{
              'movimento': <String, dynamic>{'tipo': 'sentido', 'tempos': 2},
            },
          },
          atualizadoEm: DateTime.now(),
        ),
      );
      final DateTime agora = DateTime.now();
      final String outroPelotaoId = repo.novoId();
      await repo.gravarPelotao(
        PelotaoDoc(
          id: outroPelotaoId,
          nome: 'Pelotão Novo',
          linhas: 5,
          colunas: 5,
          rotulos: const <String, String>{},
          criadoEm: agora,
          atualizadoEm: agora,
        ),
      );

      final String novaEvolucaoId = await duplicarEvolucaoParaPelotao(
        repo: repo,
        evolucaoId: evolucaoId,
        pelotaoIdDestino: outroPelotaoId,
      );

      expect(novaEvolucaoId, isNot(evolucaoId));
      final EvolucaoDoc? nova = await repo.evolucao(novaEvolucaoId).first;
      expect(nova!.pelotaoId, outroPelotaoId);
      expect(nova.estadoInicial, estadoInicial5x5Firme());

      final List<ParteDoc> partesNovas = await repo.partes(novaEvolucaoId).first;
      expect(partesNovas, hasLength(1));
      expect(partesNovas.single.atribuicoes, isNotEmpty);

      // Original intacta — nunca um update.
      final EvolucaoDoc? original = await repo.evolucao(evolucaoId).first;
      expect(original!.pelotaoId, pelotaoId);
    });
  });
}
