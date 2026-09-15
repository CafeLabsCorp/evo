import 'package:evo_app/dados/modelos/parte_doc.dart';
import 'package:evo_app/dados/ordenacao_partes.dart';
import 'package:evo_motor/evo_motor.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _atribuicaoSentido() => <String, dynamic>{
  'movimento': <String, dynamic>{'tipo': 'sentido', 'tempos': 2},
};

ParteDoc _parte({
  required String id,
  required double ordem,
  Map<String, dynamic>? atribuicoes,
}) => ParteDoc(
  id: id,
  evolucaoId: 'evolucao-1',
  ordem: ordem,
  atribuicoes: atribuicoes ?? <String, dynamic>{'0': _atribuicaoSentido()},
  atualizadoEm: DateTime(2026),
);

void main() {
  group('ordenarPartesDoc / emOrdem — (ordem, id) como único caminho', () {
    test('ordena por `ordem` quando não há empate', () {
      final List<ParteDoc> partes = <ParteDoc>[
        _parte(id: 'c', ordem: 3.0),
        _parte(id: 'a', ordem: 1.0),
        _parte(id: 'b', ordem: 2.0),
      ];
      final List<ParteDoc> ordenadas = ordenarPartesDoc(partes);
      expect(ordenadas.map((ParteDoc p) => p.id).toList(), <String>['a', 'b', 'c']);
    });

    test('desempata por `id` quando `ordem` está empatada — determinístico '
        'mesmo em ordem de chegada arbitrária', () {
      final List<ParteDoc> chegadaA = <ParteDoc>[
        _parte(id: 'zulu', ordem: 5.0),
        _parte(id: 'alfa', ordem: 5.0),
      ];
      final List<ParteDoc> chegadaB = <ParteDoc>[
        _parte(id: 'alfa', ordem: 5.0),
        _parte(id: 'zulu', ordem: 5.0),
      ];
      final List<String> idsA = ordenarPartesDoc(chegadaA).map((ParteDoc p) => p.id).toList();
      final List<String> idsB = ordenarPartesDoc(chegadaB).map((ParteDoc p) => p.id).toList();
      expect(idsA, <String>['alfa', 'zulu']);
      expect(idsA, idsB); // mesmo resultado independente da ordem de chegada.
    });

    test('emOrdem converte para List<Parte> do motor, já na ordem certa', () {
      final List<ParteDoc> partes = <ParteDoc>[
        _parte(id: 'segunda', ordem: 2.0, atribuicoes: <String, dynamic>{
          '0': <String, dynamic>{
            'movimento': <String, dynamic>{'tipo': 'descansar', 'tempos': 1},
          },
        }),
        _parte(id: 'primeira', ordem: 1.0),
      ];
      final List<Parte> motor = emOrdem(partes);
      expect(motor, hasLength(2));
      expect(motor[0].ordem, 1.0);
      expect(motor[1].ordem, 2.0);
      // Round-trip real via o codec do motor, não um stub — se o formato
      // de `atribuicoes` divergir do que `atribuicaoDoJson` espera, isto
      // lança em vez de silenciosamente aceitar.
      expect(motor[0].atribuicoes[0]!.movimento.nome, 'Sentido');
      expect(motor[1].atribuicoes[0]!.movimento.nome, 'Descansar');
    });

    test('nome opcional da parte é preservado no round-trip', () {
      final ParteDoc doc = _parte(id: 'x', ordem: 1.0)
          .copiarCom(nome: 'Marcar passo (partindo de Sentido)');
      final List<Parte> motor = emOrdem(<ParteDoc>[doc]);
      expect(motor.single.nome, 'Marcar passo (partindo de Sentido)');
    });
  });
}
