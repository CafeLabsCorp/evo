import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:evo_app/dados/modelos/timestamp_pendente.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regressão do bug real encontrado no E2E desta rodada: criar a primeira
/// parte de uma evolução (`ControladorEditorPartes.adicionarParteVazia` ->
/// `RepositorioEvoFirestore.gravarParte`, um `.set()` NÃO-transacional com
/// `FieldValue.serverTimestamp()`) derrubava o stream de `partes` inteiro
/// com `type 'JSNull' is not a subtype of type 'Timestamp'` — porque o
/// snapshot OTIMISTA que o SDK entrega antes do servidor confirmar tem o
/// campo do timestamp como `null`, e `ParteDoc.doSnapshot` fazia um cast
/// direto sem tolerar isso. `FakeFirebaseFirestore` não reproduz esse
/// snapshot intermediário (resolve tudo síncrono), então o bug só apareceu
/// no E2E contra um Firestore de verdade — este teste cobre a FUNÇÃO em
/// isolamento, que é o que os quatro `doSnapshot` (`ParteDoc`, `EvolucaoDoc`,
/// `PelotaoDoc`, `ResumoEvolucao`) agora chamam em vez do cast direto.
void main() {
  group('dataDeTimestampPendente', () {
    test('Timestamp de verdade vira a mesma data (round-trip)', () {
      final DateTime original = DateTime(2026, 3, 10, 14, 30);
      final Timestamp bruto = Timestamp.fromDate(original);
      expect(dataDeTimestampPendente(bruto), original);
    });

    test('null (serverTimestamp() ainda não confirmado) não lança — cai '
        'para "agora" como aproximação, nunca crasha o stream', () {
      final DateTime antes = DateTime.now();
      final DateTime resultado = dataDeTimestampPendente(null);
      final DateTime depois = DateTime.now();

      expect(
        resultado.isAfter(antes.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        resultado.isBefore(depois.add(const Duration(seconds: 1))),
        isTrue,
      );
    });
  });
}
