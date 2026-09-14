import '../campo.dart';
import '../diagnostico.dart';
import '../estado.dart';
import '../geometria.dart';

/// Checagem 4 — Fora dos limites: por tique, contra `cfg.campo`, em
/// células. O campo NÃO é a grade da formação — evoluções deslocam o
/// pelotão inteiro pelo salão, então os limites são do salão, não do
/// retângulo inicial 5x5 (ou o que for) da formação.
///
/// A comparação é feita em quartos-de-célula (inteiro) para não introduzir
/// erro de ponto flutuante; só convertemos para células (`double`) na hora
/// de montar a mensagem do diagnóstico.
List<Diagnostico> verificarLimites(List<EstadoFormacao> porTique, Campo campo) {
  final int xMinQuartos = (campo.colunaMinima * unidadesPorCelula).round();
  final int xMaxQuartos = (campo.colunaMaxima * unidadesPorCelula).round();
  final int yMinQuartos = (campo.linhaMinima * unidadesPorCelula).round();
  final int yMaxQuartos = (campo.linhaMaxima * unidadesPorCelula).round();

  final List<Diagnostico> diagnosticos = <Diagnostico>[];

  for (int tique = 0; tique < porTique.length; tique++) {
    final EstadoFormacao formacao = porTique[tique];
    for (final int slot in formacao.slots) {
      final estado = formacao[slot];
      if (estado.x < xMinQuartos ||
          estado.x > xMaxQuartos ||
          estado.y < yMinQuartos ||
          estado.y > yMaxQuartos) {
        final (double linha, double coluna) = estado.posicao.emCelulas();
        diagnosticos.add(
          DiagnosticoForaDosLimites(
            tique: tique,
            slot: slot,
            linha: linha,
            coluna: coluna,
          ),
        );
      }
    }
  }

  return diagnosticos;
}
