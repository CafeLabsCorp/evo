import 'package:cloud_firestore/cloud_firestore.dart';

import 'ordenacao_partes.dart';
import 'repositorio_evo.dart';
import 'validacao_espelho.dart';

/// Implementação de [RepositorioEvo] sobre Firestore, escopada a UM clube.
///
/// `clubId` é injetado aqui no construtor — nunca aparece nos `*Doc` que a
/// tela manipula (regra de disciplina #6). Uma instância desta classe só
/// enxerga o clube com que foi construída; trocar de clube (não suportado
/// nesta versão single-user) significa construir outra instância.
///
/// -----------------------------------------------------------------------
/// SOBRE `criadoEm`/`atualizadoEm` NUNCA VIREM DO MODELO DIRETO
/// -----------------------------------------------------------------------
/// `evolucoes` e `pelotoes` têm `criadoEm` IMUTÁVEL
/// (`inalterado('criadoEm')` em `firestore.rules`). Reenviar
/// `FieldValue.serverTimestamp()` a cada `gravar*` (inclusive em updates)
/// pareceria inofensivo e QUEBRARIA a regra: o servidor resolve
/// `serverTimestamp()` para o instante da escrita ANTES de avaliar a regra,
/// então `next().criadoEm` (agora) nunca bate com `prev().criadoEm`
/// (quando o documento foi criado) — toda atualização seria rejeitada.
///
/// A alternativa óbvia — reenviar o `criadoEm` que a TELA recebeu de volta
/// do stream — tem um problema mais sutil: em Flutter Web, `DateTime` tem
/// precisão de MILISSEGUNDO (herda do `Date` do JS), enquanto `Timestamp`
/// do Firestore tem precisão de nanossegundo. Um `Timestamp` gravado pelo
/// servidor com sub-milissegundo não-zero, convertido para `DateTime`
/// (`.toDate()`) e de volta para `Timestamp` (`Timestamp.fromDate(...)`),
/// NÃO reproduz o valor original — e `inalterado('criadoEm')` compara
/// igualdade exata. Esse round-trip rejeitaria a escrita silenciosamente
/// na primeira edição de um pelotão/evolução recém-criado.
///
/// A solução aqui é não fazer nenhum dos dois: toda escrita de
/// evolução/pelotão passa por uma TRANSAÇÃO que decide sozinha, olhando o
/// servidor, se é create (define `criadoEm` uma única vez) ou update (nunca
/// toca em `criadoEm` — `.update()` com um mapa que não inclui a chave
/// simplesmente não mexe nela, o que satisfaz `inalterado` trivialmente).
/// `EvolucaoDoc`/`PelotaoDoc` nunca precisam carregar um `Timestamp` cru
/// para isso funcionar.
///
/// -----------------------------------------------------------------------
/// A TRANSAÇÃO LÊ ANTES DE ESCREVER — e isso tem duas consequências
/// -----------------------------------------------------------------------
/// 1. A REGRA DE LEITURA PRECISA ACEITAR DOCUMENTO INEXISTENTE. No create,
///    `tx.get(ref)` cai num documento que ainda não existe, onde `resource`
///    é null do lado da regra. Enquanto `firestore.rules` tinha
///    `allow read: if membroAtivo(resource.data.clubId)`, esse `get` dava
///    erro de avaliação e era NEGADO — a transação abortava antes de a
///    regra de create sequer rodar, e criar pelotão/evolução era impossível
///    com qualquer conteúdo. Hoje existe `podeObterDocumentoDeClube()` lá
///    justamente para este caso. Se alguém "simplificar" aquela regra de
///    volta, este caminho quebra inteiro de novo.
///
/// 2. UM ERRO DENTRO DO CALLBACK CHEGA AQUI DESFIGURADO, em Flutter Web.
///    `firebase_core_web` transforma a exceção Dart lançada dentro do
///    callback num `Error` de JS com a mensagem `'Dart exception: ...'` e o
///    objeto original enfiado numa propriedade. Na volta,
///    `_flutterfire_internals` não reconhece isso como erro do Firebase
///    (não contém `FirebaseError`), então NÃO reconverte — e o app recebe um
///    objeto de JS cru no lugar do `FirebaseException`. Resultado: um
///    `permission-denied` legítimo caía no `default` de
///    `falhaPersistenciaDe` e era exibido como "o dado não passou na
///    validação do servidor", que é uma mentira sobre a causa.
///    [_transacao] existe para consertar isso: guarda a exceção original
///    antes de ela cruzar a fronteira para o JS e a relança intacta.
class RepositorioEvoFirestore implements RepositorioEvo {
  RepositorioEvoFirestore({required FirebaseFirestore firestore, required this.clubId})
    : _db = firestore;

