import 'dart:convert';
import 'dart:io';

import 'package:evo_motor/evo_motor.dart';
import 'package:test/test.dart';

import 'golden/golden_codec.dart';

/// Testes de golden — ver `test/golden/golden_codec.dart` pro formato e
/// `tool/regenerar_goldens.dart` pro script de regeneração.
///
/// Dois testes por golden, e a distinção entre eles É o ponto (ver spec):
/// - "regressão real": reprocessa a entrada e compara com a saída
///   gravada — só é um sinal de bug quando `versaoCatalogo` do arquivo
///   bate com a constante atual do motor.
/// - "consistência de versão": se `versaoCatalogo` do arquivo NÃO bate
///   com a constante atual, o golden está desatualizado — rode o script
///   de regeneração. Isso é sempre checado, independente do resultado do
///   teste de regressão.
///
/// Assim uma correção legítima de catálogo aparece como "N arquivos
/// mudaram, todos com a versão indo de X pra Y" (falha só no teste de
/// consistência, até alguém rodar o script) — diff grande mas explicado;
/// uma regressão aparece como "1 arquivo mudou, mesma versão" — falha no
/// teste de regressão, diff pequeno e inexplicável.
void main() {
  final Directory dirGoldens = Directory('test/golden');
  final List<File> arquivos =
      dirGoldens
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.endsWith('.golden.json'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));

  test('existe pelo menos um golden registrado', () {
    expect(
      arquivos,
      isNotEmpty,
      reason:
          'Nenhum test/golden/*.golden.json encontrado — rode '
          '`dart run tool/regenerar_goldens.dart`.',
    );
  });

  for (final File arquivo in arquivos) {
    final String nome = arquivo.path
        .split(Platform.pathSeparator)
        .last
        .replaceAll('.golden.json', '');

    final Map<String, dynamic> golden =
        jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>;
    final int versaoGravada = golden['versaoCatalogo'] as int;
    final Map<String, dynamic> entradaJson =
        golden['entrada'] as Map<String, dynamic>;
    final dynamic saidaGravada = golden['saida'];

    final Evolucao evolucao = evolucaoDoJson(entradaJson);
    final ResultadoSimulacao resultado = simular(
      evolucao.estadoInicial,
      evolucao.partes,
    );
    final List<dynamic> saidaAtual = saidaParaGolden(resultado.porTique);

    test('golden "$nome" — consistência de versão', () {
      expect(
        versaoGravada,
        versaoCatalogo,
        reason:
            'golden "$nome" desatualizado (gravado com versaoCatalogo='
            '$versaoGravada, motor está em $versaoCatalogo) — rode '
            '`dart run tool/regenerar_goldens.dart`.',
      );
    });

    test('golden "$nome" — regressão (só é sinal de bug com a mesma versão)', () {
      if (versaoGravada != versaoCatalogo) {
        // Já é reportado pelo teste de consistência de versão acima —
        // comparar a saída aqui só teria sinal quando as versões batem
        // (é exatamente a distinção que este arquivo documenta).
        return;
      }
      expect(
        saidaAtual,
        equals(saidaGravada),
        reason:
            'golden "$nome" mudou sem mudança de catálogo — bug, não '
            'correção (versaoCatalogo continua $versaoCatalogo nos dois '
            'lados).',
      );
    });
  }
}
