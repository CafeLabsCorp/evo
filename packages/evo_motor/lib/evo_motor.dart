/// Motor de simulação de ordem unida do Evo — Dart puro, sem Flutter, sem
/// Firebase. Ver `packages/evo_motor/README` (se/quando existir) ou os
/// comentários de `src/` para a spec completa; este arquivo só reexporta a
/// API pública.
library;

export 'src/campo.dart';
export 'src/catalogo.dart';
export 'src/cadencia.dart';
export 'src/checagens/colisao.dart';
export 'src/checagens/encadeamento.dart';
export 'src/checagens/limites.dart';
export 'src/compilador.dart' show ResultadoCompilacaoParte, compilarParte;
export 'src/diagnostico.dart';
export 'src/estado.dart';
export 'src/eventos.dart';
export 'src/geometria.dart';
export 'src/json/evolucao_json.dart';
export 'src/movimento.dart';
export 'src/parte.dart';
export 'src/preenchimento.dart';
export 'src/segmento.dart';
export 'src/simulador.dart';
