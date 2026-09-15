/// Chave fracionária de reordenação — a técnica que permite inserir uma
/// parte entre duas vizinhas sem reescrever a ordem de nenhuma outra.
///
/// Funções puras, sem I/O e sem estado: testáveis sem banco (ver
/// `test/ordem_fracionaria_test.dart`).
///
/// Convenção: `ordem` é `double`. A primeira parte de uma evolução vazia
/// recebe [primeiraOrdem]; inserir no fim usa [ordemNoFim]; no início,
/// [ordemNoInicio]; entre duas partes existentes, [ordemNoMeio].
library;

import 'dart:math' as math;

/// Ordem da primeira parte de uma evolução vazia.
double primeiraOrdem() => 1.0;

/// Ordem de uma nova parte inserida DEPOIS de todas as existentes.
///
/// Soma, nunca multiplica nem divide: somar 1.0 nunca converge para um
/// limite (a ordem cresce sem teto, então inserir sempre no fim nunca
/// esgota o espaço fracionário) — diferente de [ordemNoMeio], que converge
/// para o vizinho a cada bisseção.
double ordemNoFim(double ultima) => ultima + 1.0;

/// Ordem de uma nova parte inserida ANTES de todas as existentes.
///
/// Subtrai, pelo mesmo motivo de [ordemNoFim]: subtrair 1.0 do menor valor
/// atual nunca converge para ele. Dividir (`primeira / 2`, por exemplo)
/// converge para zero e, pior, não faz sentido nenhum se `primeira` for
/// negativa — é exatamente o erro que esta função existe para evitar.
double ordemNoInicio(double primeira) => primeira - 1.0;

/// Ordem de uma nova parte inserida ENTRE as vizinhas [a] e [b] (`a < b`).
///
/// Ponto médio aritmético — a única operação que cabe aqui, porque as duas
/// partes já têm ordens concretas dos dois lados (não há "ponta" para somar
/// ou subtrair). Chame [ordemEsgotada] ANTES de usar este valor: perto do
/// limite de precisão de `double`, o ponto médio pode colapsar de volta em
/// [a] ou [b], o que quebraria a ordenação silenciosamente.
double ordemNoMeio(double a, double b) => (a + b) / 2;

/// `true` quando o espaço fracionário entre [a] e [b] (`a < b`) está
/// esgotado — ou seja, quando não é mais seguro usar [ordemNoMeio](a, b)
/// para inserir uma nova parte ali, e a coleção precisa ser renormalizada
/// (`1.0, 2.0, 3.0, ...`) antes de inserir.
///
/// O teste é RELATIVO (`1e-9 * max(1.0, a.abs())`), não um limiar absoluto:
/// um limiar absoluto (ex.: `b - a < 1e-9`) erra assim que `ordem` deriva
/// para a casa de `1e6` — a essa escala, `1e-9` absoluto é muito menor que
/// o ULP de `double` ali, e a checagem nunca dispara mesmo já tendo
/// esgotado a precisão disponível.
bool ordemEsgotada(double a, double b) {
  final double meio = ordemNoMeio(a, b);
  return meio <= a ||
      meio >= b ||
      (b - a) < 1e-9 * math.max(1.0, a.abs());
}
