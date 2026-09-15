import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:evo_app/dados/repositorio_evo.dart';
import 'package:evo_app/dados/repositorio_evo_firestore.dart';
import 'package:evo_app/dados/validacao_espelho.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// Testes do validador-espelho de `firestore.rules`
// (app/lib/dados/validacao_espelho.dart).
//
// O QUE ELES PROTEGEM: o espelho existe para o app conseguir dizer QUAL
// verificação falhou, já que o Firestore devolve `permission-denied` idêntico
// para "não autorizado" e para "não passou na validação". Um espelho que
// diverge da regra é pior que espelho nenhum — ele afirma com confiança que o
// dado está bom enquanto o servidor recusa.
//
// Os valores de fronteira aqui (24/25 caracteres de rótulo, 6/7 de grid, slot
// 35/36) são os MESMOS exercitados contra a regra real, no emulador, em
// test/rules/rules.test.mjs. Se um lado mudar sem o outro, um dos dois fica
// vermelho.
//
// FIXTURES FICTÍCIAS, como no harness de regras: nenhum apelido real entra
// aqui.

const String clubId = 'clube-a';

PelotaoDoc pelotao({
  String nome = 'Pelotão Exemplo',
  int linhas = 3,
  int colunas = 3,
  Map<String, String> rotulos = const <String, String>{'0': 'Alfa'},
}) => PelotaoDoc(
  id: 'p1',
  nome: nome,
  linhas: linhas,
  colunas: colunas,
  rotulos: rotulos,
  criadoEm: DateTime(2026),
  atualizadoEm: DateTime(2026),
);

EvolucaoDoc evolucao({
  String nome = 'Evolução Exemplo',
  String pelotaoId = 'p1',
  int versaoCatalogo = 2,
  Map<String, dynamic>? estadoInicial,
  CampoDoc? campo,
}) => EvolucaoDoc(
  id: 'e1',
  nome: nome,
  pelotaoId: pelotaoId,
  estadoInicial: estadoInicial ??
      <String, dynamic>{
        'slots': <String, dynamic>{
          '0': <String, dynamic>{'linha': 0, 'coluna': 0, 'setor': 0, 'cadencia': 'firme'},
        },
      },
  campo: campo,
  versaoCatalogo: versaoCatalogo,
  criadoEm: DateTime(2026),
  atualizadoEm: DateTime(2026),
);

ParteDoc parte({
  double ordem = 1,
  String? nome = 'Marcar passo',
  String evolucaoId = 'e1',
  Map<String, dynamic>? atribuicoes,
}) => ParteDoc(
  id: 'pt1',
  evolucaoId: evolucaoId,
  ordem: ordem,
  nome: nome,
  atribuicoes: atribuicoes ??
      <String, dynamic>{
        '0': <String, dynamic>{
          'movimento': <String, dynamic>{'tipo': 'sentido', 'tempos': 2},
        },
      },
  atualizadoEm: DateTime(2026),
);

String texto(int n) => 'a' * n;

