/// Codec compartilhado entre o script de regeneração
/// (`tool/regenerar_goldens.dart`) e o teste de goldens (`test/golden_test.dart`).
///
/// Formato de um `*.golden.json`:
/// ```json
/// {
///   "versaoCatalogo": 2,
///   "entrada": { ... Evolucao em JSON, mesmo formato de evolucao_json.dart ... },
///   "saida": [ { "0": {"x":0,"y":0,"dir":0,"cad":"firme"}, "1": {...} }, ... ]
/// }
/// ```
///
/// `saida` NÃO usa `estadoPessoaParaJson` (linha/coluna): tiques
/// intermediários de uma diagonal não caem numa fronteira de célula
/// inteira e aquela função lança de propósito nesse caso (é a fronteira de
/// serialização "de verdade", voltada pra Firestore/app). O golden é um
/// fixture de TESTE interno ao pacote, não atravessa a fronteira pública —
/// então grava x/y em quartos diretamente, sem essa restrição.
library;

import 'package:evo_motor/evo_motor.dart';

Map<String, dynamic> estadoPessoaParaGolden(EstadoPessoa e) => <String, dynamic>{
  'x': e.x,
  'y': e.y,
  'dir': e.dir,
  'cad': cadenciaParaJson(e.cad),
};

Map<String, dynamic> estadoFormacaoParaGolden(EstadoFormacao f) =>
    <String, dynamic>{
      for (final int slot in f.slots) '$slot': estadoPessoaParaGolden(f[slot]),
    };

List<dynamic> saidaParaGolden(List<EstadoFormacao> porTique) => <dynamic>[
  for (final EstadoFormacao f in porTique) estadoFormacaoParaGolden(f),
];

Map<String, dynamic> montarGolden({
  required Map<String, dynamic> entradaJson,
  required List<EstadoFormacao> porTique,
}) => <String, dynamic>{
  'versaoCatalogo': versaoCatalogo,
  'entrada': entradaJson,
  'saida': saidaParaGolden(porTique),
};
