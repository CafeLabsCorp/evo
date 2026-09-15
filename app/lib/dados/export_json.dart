import 'package:evo_motor/evo_motor.dart';

import 'modelos/evolucao_doc.dart';
import 'modelos/parte_doc.dart';
import 'ordenacao_partes.dart';

/// Monta o JSON de export de uma evolução — reusa `evolucaoParaJson` do
/// motor (Etapa 5 do handoff: "reusando `evolucaoParaJson`", não
/// reimplementando serialização). Função pura, sem Firestore nem
/// `dart:html`/`package:web`: testável sozinha (ver
/// `test/export_json_test.dart`), diferente do download em si
/// (`util/exportar_evolucao.dart`), que só existe em navegador de verdade.
Map<String, dynamic> construirJsonDeExport(EvolucaoDoc doc, List<ParteDoc> partes) {
  final Evolucao evolucao = Evolucao(
    nome: doc.nome,
    estadoInicial: estadoFormacaoDoJson(doc.estadoInicial),
    partes: emOrdem(partes),
  );
  return evolucaoParaJson(evolucao);
}
