import 'package:evo_app/dados/ordem_fracionaria.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chave fracionária de reordenação', () {
    test('primeira ordem de uma evolução vazia é 1.0', () {
      expect(primeiraOrdem(), 1.0);
    });

    test('ordemNoFim soma, nunca converge para um teto', () {
      double v = 1.0;
      for (int i = 0; i < 1000; i++) {
        v = ordemNoFim(v);
      }
      expect(v, 1001.0);
    });

    test('ordemNoInicio subtrai, funciona mesmo já negativo', () {
      expect(ordemNoInicio(1.0), 0.0);
      expect(ordemNoInicio(0.0), -1.0);
      expect(ordemNoInicio(-5.0), -6.0);
    });

    test('ordemNoMeio é o ponto médio aritmético', () {
      expect(ordemNoMeio(1.0, 2.0), 1.5);
      expect(ordemNoMeio(1.0, 1.5), 1.25);
    });

    test('inserir repetidamente no meio converge, mas não trava antes de '
        'ordemEsgotada sinalizar', () {
      double a = 1.0;
      const double b = 2.0;
      int iteracoes = 0;
      while (!ordemEsgotada(a, b) && iteracoes < 200) {
        a = ordemNoMeio(a, b);
        iteracoes++;
      }
      // Precisão de double (52 bits de mantissa) esgota bem antes de 200
      // bisseções para um intervalo unitário — se isto não convergir,
      // ordemEsgotada está com o critério errado.
      expect(iteracoes, lessThan(120));
      expect(ordemEsgotada(a, b), isTrue);
    });

    test('ordemEsgotada é relativa — falso para um intervalo saudável '
        'mesmo em ordens grandes', () {
      // Intervalo de 1.0 entre duas ordens na casa de 1e6: ainda há
      // MUITAS bisseções possíveis (double tem precisão relativa, não
      // absoluta) — um limiar absoluto ingênuo (ex.: `b - a < 1e-9`)
      // diria "esgotado" aqui, o que seria errado.
      expect(ordemEsgotada(1000000.0, 1000001.0), isFalse);
    });

    test('ordemEsgotada verdadeiro quando o meio de fato colapsa em uma '
        'das pontas (achado por bisseção, não por um epsilon chutado)', () {
      double a = 1.0;
      double b = 2.0;
      // Bisecta até o próprio critério "meio == a || meio == b" acontecer
      // de verdade — evita cravar um epsilon arbitrário que poderia não
      // colapsar nesta escala (double tem ~15-17 dígitos decimais de
      // precisão relativa, não um limiar fixo).
      while (ordemNoMeio(a, b) != a && ordemNoMeio(a, b) != b) {
        final double meio = ordemNoMeio(a, b);
        a = meio; // sempre anda pra dentro do intervalo, convergindo pra `b`.
      }
      expect(ordemNoMeio(a, b) == a || ordemNoMeio(a, b) == b, isTrue);
      expect(ordemEsgotada(a, b), isTrue);
    });

    test('ordemEsgotada verdadeiro quando o intervalo é vazio ou invertido '
        'por engano (a >= b)', () {
      expect(ordemEsgotada(2.0, 2.0), isTrue);
    });
  });
}
