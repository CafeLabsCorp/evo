import 'package:cloud_firestore/cloud_firestore.dart';

/// Lê um campo gravado com `FieldValue.serverTimestamp()` a partir de um
/// snapshot — tolerando o instante em que ele ainda não foi confirmado.
///
/// Entre o momento em que uma escrita NÃO-transacional (`.set()`/`.update()`
/// fora de `runTransaction`) é aplicada ao cache local e o momento em que o
/// servidor confirma, o SDK do Firestore entrega um snapshot OTIMISTA em que
/// esse campo ainda é `null` — comportamento documentado do
/// `FieldValue.serverTimestamp()`, não dado corrompido. Um listener já
/// inscrito no instante da escrita VÊ esse snapshot intermediário: é
/// exatamente o que acontece ao criar a primeira parte de uma evolução
/// (`ControladorEditorPartes.adicionarParteVazia` -> `gravarParte`) com o
/// editor já aberto e já assinando `partes(evolucaoId)` — um cast direto
/// `dados['atualizadoEm'] as Timestamp` explode ali com
/// `type 'JSNull' is not a subtype of type 'Timestamp'`, matando o stream
/// (bug real, encontrado no E2E desta rodada — não é artefato de emulador).
///
/// `cloud_firestore` (Flutter) ainda não expõe `serverTimestampBehavior` —
/// `SnapshotOptions` está marcada "Currently unsupported by FlutterFire" no
/// pacote hoje — então não há como pedir ao SDK para estimar o valor. A
/// saída aqui é a mesma que a documentação do Firestore recomenda nesse
/// caso: tratar `null` como "ainda não confirmado" e usar o instante local
/// como aproximação; o snapshot seguinte (quando o servidor confirmar)
/// substitui isso pelo valor real — o campo nunca fica errado por muito
/// tempo, só até o próximo tique do stream.
///
/// Escritas TRANSACIONAIS (`gravarPelotao`/`gravarEvolucao`, via
/// `runTransaction`) não passam por este caminho: uma transação não aplica
/// nada ao cache local antes do commit no servidor, então o campo já chega
/// resolvido. Esta função existe mesmo assim nos quatro `doSnapshot` que
/// leem timestamp — é a mesma classe de bug, e nada garante que um caminho
/// de escrita não-transacional não apareça amanhã em um deles.
DateTime dataDeTimestampPendente(Object? bruto) {
  if (bruto == null) return DateTime.now();
  return (bruto as Timestamp).toDate();
}
