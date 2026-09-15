import 'package:evo_app/dados/export_json.dart';
import 'package:evo_app/dados/modelos/evolucao_doc.dart';
import 'package:evo_app/dados/modelos/parte_doc.dart';
import 'package:evo_motor/evo_motor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('construirJsonDeExport — reusa evolucaoParaJson do motor', () {
    test('produz um JSON que o próprio motor lê de volta (round-trip)', () {
      final EvolucaoDoc doc = EvolucaoDoc(
        id: 'evo-1',
        nome: 'Evolução de teste',
        pelotaoId: 'pel-1',
        estadoInicial: <String, dynamic>{
          'slots': <String, dynamic>{
            '0': <String, dynamic>{
              'linha': 0,
              'coluna': 0,
              'setor': 0,
              'cadencia': 'firme',
            },
          },
        },
        versaoCatalogo: versaoCatalogo,
        criadoEm: DateTime(2026, 9, 14),
        atualizadoEm: DateTime(2026, 9, 14),
      );
      final List<ParteDoc> partes = <ParteDoc>[
        ParteDoc(
          id: 'parte-1',
          evolucaoId: 'evo-1',
          ordem: 1.0,
          atribuicoes: <String, dynamic>{
            '0': <String, dynamic>{
              'movimento': <String, dynamic>{'tipo': 'sentido', 'tempos': 2},
            },
          },
          atualizadoEm: DateTime(2026, 9, 14),
        ),
      ];

      final Map<String, dynamic> json = construirJsonDeExport(doc, partes);

      expect(json['nome'], 'Evolução de teste');
      expect(json['estadoInicial'], isA<Map<String, dynamic>>());
      expect(json['partes'], hasLength(1));

      // O teste real: o JSON produzido é o mesmo formato que
      // `carregarEvolucaoDoAsset` lê — se um dia divergir, o motor lança
      // ao tentar reconstruir a `Evolucao`, aqui, não em produção.
      final Evolucao reconstruida = evolucaoDoJson(json);
      expect(reconstruida.nome, 'Evolução de teste');
      expect(reconstruida.partes, hasLength(1));
      expect(reconstruida.estadoInicial[0].cad, Cadencia.firme);
    });

    test('nunca inclui clubId/pelotaoId/evolucaoId — export é só o que o '
        'motor entende, sem tenancy', () {
      final EvolucaoDoc doc = EvolucaoDoc(
        id: 'evo-2',
        nome: 'Sem tenancy',
        pelotaoId: 'pel-x',
        estadoInicial: <String, dynamic>{'slots': <String, dynamic>{}},
        versaoCatalogo: versaoCatalogo,
        criadoEm: DateTime(2026),
        atualizadoEm: DateTime(2026),
      );
      final Map<String, dynamic> json = construirJsonDeExport(doc, const <ParteDoc>[]);
      expect(json.containsKey('clubId'), isFalse);
      expect(json.containsKey('pelotaoId'), isFalse);
      expect(json.containsKey('evolucaoId'), isFalse);
    });
  });
}
