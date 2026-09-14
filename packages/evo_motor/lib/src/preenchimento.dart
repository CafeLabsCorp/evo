import 'cadencia.dart';
import 'segmento.dart';

/// Preenchimento: como um slot passa o tempo antes do `offsetInicialTiques`
/// de uma [Atribuicao] (esperando a deixa) e depois que o movimento
/// termina (até a parte fechar em `T`). Mesmo tipo cobre os dois lados —
/// ver `Atribuicao.preenchimento` na spec.
///
/// Todo `Preenchimento` sabe gerar exatamente `tiques` tiques (sempre par —
/// 1 tempo = 2 tiques, e `T` já vem arredondado para par) para uma dada
/// cadência sustentada.
sealed class Preenchimento {
  const Preenchimento();

  Cadencia get cadencia;

  List<Segmento> segmentosPara(int tiques) {
    if (tiques == 0) return const <Segmento>[];
    if (tiques.isOdd) {
      throw ArgumentError(
        'Preenchimento pedido para $tiques tiques (ímpar) — toda duração '
        'no motor é múltipla de 1 tempo (2 tiques); T de uma parte já vem '
        'arredondado para par exatamente para evitar isso.',
      );
    }
    return _segmentos(tiques ~/ 2);
  }

  List<Segmento> _segmentos(int tempos);

  /// Preenchimento default para uma cadência: a continuação "natural" dela
  /// — nunca hardcoded para `firme`. `marchando` continua avançando no
  /// facing corrente (é o `EmFrenteMarche(T/2, aoTerminar: marchando)` da
  /// continuação implícita); as cadências paradas simplesmente seguram.
  factory Preenchimento.paraCadencia(Cadencia cadencia) => switch (cadencia) {
    Cadencia.firme => const PreenchimentoFirme(),
    Cadencia.descansar => const PreenchimentoDescansar(),
    Cadencia.marcandoPasso => const PreenchimentoMarcandoPasso(),
    Cadencia.marchando => const PreenchimentoMarchando(),
  };
}

class PreenchimentoFirme extends Preenchimento {
  const PreenchimentoFirme();

  @override
  Cadencia get cadencia => Cadencia.firme;

  @override
  List<Segmento> _segmentos(int tempos) => <Segmento>[Pausa(tempos)];
}

class PreenchimentoDescansar extends Preenchimento {
  const PreenchimentoDescansar();

  @override
  Cadencia get cadencia => Cadencia.descansar;

  @override
  List<Segmento> _segmentos(int tempos) => <Segmento>[Pausa(tempos)];
}

class PreenchimentoMarcandoPasso extends Preenchimento {
  const PreenchimentoMarcandoPasso();

  @override
  Cadencia get cadencia => Cadencia.marcandoPasso;

  @override
  List<Segmento> _segmentos(int tempos) => <Segmento>[
    Pausa(tempos, bateRitmo: true),
  ];
}

class PreenchimentoMarchando extends Preenchimento {
  const PreenchimentoMarchando();

  @override
  Cadencia get cadencia => Cadencia.marchando;

  @override
  List<Segmento> _segmentos(int tempos) => <Segmento>[Avanco(tempos)];
}
