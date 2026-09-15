import 'package:cloud_firestore/cloud_firestore.dart';

/// Projeção mínima de `clubes/{clubId}` que a UI de navegação precisa —
/// só o suficiente para identificar "qual clube" e mostrar o nome. Nunca
/// carrega `membros`/`membrosAtivos` (não há tela de gestão de membros
/// nesta versão single-user).
class ClubeResumo {
  const ClubeResumo({required this.id, required this.nome});

  final String id;
  final String nome;

  factory ClubeResumo.doSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) =>
      ClubeResumo(id: doc.id, nome: doc.data()!['nome'] as String);
}
