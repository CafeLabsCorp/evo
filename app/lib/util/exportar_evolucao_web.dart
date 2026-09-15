import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'carimbo_de_data.dart';

/// Implementação de verdade — só compilada quando o alvo é Web (ver o
/// export condicional em `exportar_evolucao.dart`). `package:web` no lugar
/// de `dart:html`: o app é 100% Web (Etapa 0 do handoff só configura a
/// plataforma web), mas `dart:html` ainda dispara o lint
/// `avoid_web_libraries_in_flutter` do `flutter_lints` — `package:web` é o
/// caminho atual sem esse aviso.
void baixarJsonComoArquivo({
  required String nomeBaseArquivo,
  required Map<String, dynamic> json,
}) {
  final String conteudo = const JsonEncoder.withIndent('  ').convert(json);
  final String nomeArquivo = '$nomeBaseArquivo-${carimboDeData(DateTime.now())}.json';

  final web.Blob blob = web.Blob(
    <JSAny>[conteudo.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final String url = web.URL.createObjectURL(blob);
  final web.HTMLAnchorElement ancora = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = nomeArquivo
    ..style.display = 'none';
  web.document.body!.append(ancora);
  ancora.click();
  ancora.remove();
  web.URL.revokeObjectURL(url);
}
