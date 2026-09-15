import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:evo_app/dados/repositorio_evo.dart';
import 'package:evo_app/dados/repositorio_evo_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _atribuicaoSimples() => <String, dynamic>{
  '0': <String, dynamic>{
    'movimento': <String, dynamic>{'tipo': 'sentido', 'tempos': 2},
  },
};

Map<String, dynamic> _estadoInicialSimples() => <String, dynamic>{
  'slots': <String, dynamic>{
    '0': <String, dynamic>{'linha': 0, 'coluna': 0, 'setor': 0, 'cadencia': 'firme'},
  },
};

void main() {
  late FakeFirebaseFirestore db;
  late RepositorioEvoFirestore repo;
  const String clubId = 'clube-a';

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = RepositorioEvoFirestore(firestore: db, clubId: clubId);
  });

  group('escopo por clube (tenancy nunca aparece no *Doc, mas filtra a leitura)', () {
    test('pelotoes()/evolucoes() só devolvem documentos do clube injetado', () async {
      await db.collection('pelotoes').doc('p-a').set(<String, dynamic>{
        'clubId': clubId,
        'nome': 'Do clube A',
        'linhas': 1,
        'colunas': 1,
        'rotulos': <String, dynamic>{},
        'criadoEm': FieldValue.serverTimestamp(),
        'atualizadoEm': FieldValue.serverTimestamp(),
      });
      await db.collection('pelotoes').doc('p-b').set(<String, dynamic>{
        'clubId': 'outro-clube',
        'nome': 'Do outro clube',
        'linhas': 1,
        'colunas': 1,
        'rotulos': <String, dynamic>{},
        'criadoEm': FieldValue.serverTimestamp(),
        'atualizadoEm': FieldValue.serverTimestamp(),
      });

      final List<PelotaoDoc> pelotoes = await repo.pelotoes().first;
      expect(pelotoes, hasLength(1));
      expect(pelotoes.single.id, 'p-a');
      expect(pelotoes.single.nome, 'Do clube A');
    });
  });

  group('gravarParte — upsert por id, nunca add', () {
    test('grava e depois atualiza o MESMO documento (mesmo id)', () async {
      final ParteDoc parte = ParteDoc(
        id: 'parte-1',
        evolucaoId: 'evo-1',
        ordem: 1.0,
        atribuicoes: _atribuicaoSimples(),
        atualizadoEm: DateTime.now(),
      );
      await repo.gravarParte(parte);
      await repo.gravarParte(parte.copiarCom(ordem: 2.0));

      final QuerySnapshot<Map<String, dynamic>> todas =
          await db.collection('partes').get();
      expect(todas.docs, hasLength(1));
      expect(todas.docs.single.id, 'parte-1');
      expect(todas.docs.single.data()['ordem'], 2.0);
      expect(todas.docs.single.data()['clubId'], clubId);
    });

    test('apagarParte remove o documento', () async {
      await repo.gravarParte(
        ParteDoc(
          id: 'parte-x',
          evolucaoId: 'evo-1',
          ordem: 1.0,
          atribuicoes: _atribuicaoSimples(),
          atualizadoEm: DateTime.now(),
        ),
      );
      await repo.apagarParte('parte-x');
      expect((await db.collection('partes').get()).docs, isEmpty);
    });
  });

  group('gravarEvolucao — criadoEm imutável (a divergência de regra que o '
      'handoff pediu para reportar)', () {
    test('create define criadoEm; update NÃO reenvia criadoEm (só '
        'atualizadoEm muda)', () async {
      final DateTime agora = DateTime.now();
      final EvolucaoDoc doc = EvolucaoDoc(
        id: 'evo-1',
        nome: 'V1',
        pelotaoId: 'pel-1',
        estadoInicial: _estadoInicialSimples(),
        versaoCatalogo: 2,
        criadoEm: agora,
        atualizadoEm: agora,
      );
      await repo.gravarEvolucao(doc);
      final DocumentSnapshot<Map<String, dynamic>> depoisDeCriar =
          await db.collection('evolucoes').doc('evo-1').get();
      final Timestamp criadoEmOriginal = depoisDeCriar.data()!['criadoEm'] as Timestamp;

      // Update: passamos um `criadoEm` local DIFERENTE de propósito (como
      // se a tela tivesse um valor "errado" à mão) — o adaptador deve
      // ignorá-lo e nunca reenviar `criadoEm` no update.
      await repo.gravarEvolucao(
        doc.copiarCom(nome: 'V2', estadoInicial: _estadoInicialSimples()),
      );
      final DocumentSnapshot<Map<String, dynamic>> depoisDeAtualizar =
          await db.collection('evolucoes').doc('evo-1').get();

      expect(depoisDeAtualizar.data()!['nome'], 'V2');
      expect(depoisDeAtualizar.data()!['criadoEm'], criadoEmOriginal);
    });
  });

  group('apagarEvolucao — cascata: partes somem junto, evolução some por último', () {
    test('apaga a evolução e TODAS as partes filhas, nenhum órfão', () async {
      final DateTime agora = DateTime.now();
      await repo.gravarEvolucao(
        EvolucaoDoc(
          id: 'evo-cascata',
          nome: 'Vai ser apagada',
          pelotaoId: 'pel-1',
          estadoInicial: _estadoInicialSimples(),
          versaoCatalogo: 2,
          criadoEm: agora,
          atualizadoEm: agora,
        ),
      );
      for (final String id in <String>['pa', 'pb', 'pc']) {
        await repo.gravarParte(
          ParteDoc(
            id: id,
            evolucaoId: 'evo-cascata',
            ordem: 1.0,
            atribuicoes: _atribuicaoSimples(),
            atualizadoEm: agora,
          ),
        );
      }
      // Parte de OUTRA evolução não deve ser afetada.
      await repo.gravarParte(
        ParteDoc(
          id: 'de-outra-evolucao',
          evolucaoId: 'evo-outra',
          ordem: 1.0,
          atribuicoes: _atribuicaoSimples(),
          atualizadoEm: agora,
        ),
      );

      await repo.apagarEvolucao('evo-cascata');

      expect(
        (await db.collection('evolucoes').doc('evo-cascata').get()).exists,
        isFalse,
      );
      final QuerySnapshot<Map<String, dynamic>> partesRestantes =
          await db.collection('partes').get();
      expect(partesRestantes.docs.map((d) => d.id), <String>['de-outra-evolucao']);
    });
  });

  group('gravarPelotao / apagarPelotao', () {
    // NOTA DE FIDELIDADE DO FAKE: no Firestore de verdade, `.update({'rotulos':
    // novoMapa})` REPLACES o campo `rotulos` inteiro — `.update()` trata cada
    // chave de topo do argumento como um field path a ser SUBSTITUÍDO, não
    // como um merge profundo (isso é `.set(dados, SetOptions(merge: true))`,
    // que `RepositorioEvoFirestore` deliberadamente NÃO usa, justamente para
    // que remover um rótulo remova de verdade — ver o comentário grande no
    // topo de `repositorio_evo_firestore.dart`). `fake_cloud_firestore`
    // 4.2.0, porém, faz merge profundo de mapas aninhados mesmo em
    // `.update()` — diverge do backend real. Por isso este teste verifica o
    // que dá pra verificar sem o emulador de verdade (a chave removida some
    // do INPUT que construímos, e seguiria sumindo no backend real); os 88
    // testes de Security Rules do `backend` (`test/rules/`), esses sim,
    // rodam contra o emulador real.
    test('a segunda gravação envia rotulos SEM a chave removida — a chave '
        'que sobreviveria numa fake com merge profundo simplesmente nunca '
        'está no payload que enviamos', () async {
      final DateTime agora = DateTime.now();
      final PelotaoDoc primeiraVersao = PelotaoDoc(
        id: 'pel-1',
        nome: 'Pelotão',
        linhas: 1,
        colunas: 2,
        rotulos: <String, String>{'0': 'Alfa', '1': 'Bravo'},
        criadoEm: agora,
        atualizadoEm: agora,
      );
      final PelotaoDoc segundaVersao = primeiraVersao.copiarCom(
        rotulos: <String, String>{'0': 'Alfa'}, // "1" removido de propósito
      );

      expect(segundaVersao.paraFirestoreSemTimestamps()['rotulos'], <String, String>{'0': 'Alfa'});
      expect(
        (segundaVersao.paraFirestoreSemTimestamps()['rotulos'] as Map).containsKey('1'),
        isFalse,
      );

      await repo.gravarPelotao(primeiraVersao);
      await repo.gravarPelotao(segundaVersao);
      // Contra o backend real isto seria `{'0': 'Alfa'}` — contra a fake,
      // hoje, é `{'0': 'Alfa', '1': 'Bravo'}` (merge profundo indevido).
      // Deixado documentado em vez de silenciado.
    });

    test('apagarPelotao remove o documento', () async {
      final DateTime agora = DateTime.now();
      await repo.gravarPelotao(
        PelotaoDoc(
          id: 'pel-2',
          nome: 'Pelotão',
          linhas: 1,
          colunas: 1,
          rotulos: const <String, String>{},
          criadoEm: agora,
          atualizadoEm: agora,
        ),
      );
      await repo.apagarPelotao('pel-2');
      expect((await db.collection('pelotoes').doc('pel-2').get()).exists, isFalse);
    });
  });

  group('renormalizarOrdens', () {
    test('renumera as partes de uma evolução para 1.0, 2.0, 3.0... na '
        'ordem (ordem, id) correta', () async {
      final DateTime agora = DateTime.now();
      await repo.gravarParte(
        ParteDoc(
          id: 'terceira',
          evolucaoId: 'evo-r',
          ordem: 100.0,
          atribuicoes: _atribuicaoSimples(),
          atualizadoEm: agora,
        ),
      );
      await repo.gravarParte(
        ParteDoc(
          id: 'primeira',
          evolucaoId: 'evo-r',
          ordem: 0.5,
          atribuicoes: _atribuicaoSimples(),
          atualizadoEm: agora,
        ),
      );
      await repo.gravarParte(
        ParteDoc(
          id: 'segunda',
          evolucaoId: 'evo-r',
          ordem: 0.75,
          atribuicoes: _atribuicaoSimples(),
          atualizadoEm: agora,
        ),
      );

      await repo.renormalizarOrdens('evo-r');

      final List<ParteDoc> resultado = await repo.partes('evo-r').first;
      expect(resultado.map((p) => p.id).toList(), <String>['primeira', 'segunda', 'terceira']);
      expect(resultado.map((p) => p.ordem).toList(), <double>[1.0, 2.0, 3.0]);
    });
  });

  test('novoId() gera ids únicos sem round-trip de rede', () {
    final String a = repo.novoId();
    final String b = repo.novoId();
    expect(a, isNotEmpty);
    expect(b, isNotEmpty);
    expect(a, isNot(b));
  });
}
