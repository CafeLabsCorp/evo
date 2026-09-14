import '../diagnostico.dart';
import '../estado.dart';

/// Checagem 2 — Encadeamento: compara o fim real de uma evolução (ou
/// parte) contra o início EXIGIDO da próxima, em posição, direção e
/// cadência por slot, mais diferença de conjunto de slots.
///
/// Roda sempre, independente do modo de playback da sequência (`declarado`
/// ou `encadeado`) — é justamente o que expõe a divergência de cadência
/// ("termina marchando, a próxima exige firme") que não aparece no papel.
List<Diagnostico> verificarEncadeamento(
  EstadoFormacao fimReal,
  EstadoFormacao inicioExigido,
) {
  final List<Diagnostico> diagnosticos = <Diagnostico>[];
  final Set<int> slotsFim = fimReal.slots.toSet();
  final Set<int> slotsInicio = inicioExigido.slots.toSet();

  for (final int slot in slotsFim.difference(slotsInicio)) {
    diagnosticos.add(
      DiagnosticoEncadeamento(
        slot: slot,
        motivo:
            'presente no fim desta evolução mas ausente no início '
            'exigido da próxima (saiu da formação?).',
      ),
    );
  }
  for (final int slot in slotsInicio.difference(slotsFim)) {
    diagnosticos.add(
      DiagnosticoEncadeamento(
        slot: slot,
        motivo:
            'exigido no início da próxima evolução mas ausente no fim '
            'desta (entrada de membro novo?).',
        // Aviso, não erro: um slot novo pode ser uma entrada legítima no
        // pelotão — bloquear isso como erro seria um falso positivo
        // recorrente sempre que a formação crescer.
        severidade: SeveridadeDiagnostico.aviso,
      ),
    );
  }
  for (final int slot in slotsFim.intersection(slotsInicio)) {
    final estadoFim = fimReal[slot];
    final estadoInicio = inicioExigido[slot];
    final List<String> problemas = <String>[];
    if (estadoFim.x != estadoInicio.x || estadoFim.y != estadoInicio.y) {
      problemas.add(
        'posição diverge (fim: (${estadoFim.x}, ${estadoFim.y}) quartos; '
        'próxima exige: (${estadoInicio.x}, ${estadoInicio.y}) quartos)',
      );
    }
    if (estadoFim.dir != estadoInicio.dir) {
      problemas.add(
        'direção diverge (fim: setor ${estadoFim.dir}; próxima exige: '
        'setor ${estadoInicio.dir})',
      );
    }
    if (estadoFim.cad != estadoInicio.cad) {
      problemas.add(
        'cadência diverge (fim: ${estadoFim.cad}; próxima exige: '
        '${estadoInicio.cad})',
      );
    }
    if (problemas.isNotEmpty) {
      diagnosticos.add(
        DiagnosticoEncadeamento(slot: slot, motivo: problemas.join('; ')),
      );
    }
  }
  return diagnosticos;
}
