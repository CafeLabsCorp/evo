/// O salão/quadra onde a evolução acontece — em CÉLULAS, não relacionado
/// ao tamanho da grade da formação (uma evolução desloca o pelotão inteiro
/// pelo campo, não fica presa ao retângulo inicial da formação).
///
/// Config, não constante: cada clube tem um salão de tamanho diferente.
/// Default 20x20 com a grade centralizada em (0, 0) — ou seja, colunas de
/// -10 a 10 e linhas de -10 a 10 por default.
class Campo {
  const Campo({this.larguraCelulas = 20, this.alturaCelulas = 20});

  final int larguraCelulas;
  final int alturaCelulas;

  double get colunaMinima => -larguraCelulas / 2;
  double get colunaMaxima => larguraCelulas / 2;
  double get linhaMinima => -alturaCelulas / 2;
  double get linhaMaxima => alturaCelulas / 2;
}

/// Configuração da simulação.
class Config {
  const Config({
    this.campo = const Campo(),
    this.avisosColisaoHabilitados = true,
  });

  final Campo campo;

  /// Avisos de colisão (0,5 célula < dmin < 1,0 célula) são agregados e
  /// desligáveis — erros (dmin ≤ 0,5 célula) nunca são.
  final bool avisosColisaoHabilitados;
}
