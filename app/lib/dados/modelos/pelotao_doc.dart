import 'package:cloud_firestore/cloud_firestore.dart';

/// Teto de caracteres por rótulo — espelha `rotulosDoMapaValidos()` em
/// `firestore.rules`. Limita TAMANHO, não semântica (docs/DADOS.md 3.3a):
/// não impede um nome civil curto, só um texto livre longo.
const int maxCaracteresRotulo = 24;

/// Teto de slots (grid 6×6) — espelha o orçamento de expressões da regra
/// (ver o comentário "ORÇAMENTO DE EXPRESSÕES" em `firestore.rules`). Um
/// grid maior não cabe na regra sem reformulá-la primeiro.
const int maxLinhasOuColunas = 6;

/// Documento de `pelotoes/{id}` como a TELA enxerga — sem `clubId` (regra
/// de disciplina #6). É a coleção sensível: `rotulos` é o único lugar do
/// schema inteiro que guarda dado pessoal de membro do pelotão (ver
/// docs/DADOS.md 2.3).
class PelotaoDoc {
  const PelotaoDoc({
    required this.id,
    required this.nome,
    required this.linhas,
    required this.colunas,
    required this.rotulos,
    required this.criadoEm,
    required this.atualizadoEm,
    this.pendente = false,
  });

  final String id;
  final String nome;
  final int linhas;
  final int colunas;

  /// Chave = índice de slot (`"0"`..`"35"`), valor = rótulo (apelido ou
  /// primeiro nome, ≤ [maxCaracteresRotulo]). Slots sem rótulo simplesmente
  /// NÃO aparecem como chave — grid parcialmente preenchido é estado
  /// válido (docs/DADOS.md 2.3). O rótulo vive só aqui: nunca como ID de
  /// documento, nunca em path.
  final Map<String, String> rotulos;

  final DateTime criadoEm;
  final DateTime atualizadoEm;

  /// NÃO É CAMPO DE DOCUMENTO — ver o mesmo aviso em [EvolucaoDoc.pendente].
  final bool pendente;

  int get totalSlots => linhas * colunas;

  factory PelotaoDoc.doSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> dados = doc.data()!;
    final Map<String, dynamic> rotulosCrus =
        (dados['rotulos'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return PelotaoDoc(
      id: doc.id,
      nome: dados['nome'] as String,
      linhas: dados['linhas'] as int,
      colunas: dados['colunas'] as int,
      rotulos: <String, String>{
        for (final MapEntry<String, dynamic> e in rotulosCrus.entries)
          if ((e.value as String).isNotEmpty) e.key: e.value as String,
      },
      criadoEm: (dados['criadoEm'] as Timestamp).toDate(),
      atualizadoEm: (dados['atualizadoEm'] as Timestamp).toDate(),
      pendente: doc.metadata.hasPendingWrites,
    );
  }

  /// Ver o aviso em `EvolucaoDoc.paraFirestoreSemTimestamps` — mesmo
  /// motivo, mesma solução: `criadoEm`/`atualizadoEm` nunca passam por
  /// aqui.
  Map<String, dynamic> paraFirestoreSemTimestamps() => <String, dynamic>{
    'nome': nome,
    'linhas': linhas,
    'colunas': colunas,
    'rotulos': rotulos,
  };

  PelotaoDoc copiarCom({
    String? nome,
    int? linhas,
    int? colunas,
    Map<String, String>? rotulos,
  }) => PelotaoDoc(
    id: id,
    nome: nome ?? this.nome,
    linhas: linhas ?? this.linhas,
    colunas: colunas ?? this.colunas,
    rotulos: rotulos ?? this.rotulos,
    criadoEm: criadoEm,
    atualizadoEm: atualizadoEm,
    pendente: pendente,
  );
}
