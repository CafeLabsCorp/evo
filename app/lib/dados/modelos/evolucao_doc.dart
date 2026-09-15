import 'package:cloud_firestore/cloud_firestore.dart';

import 'campo_doc.dart';

/// Documento de `evolucoes/{id}` como a TELA enxerga — sem `clubId` (regra
/// de disciplina #6 do repositório: tenancy nunca aparece no modelo que a
/// tela manipula; quem injeta e filtra por `clubId` é o adaptador Firestore,
/// nunca o modelo).
///
/// `estadoInicial` e a futura leitura de `atribuicoes` (ver [ParteDoc])
/// guardam o MAPA CRU no formato que `package:evo_motor`
/// (`evolucao_json.dart`) já sabe ler via `estadoFormacaoDoJson` — ou seja,
/// o schema do documento Firestore E o schema JSON do motor são o MESMO
/// formato por construção. Isso é o que faz `emOrdem()` /
/// `paraEvolucaoMotor()` não precisar de nenhuma tradução além de remontar
/// o envelope `{nome, estadoInicial, partes}` que `evolucaoDoJson` espera.
class EvolucaoDoc {
  const EvolucaoDoc({
    required this.id,
    required this.nome,
    required this.pelotaoId,
    required this.estadoInicial,
    required this.versaoCatalogo,
    required this.criadoEm,
    required this.atualizadoEm,
    this.campo,
    this.pendente = false,
  });

  final String id;
  final String nome;
  final String pelotaoId;

  /// Formato cru `{'slots': {'0': {linha, coluna, setor, cadencia}, ...}}`
  /// — o mesmo que `estadoFormacaoDoJson`/`estadoFormacaoParaJson` do motor
  /// leem e escrevem. Chaves são ÍNDICE DE SLOT, nunca rótulo (é essa
  /// propriedade, imposta pela regra do servidor, que faz esta coleção não
  /// conter dado pessoal — ver docs/DADOS.md 2.4).
  final Map<String, dynamic> estadoInicial;

  final CampoDoc? campo;
  final int versaoCatalogo;
  final DateTime criadoEm;
  final DateTime atualizadoEm;

  /// NÃO É CAMPO DE DOCUMENTO. Vem de `snapshot.metadata.hasPendingWrites`
  /// — nunca de um campo `pendente` gravado no Firestore. Se algum dia
  /// alguém tentar persistir isto como campo de verdade, a allowlist do
  /// servidor (`camposPermitidosEvolucao().hasOnly([...])`) rejeita a
  /// escrita, porque `pendente` não está na lista.
  final bool pendente;

  factory EvolucaoDoc.doSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> dados = doc.data()!;
    return EvolucaoDoc(
      id: doc.id,
      nome: dados['nome'] as String,
      pelotaoId: dados['pelotaoId'] as String,
      estadoInicial: Map<String, dynamic>.from(
        dados['estadoInicial'] as Map<String, dynamic>,
      ),
      campo: dados['campo'] == null
          ? null
          : CampoDoc.doMapa(dados['campo'] as Map<String, dynamic>),
      versaoCatalogo: dados['versaoCatalogo'] as int,
      criadoEm: (dados['criadoEm'] as Timestamp).toDate(),
      atualizadoEm: (dados['atualizadoEm'] as Timestamp).toDate(),
      pendente: doc.metadata.hasPendingWrites,
    );
  }

  /// Campos aceitos pela allowlist do servidor, MENOS `criadoEm`/
  /// `atualizadoEm` — o adaptador (`RepositorioEvoFirestore`) decide os
  /// dois por fora, com `FieldValue.serverTimestamp()`, precisamente para
  /// nunca reenviar `criadoEm` como valor cru (ver o comentário longo em
  /// `repositorio_evo_firestore.dart` sobre por que isso quebraria
  /// `inalterado('criadoEm')` — e, em Flutter Web, quebraria mesmo sem
  /// querer mudar nada, só pela perda de precisão do `DateTime` da VM
  /// (milissegundo) frente ao `Timestamp` do Firestore (nanossegundo)).
  Map<String, dynamic> paraFirestoreSemTimestamps() => <String, dynamic>{
    'pelotaoId': pelotaoId,
    'nome': nome,
    'estadoInicial': estadoInicial,
    if (campo != null) 'campo': campo!.paraMapa(),
    'versaoCatalogo': versaoCatalogo,
  };

  EvolucaoDoc copiarCom({
    String? nome,
    Map<String, dynamic>? estadoInicial,
    CampoDoc? campo,
  }) => EvolucaoDoc(
    id: id,
    nome: nome ?? this.nome,
    pelotaoId: pelotaoId,
    estadoInicial: estadoInicial ?? this.estadoInicial,
    campo: campo ?? this.campo,
    versaoCatalogo: versaoCatalogo,
    criadoEm: criadoEm,
    atualizadoEm: atualizadoEm,
    pendente: pendente,
  );
}
