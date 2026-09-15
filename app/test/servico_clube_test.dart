import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:evo_app/clube/modelo_clube.dart';
import 'package:evo_app/clube/servico_clube.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServicoClube.bootstrap — idempotente, clubId nunca é o uid', () {
    test('primeiro login: cria um clube com auto-id (≠ uid), dono e único '
        'membro ativo', () async {
      final FakeFirebaseFirestore db = FakeFirebaseFirestore();
      final ServicoClube servico = ServicoClube(firestore: db);

      const String uid = 'uid-do-felipe';
      final String clubId = await servico.bootstrap(uid: uid);

      expect(clubId, isNot(uid)); // a trava central do handoff.
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await db.collection('clubes').doc(clubId).get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['dono'], uid);
      expect(doc.data()!['nome'], 'Clube Exemplo');
      expect(doc.data()!['membros'], <String, dynamic>{
        uid: <String, dynamic>{'estado': 'ativo', 'papel': 'instrutor'},
      });
      expect(doc.data()!['membrosAtivos'], <String, dynamic>{uid: true});
    });

    test('segundo login do mesmo uid não cria um segundo clube', () async {
      final FakeFirebaseFirestore db = FakeFirebaseFirestore();
      final ServicoClube servico = ServicoClube(firestore: db);
      const String uid = 'uid-do-felipe';

      final String primeiro = await servico.bootstrap(uid: uid);
      final String segundo = await servico.bootstrap(uid: uid);

      expect(segundo, primeiro);
      expect((await db.collection('clubes').get()).docs, hasLength(1));
    });

    test('meusClubes descobre via membrosAtivos.<uid> == true', () async {
      final FakeFirebaseFirestore db = FakeFirebaseFirestore();
      final ServicoClube servico = ServicoClube(firestore: db);
      const String uid = 'uid-1';
      final String clubId = await servico.bootstrap(uid: uid);

      final List<ClubeResumo> clubes = await servico.meusClubes(uid).first;
      expect(clubes, hasLength(1));
      expect(clubes.single.id, clubId);

      final List<ClubeResumo> deOutroUid = await servico.meusClubes('outro-uid').first;
      expect(deOutroUid, isEmpty);
    });
  });
}
