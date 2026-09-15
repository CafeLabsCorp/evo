import 'package:cloud_firestore/cloud_firestore.dart';

import '../dados/falha_persistencia.dart';
import '../dados/repositorio_evo.dart' show ErroPersistencia;
import 'modelo_clube.dart';

/// Descoberta e bootstrap de clube — deliberadamente FORA de
/// `RepositorioEvo`: `clubes/{clubId}` é o documento de AUTORIZAÇÃO (quem
/// pode ler/escrever o quê), não um dado de domínio que a tela de
/// evolução/pelotão manipula. Ver `firestore.rules` — é por isso, também,
/// que não existe `usuarios/{uid}` neste schema.
class ServicoClube {
  ServicoClube({required FirebaseFirestore firestore}) : _db = firestore;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _clubes =>
      _db.collection('clubes');

  /// Descoberta multi-tenant: `where('membrosAtivos.<uid>', '==', true)` é
  /// equality num subcampo de mapa — auto-indexada, sem precisar de nenhum
  /// índice composto em `firestore.indexes.json`. Em v1 (single-user, e a
  /// trava de `membrosAtivos.keys().size() == 1` na regra) o resultado tem
  /// no máximo 1 documento; a assinatura já é lista para não exigir
  /// reescrita quando clubes multiusuário permitirem alguém pertencer a
  /// mais de um.
  Stream<List<ClubeResumo>> meusClubes(String uid) => _clubes
      .where('membrosAtivos.$uid', isEqualTo: true)
      .snapshots()
      .map(
        (QuerySnapshot<Map<String, dynamic>> s) => <ClubeResumo>[
          for (final QueryDocumentSnapshot<Map<String, dynamic>> d in s.docs)
            ClubeResumo.doSnapshot(d),
        ],
      )
      .handleError((Object erro, StackTrace pilha) {
        throw ErroPersistencia(falhaPersistenciaDe(erro), causa: erro);
      });

  /// Bootstrap IDEMPOTENTE do clube no primeiro login: se [uid] já é
  /// membro ativo de algum clube, devolve o id dele sem escrever nada; caso
  /// contrário cria um clube novo com [uid] como dono e único membro
  /// ativo — a única forma que passa em `membrosAtivosValidos()`
  /// (`membrosAtivos.keys().size() == 1`).
  ///
  /// `clubId` é auto-id, NUNCA `uid`: usar o uid como id do clube parece
  /// inofensivo ("uma pessoa, um clube") e quebra no primeiro cenário de
  /// posse compartilhada ou transferência — `clubId == uid` viraria uma
  /// mentira gravada em todo documento filho.
  ///
  /// Nome default "Clube Exemplo": não existe, nesta versão, uma tela de
  /// "nomear seu clube" no primeiro login (fora do escopo da Etapa 2/4do
  /// handoff) — e é também o nome fictício exigido enquanto não há dado
  /// real (ver docs/DADOS.md, Gatilho 2). Quando um segundo usuário de
  /// verdade entrar (Gatilho 1), vale revisitar isto com um passo real de
  /// onboarding.
  ///
  /// NÃO é atômico contra um duplo-clique/duas abas chamando ao mesmo
  /// tempo (faria uma leitura, veria "não existe", e as duas criariam um
  /// clube cada). Aceitável em single-user: só há uma pessoa disparando
  /// isto, uma vez, no primeiro login — documentado aqui como limitação
  /// conhecida, não descuido.
  Future<String> bootstrap({required String uid}) async {
    try {
      final QuerySnapshot<Map<String, dynamic>> existentes = await _clubes
          .where('membrosAtivos.$uid', isEqualTo: true)
          .limit(1)
          .get();
      if (existentes.docs.isNotEmpty) return existentes.docs.first.id;

      final DocumentReference<Map<String, dynamic>> ref = _clubes.doc();
      await ref.set(<String, dynamic>{
        'nome': 'Clube Exemplo',
        'dono': uid,
        'membros': <String, dynamic>{
          uid: <String, dynamic>{'estado': 'ativo', 'papel': 'instrutor'},
        },
        'membrosAtivos': <String, dynamic>{uid: true},
        'criadoEm': FieldValue.serverTimestamp(),
      });
      return ref.id;
    } catch (erro) {
      throw ErroPersistencia(falhaPersistenciaDe(erro), causa: erro);
    }
  }
}