  final FirebaseFirestore _db;
  final String clubId;

  CollectionReference<Map<String, dynamic>> get _evolucoes =>
      _db.collection('evolucoes');
  CollectionReference<Map<String, dynamic>> get _partes =>
      _db.collection('partes');
  CollectionReference<Map<String, dynamic>> get _pelotoes =>
      _db.collection('pelotoes');

  // ---- leitura -----------------------------------------------------------

  @override
  Stream<List<ResumoEvolucao>> evolucoes() => _protegido(
    _evolucoes
        .where('clubId', isEqualTo: clubId)
        .orderBy('atualizadoEm', descending: true)
        .snapshots()
        .map(
          (QuerySnapshot<Map<String, dynamic>> s) => <ResumoEvolucao>[
            for (final QueryDocumentSnapshot<Map<String, dynamic>> d in s.docs)
              ResumoEvolucao.doSnapshot(d),
          ],
        ),
  );

  @override
  Stream<EvolucaoDoc?> evolucao(String id) => _protegido(
    _evolucoes.doc(id).snapshots().map(
      (DocumentSnapshot<Map<String, dynamic>> d) =>
          d.exists ? EvolucaoDoc.doSnapshot(d) : null,
    ),
  );

  @override
  Stream<List<ParteDoc>> partes(String evolucaoId) => _protegido(
    _partes
        .where('clubId', isEqualTo: clubId)
        .where('evolucaoId', isEqualTo: evolucaoId)
        .orderBy('ordem')
        .snapshots()
        .map(
          (QuerySnapshot<Map<String, dynamic>> s) => ordenarPartesDoc(<ParteDoc>[
            for (final QueryDocumentSnapshot<Map<String, dynamic>> d in s.docs)
              ParteDoc.doSnapshot(d),
          ]),
        ),
  );

  @override
  Stream<PelotaoDoc?> pelotao(String id) => _protegido(
    _pelotoes.doc(id).snapshots().map(
      (DocumentSnapshot<Map<String, dynamic>> d) =>
          d.exists ? PelotaoDoc.doSnapshot(d) : null,
    ),
  );

  @override
  Stream<List<PelotaoDoc>> pelotoes() => _protegido(
    _pelotoes.where('clubId', isEqualTo: clubId).snapshots().map((
      QuerySnapshot<Map<String, dynamic>> s,
    ) {
      final List<PelotaoDoc> lista = <PelotaoDoc>[
        for (final QueryDocumentSnapshot<Map<String, dynamic>> d in s.docs)
          PelotaoDoc.doSnapshot(d),
      ];
      // Sem índice composto para isto (só equality em `clubId`, que é
      // auto-indexado) — ordenação por nome é cliente, e é barato: um
      // clube single-user não tem dezenas de pelotões.
      lista.sort((PelotaoDoc a, PelotaoDoc b) => a.nome.compareTo(b.nome));
      return lista;
    }),
  );

  // ---- escrita: partes -----------------------------------------------------

