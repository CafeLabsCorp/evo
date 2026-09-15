import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:evo_app/dados/falha_persistencia.dart';
import 'package:flutter_test/flutter_test.dart';

FirebaseException _erro(String codigo, [String? mensagem]) =>
    FirebaseException(plugin: 'cloud_firestore', code: codigo, message: mensagem);

void main() {
  group('falhaPersistenciaDe — tradução de FirebaseException para o tipo fechado', () {
    test('permission-denied vira SemPermissao', () {
      expect(falhaPersistenciaDe(_erro('permission-denied')), isA<SemPermissao>());
    });

    test('unavailable/deadline-exceeded/cancelled/aborted viram ForaDoAr — '
        'conectividade é estado normal, não erro', () {
      for (final String codigo in <String>[
        'unavailable',
        'deadline-exceeded',
        'cancelled',
        'aborted',
      ]) {
        expect(falhaPersistenciaDe(_erro(codigo)), isA<ForaDoAr>(), reason: codigo);
      }
    });

    test('resource-exhausted vira CotaEstourada — precisa de mensagem '
        'própria (cota diária do Spark), não "erro desconhecido"', () {
      expect(falhaPersistenciaDe(_erro('resource-exhausted')), isA<CotaEstourada>());
    });

    test('invalid-argument sem menção a tamanho vira DocumentoInvalido', () {
      expect(
        falhaPersistenciaDe(_erro('invalid-argument', 'algum campo é inválido')),
        isA<DocumentoInvalido>(),
      );
    });

    test('invalid-argument mencionando tamanho vira LimiteDeTamanho', () {
      expect(
        falhaPersistenciaDe(
          _erro('invalid-argument', 'the value exceeds the maximum size'),
        ),
        isA<LimiteDeTamanho>(),
      );
    });

    test('código desconhecido do SDK cai em DocumentoInvalido, nunca em '
        'ForaDoAr — não presume que um erro não mapeado é transitório', () {
      expect(falhaPersistenciaDe(_erro('algum-codigo-novo-do-sdk')), isA<DocumentoInvalido>());
    });

    test('erro que não é FirebaseException também cai em DocumentoInvalido', () {
      expect(falhaPersistenciaDe(Exception('erro genérico')), isA<DocumentoInvalido>());
    });
  });
}
