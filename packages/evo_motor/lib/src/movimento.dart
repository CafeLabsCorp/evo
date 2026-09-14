import 'cadencia.dart';
import 'segmento.dart';

/// Variante de encerramento de "Em frente, marche" (movimento 5 do
/// catálogo).
enum AoTerminarMarche {
  /// `A(N)`, N tempos, final marchando — a formação segue em marcha.
  marchando,

  /// `A(N)·J`, N+1 tempos, deslocamento N (a junção não anda), final
  /// marcandoPasso. Simétrico a `firme` — catálogo v2: terminar uma marcha
  /// marcando passo custa o mesmo passo de transição que "Marcar passo"
  /// (#3) cobra vindo de `marchando`.
  marcandoPasso,

  /// `A(N)·J`, N+1 tempos, deslocamento N — a junção não anda.
  firme,
}

/// Um movimento do catálogo, já resolvido em segmentos concretos.
///
/// `exigido == null` significa "qualquer" cadência de entrada é aceita.
/// `permiteTeleporteDeMarchando` é a exceção documentada no catálogo
/// (footnote ¹): mesmo quando a cadência de entrada não bate, se ela for
/// `marchando` e o movimento estiver marcado, a transição é permitida mas
/// emite um diagnóstico de aviso ("parada teleportada") em vez de cair na
/// checagem de comando impossível.
///
/// `segmentos` é uma função de `Cadencia entrada` — o mesmo mecanismo de
/// `cadenciaResultante`, generalizado. A maioria dos movimentos ignora o
/// parâmetro (segmentos fixos, independentes de como a pessoa chegou ali);
/// "Marcar passo" (#3) é o único que hoje usa isso de verdade, porque a
/// mecânica de transição a partir de `marchando` (passo extra + junção
/// antes de marcar passo no lugar) não é uma opção escolhida na
/// atribuição — é uma consequência da cadência real do slot naquele
/// ponto, então tem que ser resolvida com a cadência de entrada, não com
/// um parâmetro estático do movimento. Ver `Catalogo.marcarPasso`.
class Movimento {
  const Movimento({
    required this.nome,
    required this.exigido,
    required List<Segmento> Function(Cadencia entrada) segmentos,
    required this.cadenciaResultante,
    this.permiteTeleporteDeMarchando = false,
  }) : _segmentosPara = segmentos;

  final String nome;
  final Set<Cadencia>? exigido;
  final List<Segmento> Function(Cadencia entrada) _segmentosPara;
  final Cadencia Function(Cadencia entrada) cadenciaResultante;
  final bool permiteTeleporteDeMarchando;

  /// Segmentos concretos deste movimento para uma cadência de ENTRADA
  /// dada. Para a esmagadora maioria dos movimentos do catálogo é uma
  /// lista fixa (o parâmetro é ignorado); só varia de verdade para
  /// "Marcar passo" vindo de `marchando`.
  List<Segmento> segmentosPara(Cadencia entrada) => _segmentosPara(entrada);

  /// Duração estrutural em tiques para uma cadência de entrada dada — a
  /// duração de "Marcar passo", por exemplo, muda conforme a pessoa chega
  /// marchando ou já parada (ver `segmentosPara`); para todo o resto do
  /// catálogo essa dependência é só de fachada (o resultado não muda com
  /// `entrada`). Mesmo movimentos que acabam classificados como "comando
  /// impossível" têm uma duração bem-definida aqui, usada para calcular
  /// `T` da parte.
  int duracaoTiquesPara(Cadencia entrada) => segmentosPara(
    entrada,
  ).fold(0, (int acc, Segmento s) => acc + s.duracaoTiques);

  /// Resultado da checagem de precondição de cadência (checagem 1 —
  /// comando impossível).
  ResultadoPrecondicao checarPrecondicao(Cadencia atual) {
    final Set<Cadencia>? ex = exigido;
    if (ex == null) {
      // "qualquer" — nunca bloqueia; ainda assim, entrar vindo de
      // `marchando` é uma parada teleportada e vale aviso informativo.
      if (atual == Cadencia.marchando) {
        return const ResultadoPrecondicao(ok: true, avisoTeleporte: true);
      }
      return const ResultadoPrecondicao(ok: true, avisoTeleporte: false);
    }
    if (ex.contains(atual)) {
      return const ResultadoPrecondicao(ok: true, avisoTeleporte: false);
    }
    if (permiteTeleporteDeMarchando && atual == Cadencia.marchando) {
      return const ResultadoPrecondicao(ok: true, avisoTeleporte: true);
    }
    return const ResultadoPrecondicao(ok: false, avisoTeleporte: false);
  }
}

class ResultadoPrecondicao {
  const ResultadoPrecondicao({required this.ok, required this.avisoTeleporte});

  final bool ok;
  final bool avisoTeleporte;
}
