/// Baixa [json] como arquivo `.json` via `Blob` + âncora — o único jeito de
/// "salvar arquivo" num app Flutter Web sem diálogo nativo de sistema.
///
/// Export CONDICIONAL de propósito (`dart.library.html` como sinal de
/// "estou compilando para navegador", mesmo sem importar `dart:html` em
/// lugar nenhum): `flutter test` compila os testes para a VM mesmo neste
/// app sendo Web-only (não existe `flutter test --platform=chrome` no
/// pipeline padrão) — sem este shim, qualquer arquivo que importe isto
/// (ex.: `telas/tela_evolucoes.dart`, alcançável a partir de
/// `telas/portao_app.dart`) falha para COMPILAR sob a VM, não só para
/// rodar, porque `package:web`/`dart:js_interop`
/// (`exportar_evolucao_web.dart`) não têm binding nenhum fora de um
/// destino Web de verdade.
///
/// Nome do arquivo: `<nomeBaseArquivo>-AAAA-MM-DD-HHmm.json`, hora LOCAL do
/// instrutor (não UTC) — é o nome que a pessoa vai procurar na pasta de
/// downloads horas depois (ver `carimbo_de_data.dart`).
library;

export 'exportar_evolucao_stub.dart'
    if (dart.library.html) 'exportar_evolucao_web.dart';
