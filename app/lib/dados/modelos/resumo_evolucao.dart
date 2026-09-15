import 'package:cloud_firestore/cloud_firestore.dart';

/// Projeção leve de `evolucoes/{id}` para a LISTA (tela de navegação) —
/// deliberadamente mais magra que [EvolucaoDoc]: a lista não precisa de
/// `estadoInicial` (que pode ter até 36 slots) para desenhar uma linha com
/// nome + data. `RepositorioEvo.evolucao(id)` é quem entrega o documento
/// inteiro, para quem de fato vai abrir/tocar a evolução.
class ResumoEvolucao {
  const ResumoEvolucao({
    required this.id,
    required this.nome,
    required this.pelotaoId,
    required this.atualizadoEm,
  });

  final String id;
  final String nome;
  final String pelotaoId;
  final DateTime atualizadoEm;

  factory ResumoEvolucao.doSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> dados = doc.data()!;
    return ResumoEvolucao(
      id: doc.id,
      nome: dados['nome'] as String,
      pelotaoId: dados['pelotaoId'] as String,
      atualizadoEm: (dados['atualizadoEm'] as Timestamp).toDate(),
    );
  }
}