void main() {
  group('validarPelotao — espelha pelotaoValido() e rotulosValidos()', () {
    test('o documento que a tela monta no caminho feliz passa', () {
      expect(validarPelotao(pelotao(), clubId: clubId), isNull);
    });

    test('grid 1×1 e grid 6×6 passam; 0 e 7 não', () {
      expect(validarPelotao(pelotao(linhas: 1, colunas: 1), clubId: clubId), isNull);
      expect(validarPelotao(pelotao(linhas: 6, colunas: 6), clubId: clubId), isNull);
      expect(
        validarPelotao(pelotao(linhas: 7), clubId: clubId),
        contains('linhas=7'),
      );
      expect(
        validarPelotao(pelotao(colunas: 0), clubId: clubId),
        contains('colunas=0'),
      );
    });

    test('rótulo de 24 caracteres passa e o de 25 é recusado NOMEANDO o slot', () {
      expect(
        validarPelotao(
          pelotao(rotulos: <String, String>{'12': texto(24)}),
          clubId: clubId,
        ),
        isNull,
      );
      final String? motivo = validarPelotao(
        pelotao(rotulos: <String, String>{'12': texto(27)}),
        clubId: clubId,
      );
      // A mensagem tem que dizer QUAL slot e QUANTOS caracteres — é isso que
      // separa "arrume o rótulo do slot 12" de "confira os campos".
      expect(motivo, contains('slot 12'));
      expect(motivo, contains('27'));
      expect(motivo, contains('24'));
    });

    test('acento não encurta o limite — o espelho conta o que a regra conta', () {
      // Medido no emulador: `size()` das rules conta unidades UTF-16, não
      // bytes UTF-8. 'é' x24 são 48 bytes e a REGRA ACEITA. Se o espelho
      // contasse bytes, recusaria aqui um nome que o servidor gravaria.
      expect(
        validarPelotao(
          pelotao(rotulos: <String, String>{'0': 'é' * 24}),
          clubId: clubId,
        ),
        isNull,
      );
      expect(
        validarPelotao(
          pelotao(rotulos: <String, String>{'0': 'é' * 25}),
          clubId: clubId,
        ),
        isNotNull,
      );
    });

    test('nome de pelotão com 60 caracteres passa; 61 não', () {
      expect(validarPelotao(pelotao(nome: texto(60)), clubId: clubId), isNull);
      expect(
        validarPelotao(pelotao(nome: texto(61)), clubId: clubId),
        contains('61'),
      );
    });

    test('slot 35 é chave válida; 36 e texto não numérico não são', () {
      expect(
        validarPelotao(pelotao(rotulos: <String, String>{'35': 'Zulu'}), clubId: clubId),
        isNull,
      );
      expect(
        validarPelotao(pelotao(rotulos: <String, String>{'36': 'Zulu'}), clubId: clubId),
        contains('36'),
      );
      // O rótulo virar CHAVE é o buraco que o `hasOnly` da regra fecha (um
      // nome de pessoa apareceria em índice e em export).
      expect(
        validarPelotao(pelotao(rotulos: <String, String>{'Alfa': 'x'}), clubId: clubId),
        contains('Alfa'),
      );
    });

    test('chave "07" é recusada — a regra compara a chave como TEXTO', () {
      // `int.tryParse('07')` dá 7, mas '07' não está na lista desenrolada da
      // regra. Sem esta verificação o espelho aprovaria o que o servidor nega.
      expect(
        validarPelotao(pelotao(rotulos: <String, String>{'07': 'Alfa'}), clubId: clubId),
        isNotNull,
      );
    });

    test('grid parcialmente vazio é estado válido, não erro', () {
      expect(
        validarPelotao(
          pelotao(linhas: 6, colunas: 6, rotulos: const <String, String>{}),
          clubId: clubId,
        ),
        isNull,
      );
    });

    test('clubId vazio é nomeado como falta de clube, não como dado inválido', () {
      expect(validarPelotao(pelotao(), clubId: ''), contains('clube'));
    });
  });

  group('validarEvolucao — espelha evolucaoValida(), estadoInicialValido(), campoValido()', () {
    test('caminho feliz passa, inclusive com campo dentro da faixa', () {
      expect(validarEvolucao(evolucao(), clubId: clubId), isNull);
      expect(
        validarEvolucao(
          evolucao(campo: const CampoDoc(larguraCelulas: 200, alturaCelulas: 1)),
          clubId: clubId,
        ),
        isNull,
      );
    });

    test('campo fora da faixa 1..200 é recusado dizendo qual dimensão', () {
      expect(
        validarEvolucao(
          evolucao(campo: const CampoDoc(larguraCelulas: 201, alturaCelulas: 20)),
          clubId: clubId,
        ),
        contains('largura'),
      );
      expect(
        validarEvolucao(
          evolucao(campo: const CampoDoc(larguraCelulas: 20, alturaCelulas: 0)),
          clubId: clubId,
        ),
        contains('altura'),
      );
    });

    test('nome de 80 caracteres passa; 81 não', () {
      expect(validarEvolucao(evolucao(nome: texto(80)), clubId: clubId), isNull);
      expect(validarEvolucao(evolucao(nome: texto(81)), clubId: clubId), isNotNull);
    });

    test('chave de slot inválida em estadoInicial.slots é recusada', () {
      expect(
        validarEvolucao(
          evolucao(estadoInicial: <String, dynamic>{
            'slots': <String, dynamic>{'36': <String, dynamic>{}},
          }),
          clubId: clubId,
        ),
        contains('estadoInicial.slots'),
      );
    });

    test('campo extra em estadoInicial é recusado (hasOnly([\'slots\']))', () {
      expect(
        validarEvolucao(
          evolucao(estadoInicial: <String, dynamic>{
            'slots': <String, dynamic>{},
            'extra': 1,
          }),
          clubId: clubId,
        ),
        contains('extra'),
      );
    });

    test('versaoCatalogo < 1 é recusada', () {
      expect(validarEvolucao(evolucao(versaoCatalogo: 0), clubId: clubId), isNotNull);
    });

    test('pelotaoId vazio é recusado — é imutável depois do create', () {
      expect(
        validarEvolucao(evolucao(pelotaoId: ''), clubId: clubId),
        contains('pelotão'),
      );
    });

    test('o interior dos slots NÃO é validado — o servidor também não valida', () {
      // Espelhar mais que a regra criaria o erro simétrico: o app recusando o
      // que o servidor aceitaria (LIMITAÇÃO CONHECIDA em firestore.rules).
      expect(
        validarEvolucao(
          evolucao(estadoInicial: <String, dynamic>{
            'slots': <String, dynamic>{'0': 'qualquer coisa'},
          }),
          clubId: clubId,
        ),
        isNull,
      );
    });
  });

  group('validarParte — espelha parteValida() e atribuicoesValidas()', () {
    test('caminho feliz passa, inclusive sem nome', () {
      expect(validarParte(parte(), clubId: clubId), isNull);
      expect(validarParte(parte(nome: null), clubId: clubId), isNull);
    });

    test('ordem NaN e infinita são recusadas (a regra reprova as duas)', () {
      expect(validarParte(parte(ordem: double.nan), clubId: clubId), isNotNull);
      expect(validarParte(parte(ordem: double.infinity), clubId: clubId), isNotNull);
    });

    test('ordem fora de ±1e9 é recusada, sugerindo a reordenação', () {
      expect(validarParte(parte(ordem: 1e9), clubId: clubId), isNull);
      expect(
        validarParte(parte(ordem: 1e9 + 1), clubId: clubId),
        contains('Reordenar'),
      );
    });

    test('nome de 60 caracteres passa; 61 não', () {
      expect(validarParte(parte(nome: texto(60)), clubId: clubId), isNull);
      expect(validarParte(parte(nome: texto(61)), clubId: clubId), isNotNull);
    });

    test('chave de slot inválida em atribuicoes é recusada', () {
      expect(
        validarParte(
          parte(atribuicoes: <String, dynamic>{'99': <String, dynamic>{}}),
          clubId: clubId,
        ),
        contains('atribuicoes'),
      );
    });
  });

  group('o repositório reprova ANTES da rede e carrega a causa no erro', () {
    late FakeFirebaseFirestore db;
    late RepositorioEvoFirestore repo;

    setUp(() {
      db = FakeFirebaseFirestore();
      repo = RepositorioEvoFirestore(firestore: db, clubId: clubId);
    });

    test('gravarPelotao com rótulo longo falha com o slot nomeado, e nada é escrito', () async {
      // `fake_cloud_firestore` NÃO avalia Security Rules — é justamente por
      // isso que este teste prova o ponto: a recusa aqui só pode ter vindo do
      // validador-espelho, antes de qualquer ida à rede.
      await expectLater(
        repo.gravarPelotao(pelotao(rotulos: <String, String>{'12': texto(27)})),
        throwsA(
          isA<ErroPersistencia>().having(
            (ErroPersistencia e) => (e.falha as DocumentoInvalido).detalhe,
            'detalhe',
            allOf(contains('slot 12'), contains('27')),
          ),
        ),
      );
      final QuerySnapshot<Map<String, dynamic>> gravados =
          await db.collection('pelotoes').get();
      expect(gravados.docs, isEmpty);
    });

    test('gravarEvolucao e gravarParte também reprovam com causa específica', () async {
      await expectLater(
        repo.gravarEvolucao(evolucao(nome: texto(81))),
        throwsA(
          isA<ErroPersistencia>().having(
            (ErroPersistencia e) => (e.falha as DocumentoInvalido).detalhe,
            'detalhe',
            contains('81'),
          ),
        ),
      );
      await expectLater(
        repo.gravarParte(parte(ordem: double.nan)),
        throwsA(
          isA<ErroPersistencia>().having(
            (ErroPersistencia e) => (e.falha as DocumentoInvalido).detalhe,
            'detalhe',
            isNotNull,
          ),
        ),
      );
    });

    test('o documento válido continua sendo gravado normalmente', () async {
      await repo.gravarPelotao(pelotao(linhas: 6, colunas: 6));
      final QuerySnapshot<Map<String, dynamic>> gravados =
          await db.collection('pelotoes').get();
      expect(gravados.docs, hasLength(1));
      expect(gravados.docs.single.data()['linhas'], 6);
    });
  });
}
