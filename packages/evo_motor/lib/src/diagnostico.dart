import 'cadencia.dart';

enum SeveridadeDiagnostico { aviso, erro }

/// Um problema encontrado por uma das quatro checagens. Nunca faz
/// `compilar`/`simular` abortar — o resultado sempre é produzido por
/// inteiro; diagnósticos só se acumulam para o editor mostrar.
sealed class Diagnostico {
  const Diagnostico({required this.severidade});

  final SeveridadeDiagnostico severidade;
}

/// Checagem 1 — Comando impossível: um slot recebeu um movimento cuja
/// cadência de entrada exigida não bate com a cadência corrente do slot
/// naquele ponto da parte. O slot cai na continuação implícita da
/// cadência atual para a duração estrutural do movimento pedido.
class DiagnosticoComandoImpossivel extends Diagnostico {
  const DiagnosticoComandoImpossivel({
    required this.indiceParte,
    required this.slot,
    required this.nomeMovimento,
    required this.cadenciaExigida,
    required this.cadenciaAtual,
    super.severidade = SeveridadeDiagnostico.erro,
  });

  final int indiceParte;
  final int slot;
  final String nomeMovimento;

  /// `null` quando o movimento aceita "qualquer" cadência (a exigência
  /// falhou só pela regra de teleporte a partir de `marchando`, ver
  /// footnote do catálogo).
  final Set<Cadencia>? cadenciaExigida;
  final Cadencia cadenciaAtual;

  @override
  String toString() =>
      'Comando impossível na parte $indiceParte, slot $slot: '
      '"$nomeMovimento" exige $cadenciaExigida, cadência atual é '
      '$cadenciaAtual ($severidade).';
}

/// Checagem 2 — Encadeamento: o fim de uma evolução/parte não bate com o
/// início exigido da próxima, em posição, direção, cadência, ou no
/// conjunto de slots presentes.
///
/// Severidade é `erro` por padrão, com uma exceção deliberada: um slot
/// NOVO aparecendo (ausente no fim desta evolução, exigido no início da
/// próxima) é `aviso` — pode ser a entrada legítima de um membro novo do
/// pelotão, não necessariamente um erro de planejamento. Um slot
/// desaparecendo, ou qualquer divergência de posição/direção/cadência de
/// um slot que continua presente nos dois lados, continua `erro`.
class DiagnosticoEncadeamento extends Diagnostico {
  const DiagnosticoEncadeamento({
    required this.slot,
    required this.motivo,
    super.severidade = SeveridadeDiagnostico.erro,
  });

  final int slot;
  final String motivo;

  @override
  String toString() => 'Encadeamento ($severidade) no slot $slot: $motivo';
}

/// Checagem 3 — Colisão: distância mínima contínua entre dois slots
/// durante um tique caiu abaixo do limiar de erro ou de aviso.
class DiagnosticoColisao extends Diagnostico {
  const DiagnosticoColisao({
    required this.tique,
    required this.slotA,
    required this.slotB,
    required this.distanciaMinimaQuadradoQuartos,
    required super.severidade,
  });

  final int tique;
  final int slotA;
  final int slotB;

  /// dmin² em quartos², já convertido — dividir por `unidadesPorCelula²`
  /// para obter células².
  final int distanciaMinimaQuadradoQuartos;

  @override
  String toString() =>
      'Colisão ($severidade) no tique $tique entre slots $slotA e $slotB: '
      'dmin² = $distanciaMinimaQuadradoQuartos quartos².';
}

/// Checagem 4 — Fora dos limites: um slot saiu do campo configurado num
/// tique.
class DiagnosticoForaDosLimites extends Diagnostico {
  const DiagnosticoForaDosLimites({
    required this.tique,
    required this.slot,
    required this.linha,
    required this.coluna,
  }) : super(severidade: SeveridadeDiagnostico.erro);

  final int tique;
  final int slot;
  final double linha;
  final double coluna;

  @override
  String toString() =>
      'Fora dos limites no tique $tique, slot $slot: ($linha, $coluna).';
}