  @override
  Future<void> gravarParte(ParteDoc parte) => _executar(() async {
    _exigirValido(validarParte(parte, clubId: clubId));
    await _partes.doc(parte.id).set(<String, dynamic>{
      'clubId': clubId,
      ...parte.paraFirestoreSemTimestamp(),
      'atualizadoEm': FieldValue.serverTimestamp(),
    });
  });

  @override
  Future<void> apagarParte(String parteId) =>
      _executar(() => _partes.doc(parteId).delete());

  // ---- escrita: evolucoes ---------------------------------------------------

  @override
  Future<void> gravarEvolucao(EvolucaoDoc doc) => _executar(() async {
    _exigirValido(validarEvolucao(doc, clubId: clubId));
    final DocumentReference<Map<String, dynamic>> ref = _evolucoes.doc(doc.id);
    await _transacao((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> atual = await tx.get(ref);
      final Map<String, dynamic> campos = <String, dynamic>{
        'clubId': clubId,
        ...doc.paraFirestoreSemTimestamps(),
      };
      if (!atual.exists) {
        tx.set(ref, <String, dynamic>{
          ...campos,
          'criadoEm': FieldValue.serverTimestamp(),
          'atualizadoEm': FieldValue.serverTimestamp(),
        });
      } else {
        // `.update()` substitui só os campos de topo listados — omitir
        // `criadoEm` aqui é o que faz `inalterado('criadoEm')` passar (ver
        // o comentário longo no topo do arquivo).
        tx.update(ref, <String, dynamic>{
          ...campos,
          'atualizadoEm': FieldValue.serverTimestamp(),
        });
      }
    });
  });

