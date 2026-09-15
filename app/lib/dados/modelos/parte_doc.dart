import 'package:cloud_firestore/cloud_firestore.dart';

/// Documento de `partes/{id}` como a TELA enxerga — sem `clubId` (regra de
/// disciplina #6: tenancy nunca aparece no modelo). `evolucaoId` fica,
/// porque é relação de domínio (a qual evolução esta parte pertence), não
/// tenancy.
///
/// `atribuicoes` é o mapa cru no formato que `atribuicaoDoJson`/
/// `atribuicaoParaJson` (package:evo_motor) leem e escrevem — chaveado por
/// ÍNDICE DE SLOT, nunca por rótulo, e a regra do servidor NÃO valida o
/// interior de cada valor (ver LIMITAÇÃO CONHECIDA em `firestore.rules`).
class ParteDoc {
  const ParteDoc({
    required this.id,
    required this.evolucaoId,
    required this.ordem,
    required this.atribuicoes,
    this.nome,
    required this.atualizadoEm,
    this.pendente = false,
  });

  final String id;
  final String evolucaoId;

  /// Chave fracionária de reordenação (ver `ordem_fracionaria.dart`).
  final double ordem;

  final String? nome;
  final Map<String, dynamic> atribuicoes;
  final DateTime atualizadoEm;

  /// NÃO É CAMPO DE DOCUMENTO — ver o mesmo aviso em [EvolucaoDoc.pendente].
  final bool pendente;

  factory ParteDoc.doSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> dados = doc.data()!;
    return ParteDoc(
      id: doc.id,
      evolucaoId: dados['evolucaoId'] as String,
      ordem: (dados['ordem'] as num).toDouble(),
      nome: dados['nome'] as String?,
      atribuicoes: Map<String, dynamic>.from(
        dados['atribuicoes'] as Map<String, dynamic>,
      ),
      atualizadoEm: (dados['atualizadoEm'] as Timestamp).toDate(),
      pendente: doc.metadata.hasPendingWrites,
    );
  }

  /// Documento completo pronto para `.set()` — `partes` não tem `criadoEm`
  /// no schema (só `evolucoes`/`clubes` têm), então, ao contrário de
  /// [EvolucaoDoc], não existe campo imutável para proteger aqui: um
  /// `.set()` de corpo inteiro (não `merge`) é seguro tanto para criar
  /// quanto para atualizar. `atualizadoEm` é decidido pelo adaptador com
  /// `FieldValue.serverTimestamp()`.
  Map<String, dynamic> paraFirestoreSemTimestamp() => <String, dynamic>{
    'evolucaoId': evolucaoId,
    'ordem': ordem,
    if (nome != null) 'nome': nome,
    'atribuicoes': atribuicoes,
  };

  ParteDoc copiarCom({double? ordem, String? nome, Map<String, dynamic>? atribuicoes}) =>
      ParteDoc(
        id: id,
        evolucaoId: evolucaoId,
        ordem: ordem ?? this.ordem,
        nome: nome ?? this.nome,
        atribuicoes: atribuicoes ?? this.atribuicoes,
        atualizadoEm: atualizadoEm,
        pendente: pendente,
      );
}
