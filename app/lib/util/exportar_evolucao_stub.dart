/// Stub — nunca usado em produção (o app só roda em Web, Etapa 0 do
/// handoff). Existe só para que `flutter test` (que compila para a VM, não
/// para Web, mesmo num app Web-only) consiga RESOLVER este import sem
/// falhar: `package:web`/`dart:js_interop` (usados na implementação real,
/// `exportar_evolucao_web.dart`) simplesmente não compilam sob o alvo VM —
/// não é sobre não invocar a função em teste, é sobre nem conseguir
/// COMPILAR o arquivo que a importa transitivamente. Ver o export
/// condicional em `exportar_evolucao.dart`.
void baixarJsonComoArquivo({
  required String nomeBaseArquivo,
  required Map<String, dynamic> json,
}) {
  throw UnsupportedError(
    'baixarJsonComoArquivo só é suportado em Flutter Web — chamado fora dele.',
  );
}
