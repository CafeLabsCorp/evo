import 'package:evo_motor/evo_motor.dart';

import 'modelos/parte_doc.dart';

/// O comparador `(ordem, id)` isolado, para uso tanto aqui quanto direto no
/// adaptador Firestore (`RepositorioEvoFirestore.partes`, que já entrega a
/// lista "ordenada e desempatada" conforme o contrato da interface, antes
/// mesmo de qualquer tela chamar [emOrdem]).
List<ParteDoc> ordenarPartesDoc(List<ParteDoc> partes) {
  final List<ParteDoc> ordenadas = List<ParteDoc>.of(partes)
    ..sort((ParteDoc a, ParteDoc b) {
      final int porOrdem = a.ordem.compareTo(b.ordem);
      return porOrdem != 0 ? porOrdem : a.id.compareTo(b.id);
    });
  return ordenadas;
}

/// Único caminho do app para transformar `List<ParteDoc>` (o que o
/// Firestore devolve) em `List<Parte>` (o que `simular` do motor aceita).
///
/// Ordena por `(ordem, id)` MESMO já tendo pedido `orderBy('ordem')` no
/// servidor: duas partes com `ordem` empatada têm desempate INDEFINIDO no
/// Firestore (a ordem de chegada entre elas não é garantida nem estável
/// entre execuções), e `List.sort` do Dart não é estável — então "confiar
/// na ordem de chegada" nunca é uma correção válida para o empate, com ou
/// sem sort de novo. `id` é o único desempate determinístico disponível
/// (motor `Parte` nem tem `id` para servir de critério).
List<Parte> emOrdem(List<ParteDoc> partes) {
  final List<ParteDoc> ordenadas = ordenarPartesDoc(partes);
  return <Parte>[
    for (final ParteDoc doc in ordenadas)
      parteDoJson(<String, dynamic>{
        'ordem': doc.ordem,
        if (doc.nome != null) 'nome': doc.nome,
        'atribuicoes': doc.atribuicoes,
      }),
  ];
}
