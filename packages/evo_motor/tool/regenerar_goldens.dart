/// Regenera TODOS os `test/golden/*.golden.json` a partir das fontes atuais
/// e do catálogo atual (`versaoCatalogo`).
///
/// Rode com `dart run tool/regenerar_goldens.dart` (cwd = raiz do pacote
/// `evo_motor`) sempre que uma correção de catálogo mudar
/// `versaoCatalogo` — de propósito, regenera todos de uma vez, não um por
/// um, pra que o diff resultante ("N arquivos mudaram, todos indo de X pra
/// Y") seja o sinal de "correção legítima", contra um golden isolado
/// mudando sozinho (sinal de regressão).
///
/// Fontes: por ora, só `exemplo` — a mesma evolução usada no app
/// (`app/assets/evolucoes/exemplo.json`), a caminho do portão de 21/09.
/// Quando o usuário substituir pelos dados reais das evoluções da
/// apresentação, adicione a entrada correspondente no mapa `_fontes`
/// abaixo (nome do golden -> caminho do JSON de entrada) e rode este
/// script de novo.
library;

import 'dart:convert';
import 'dart:io';

import 'package:evo_motor/evo_motor.dart';

import '../test/golden/golden_codec.dart';

/// nome do golden -> caminho do JSON de entrada (relativo à raiz do
/// pacote `evo_motor`).
const Map<String, String> _fontes = <String, String>{
  'exemplo': '../../app/assets/evolucoes/exemplo.json',
};

void main() {
  for (final MapEntry<String, String> fonte in _fontes.entries) {
    final String nome = fonte.key;
    final File arquivoEntrada = File(fonte.value);
    if (!arquivoEntrada.existsSync()) {
      stderr.writeln('Fonte não encontrada para "$nome": ${fonte.value}');
      exitCode = 1;
      continue;
    }

    final Map<String, dynamic> entradaJson =
        jsonDecode(arquivoEntrada.readAsStringSync()) as Map<String, dynamic>;
    final Evolucao evolucao = evolucaoDoJson(entradaJson);
    final ResultadoSimulacao resultado = simular(
      evolucao.estadoInicial,
      evolucao.partes,
    );

    final Map<String, dynamic> golden = montarGolden(
      entradaJson: entradaJson,
      porTique: resultado.porTique,
    );

    final File arquivoSaida = File('test/golden/$nome.golden.json');
    arquivoSaida.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(golden)}\n',
    );
    stdout.writeln(
      'Regenerado: ${arquivoSaida.path} (versaoCatalogo=$versaoCatalogo, '
      '${resultado.porTique.length} tiques, '
      '${resultado.diagnosticos.length} diagnósticos)',
    );
  }
}