  @override
  Future<void> apagarEvolucao(String id) => _executar(() async {
    // Cascata: partes ANTES do documento da evolução (docs/DADOS.md, seção
    // 4 — inverter deixa órfãos inalcançáveis).
    final QuerySnapshot<Map<String, dynamic>> filhas = await _partes
        .where('clubId', isEqualTo: clubId)
        .where('evolucaoId', isEqualTo: id)
        .get();
    await _apagarEmLotes(<DocumentReference<Map<String, dynamic>>>[
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d in filhas.docs)
        d.reference,
      _evolucoes.doc(id),
    ]);
  });

  // ---- escrita: pelotoes -----------------------------------------------------

  @override
  Future<void> gravarPelotao(PelotaoDoc doc) => _executar(() async {
    _exigirValido(validarPelotao(doc, clubId: clubId));
    final DocumentReference<Map<String, dynamic>> ref = _pelotoes.doc(doc.id);
    await _transacao((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> atual = await tx.get(ref);
      final Map<String, dynamic> campos = <String, dynamic>{
        'clubId': clubId,
        ...doc.paraFirestoreSemTimestamps(),
      };
      if (!atual.exists) {
        tx.set(ref, <String, dynamic>{
          ...campos,
          'criadoEm': FieldValue.serverTimestamp(),
          'atualizadoEm': FieldValue.serverTimestamp(),
        });
      } else {
        tx.update(ref, <String, dynamic>{
          ...campos,
          'atualizadoEm': FieldValue.serverTimestamp(),
        });
      }
    });
  });

  @override
  Future<void> apagarPelotao(String id) =>
      _executar(() => _pelotoes.doc(id).delete());

  // ---- ids e reordenação -----------------------------------------------------

  @override
  String novoId() => _evolucoes.doc().id;

  @override
  Future<void> renormalizarOrdens(String evolucaoId) => _executar(() async {
    final QuerySnapshot<Map<String, dynamic>> snap = await _partes
        .where('clubId', isEqualTo: clubId)
        .where('evolucaoId', isEqualTo: evolucaoId)
        .orderBy('ordem')
        .get();
    final List<ParteDoc> ordenadas = ordenarPartesDoc(<ParteDoc>[
      for (final QueryDocumentSnapshot<Map<String, dynamic>> d in snap.docs)
        ParteDoc.doSnapshot(d),
    ]);
    WriteBatch lote = _db.batch();
    int operacoesNoLote = 0;
    for (int i = 0; i < ordenadas.length; i++) {
      lote.update(_partes.doc(ordenadas[i].id), <String, dynamic>{
        'ordem': (i + 1).toDouble(),
        'atualizadoEm': FieldValue.serverTimestamp(),
      });
      operacoesNoLote++;
      if (operacoesNoLote == 450) {
        await lote.commit();
        lote = _db.batch();
        operacoesNoLote = 0;
      }
    }
    if (operacoesNoLote > 0) await lote.commit();
  });

  // ---- helpers internos -----------------------------------------------------

  /// Barra a escrita ANTES da rede quando o validador-espelho
  /// (`validacao_espelho.dart`) reprova, carregando no erro a verificação
  /// exata que falhou.
  ///
  /// Não é só conforto: é o que dá sentido à mensagem de [SemPermissao]. Como
  /// o Firestore devolve `permission-denied` igual para "não autorizado" e
  /// para "não passou na regra", eliminar o segundo caso aqui é a única forma
  /// de o app afirmar "é autorização" sem estar chutando.
  void _exigirValido(String? motivo) {
    if (motivo != null) {
      throw ErroPersistencia(DocumentoInvalido(motivo));
    }
  }

  /// `runTransaction` que preserva a exceção ORIGINAL levantada dentro do
  /// callback.
  ///
  /// Sem isto, em Flutter Web, o `FirebaseException(permission-denied)` que
  /// `tx.get`/`tx.set` levantam é embrulhado num `Error` de JS na travessia
  /// Dart -> JS e volta irreconhecível (ver o bloco longo no topo da classe) —
  /// o app perde o código do erro e passa a exibir a causa errada. Guardar a
  /// exceção numa variável local antes da travessia e relançá-la aqui é o que
  /// mantém `falhaPersistenciaDe` recebendo o erro de verdade.
  Future<void> _transacao(Future<void> Function(Transaction tx) corpo) async {
    Object? erroInterno;
    StackTrace? pilhaInterna;
    try {
      await _db.runTransaction((Transaction tx) async {
        // Zerado a cada tentativa: `runTransaction` re-executa o callback em
        // caso de contenção, e um erro de uma tentativa anterior que acabou
        // dando certo não pode sobreviver até o fim.
        erroInterno = null;
        pilhaInterna = null;
        try {
          await corpo(tx);
        } catch (erro, pilha) {
          erroInterno = erro;
          pilhaInterna = pilha;
          rethrow;
        }
      });
    } catch (_) {
      final Object? erro = erroInterno;
      final StackTrace? pilha = pilhaInterna;
      // `erro == null` significa que a falha foi no COMMIT, não no callback —
      // esse caminho não cruza a fronteira do JS desfigurado, então o erro que
      // já veio é o bom.
      if (erro == null) rethrow;
      Error.throwWithStackTrace(erro, pilha ?? StackTrace.current);
    }
  }

  Future<void> _apagarEmLotes(
    List<DocumentReference<Map<String, dynamic>>> refs,
  ) async {
    // Teto de 500 operações por WriteBatch do Firestore; 450 dá folga.
    for (int inicio = 0; inicio < refs.length; inicio += 450) {
      final WriteBatch lote = _db.batch();
      for (final DocumentReference<Map<String, dynamic>> ref in refs.skip(inicio).take(450)) {
        lote.delete(ref);
      }
      await lote.commit();
    }
  }

  Stream<T> _protegido<T>(Stream<T> origem) => origem.handleError((
    Object erro,
    StackTrace pilha,
  ) {
    throw ErroPersistencia(falhaPersistenciaDe(erro), causa: erro);
  });

  Future<T> _executar<T>(Future<T> Function() acao) async {
    try {
      return await acao();
    } catch (erro) {
      if (erro is ErroPersistencia) rethrow;
      throw ErroPersistencia(falhaPersistenciaDe(erro), causa: erro);
    }
  }
}
