/// Módulo de geometria do motor. Este arquivo é a spec executável da unidade
/// espacial atômica e da tabela de deslocamento por tique.
library;

/// Unidade espacial atômica: quarto-de-célula.
///
/// `4` é o MÍNIMO que funciona: deslocamento ortogonal exige `U` par (2
/// unidades/tique), deslocamento diagonal exige `U` divisível por 4 (1
/// unidade/tique por eixo, e dois tiques por tempo). Não aumente "por
/// garantia" — o teste de integralidade em `propriedades_test.dart` falha
/// deliberadamente se você trocar isso por `U=2`, para que a constante nunca
/// mude sem alguém notar.
const int unidadesPorCelula = 4;

/// Deslocamento (dx, dy) em quartos-de-célula, POR TIQUE, indexado pelo
/// setor de facing (0..7, horário, 0 = Norte). `y` cresce para o Sul.
///
/// Esta tabela é o módulo de geometria inteiro: setores pares (ortogonais)
/// andam 2 unidades no eixo único; setores ímpares (diagonais) andam 1
/// unidade por eixo — nunca os dois ao mesmo tempo com o mesmo módulo, é
/// isso que faz a diagonal ser geometricamente fiel (~0,71 célula por
/// passo) em vez de "diagonal rápida" (1 célula por passo, errado).
const List<(int dx, int dy)> deltaPorTiquePorSetor = <(int, int)>[
  (0, -2), // 0 Norte
  (1, -1), // 1 Nordeste
  (2, 0), // 2 Leste
  (1, 1), // 3 Sudeste
  (0, 2), // 4 Sul
  (-1, 1), // 5 Sudoeste
  (-2, 0), // 6 Oeste
  (-1, -1), // 7 Noroeste
];

/// Normaliza um setor para o intervalo 0..7 (mod 8), aceitando negativos.
int normalizarSetor(int setor) => setor % 8 < 0 ? setor % 8 + 8 : setor % 8;

/// Posição opaca do motor.
///
/// Existe para impor a regra não-negociável de serialização: **nenhuma
/// unidade atômica (quarto-de-célula) atravessa a fronteira de
/// serialização**. JSON e (depois) Firestore só enxergam células via
/// [Posicao.celula] / [linha], [coluna]; quartos só existem dentro do
/// pacote, através de [Posicao.quartos] e dos getters [xQuartos]/[yQuartos].
///
/// `emCelulas()` devolve `double` e serve só para render (interpolação
/// visual) — nunca para lógica de simulação, que é sempre inteira.
class Posicao {
  const Posicao._(this.xQuartos, this.yQuartos);

  /// Constrói a partir de uma célula de grade (o que entra/sai de JSON).
  /// `linha` cresce para o Sul, `coluna` para o Leste — mesma convenção de
  /// `x`/`y` em quartos.
  factory Posicao.celula(int linha, int coluna) =>
      Posicao._(coluna * unidadesPorCelula, linha * unidadesPorCelula);

  /// Constrói a partir de quartos-de-célula. Uso interno do motor
  /// (compilador/simulador); nunca deve ser chamado a partir de código de
  /// (des)serialização.
  factory Posicao.quartos(int x, int y) => Posicao._(x, y);

  /// Quartos-de-célula no eixo Leste-Oeste (Leste positivo).
  final int xQuartos;

  /// Quartos-de-célula no eixo Norte-Sul (Sul positivo).
  final int yQuartos;

  /// Representação em células, como `double`. Só para render/UI — nunca
  /// para lógica de simulação.
  (double linha, double coluna) emCelulas() =>
      (yQuartos / unidadesPorCelula, xQuartos / unidadesPorCelula);

  /// Célula inteira, exigindo que a posição caia exatamente numa célula
  /// (usado para serializar de volta pra JSON, ex. estado inicial de uma
  /// evolução). Lança [StateError] se a posição estiver fora de uma
  /// fronteira de célula — isso é o teste que "falha se alguém serializar
  /// quartos": qualquer posição intermediária não tem `linha`/`coluna`
  /// inteiros para oferecer.
  (int linha, int coluna) celulaExata() {
    if (xQuartos % unidadesPorCelula != 0 ||
        yQuartos % unidadesPorCelula != 0) {
      throw StateError(
        'Posicao($xQuartos, $yQuartos) em quartos não cai numa fronteira de '
        'célula inteira — não pode ser serializada como {linha, coluna}. '
        'Isso é esperado para posições intermediárias de uma evolução em '
        'andamento; só o estado inicial/final gravado deve ser serializado.',
      );
    }
    return (yQuartos ~/ unidadesPorCelula, xQuartos ~/ unidadesPorCelula);
  }

  Posicao somar(int dx, int dy) => Posicao._(xQuartos + dx, yQuartos + dy);

  @override
  bool operator ==(Object other) =>
      other is Posicao &&
      other.xQuartos == xQuartos &&
      other.yQuartos == yQuartos;

  @override
  int get hashCode => Object.hash(xQuartos, yQuartos);

  @override
  String toString() => 'Posicao(x: ${xQuartos}q, y: ${yQuartos}q)';
}
