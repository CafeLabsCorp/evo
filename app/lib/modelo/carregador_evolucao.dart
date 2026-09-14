import 'dart:convert';

import 'package:evo_motor/evo_motor.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Uma evolução já carregada e simulada, pronta pro playback.
///
/// Simular já é uma função pura e barata (dart puro, sem I/O) — rodamos
/// uma vez ao carregar e guardamos o resultado; não há necessidade de
/// nenhum cache mais sofisticado pra v1 (um único arquivo local, sem
/// paginação, sem rede).
class PacoteEvolucao {
  const PacoteEvolucao({required this.evolucao, required this.resultado});

  final Evolucao evolucao;
  final ResultadoSimulacao resultado;

  /// Erros de verdade (severidade erro) — o que bloquearia confiança na
  /// animação, mostrado como aviso permanente na tela, não como bloqueio:
  /// a spec é clara que nenhuma checagem aborta a simulação.
  List<Diagnostico> get diagnosticosDeErro => resultado.diagnosticos
      .where((d) => d.severidade == SeveridadeDiagnostico.erro)
      .toList();

  List<Diagnostico> get diagnosticosDeAviso => resultado.diagnosticos
      .where((d) => d.severidade == SeveridadeDiagnostico.aviso)
      .toList();
}

/// Carrega e simula uma evolução a partir de um JSON local empacotado como
/// asset. Único ponto de "I/O" do app inteiro — e mesmo assim é leitura de
/// asset embarcado, não rede: não existe estado "offline" aqui, só
/// carregando / erro-de-formato / pronto.
Future<PacoteEvolucao> carregarEvolucaoDoAsset(
  String caminhoAsset, [
  Config cfg = const Config(),
]) async {
  final String texto = await rootBundle.loadString(caminhoAsset);
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(texto) as Map<String, dynamic>;
  } on FormatException catch (e) {
    throw FormatException('JSON malformado em "$caminhoAsset": ${e.message}');
  }

  final Evolucao evolucao = evolucaoDoJson(json);
  final ResultadoSimulacao resultado = simular(
    evolucao.estadoInicial,
    evolucao.partes,
    cfg,
  );
  return PacoteEvolucao(evolucao: evolucao, resultado: resultado);
}
