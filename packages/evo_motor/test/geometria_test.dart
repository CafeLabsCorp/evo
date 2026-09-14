import 'package:evo_motor/evo_motor.dart';
import 'package:test/test.dart';

void main() {
  group('unidadesPorCelula', () {
    test(
      'é a única constante consistente com a tabela de deslocamento por tique '
      '(spec executável — pina U=4, não deixe alguém "aumentar por garantia")',
      () {
        // Passo ortogonal: 2 unidades/tique (tabela, setor 0/2/4/6) × 2
        // tiques/tempo tem que dar EXATAMENTE 1 célula por tempo.
        const int orthoPorTiqueTabela = 2;
        final int orthoPorTempo = orthoPorTiqueTabela * 2;
        expect(
          orthoPorTempo,
          unidadesPorCelula,
          reason:
              'Com U != 4, "passo ortogonal = 1 célula/tempo" deixa de valer.',
        );

        // Passo diagonal: 1 unidade/tique/eixo (tabela, setores ímpares) ×
        // 2 tiques/tempo tem que dar EXATAMENTE meia célula por eixo, por
        // tempo — e essa metade só é um número inteiro de quartos se
        // unidadesPorCelula for divisível por 4.
        const int diagonalPorTiqueTabelaPorEixo = 1;
        final int diagonalPorTempoPorEixo = diagonalPorTiqueTabelaPorEixo * 2;
        expect(
          diagonalPorTempoPorEixo * 2,
          unidadesPorCelula,
          reason:
              'Com U != 4, o meio-passo diagonal não cai numa fronteira '
              'de quarto-de-célula inteira.',
        );

        expect(unidadesPorCelula, 4);
      },
    );

    test(
      'U par é exigido pelo passo ortogonal, U divisível por 4 pelo diagonal',
      () {
        expect(unidadesPorCelula % 2, 0);
        expect(unidadesPorCelula % 4, 0);
      },
    );
  });

  group('deltaPorTiquePorSetor', () {
    test('tem exatamente 8 entradas, uma por setor', () {
      expect(deltaPorTiquePorSetor.length, 8);
    });

    test('setores pares (ortogonais) só mexem um eixo, com módulo 2', () {
      for (final int setor in <int>[0, 2, 4, 6]) {
        final (int dx, int dy) = deltaPorTiquePorSetor[setor];
        expect(
          dx == 0 || dy == 0,
          isTrue,
          reason: 'setor $setor deveria ser puro em um eixo',
        );
        expect(dx.abs() + dy.abs(), 2);
      }
    });

    test('setores ímpares (diagonais) mexem os dois eixos, 1 unidade cada', () {
      for (final int setor in <int>[1, 3, 5, 7]) {
        final (int dx, int dy) = deltaPorTiquePorSetor[setor];
        expect(dx.abs(), 1);
        expect(dy.abs(), 1);
      }
    });

    test('tabela bate exatamente com a spec, valor a valor', () {
      expect(deltaPorTiquePorSetor, <(int, int)>[
        (0, -2),
        (1, -1),
        (2, 0),
        (1, 1),
        (0, 2),
        (-1, 1),
        (-2, 0),
        (-1, -1),
      ]);
    });
  });

  group('normalizarSetor', () {
    test('mantém 0..7 intocado', () {
      for (int s = 0; s < 8; s++) {
        expect(normalizarSetor(s), s);
      }
    });

    test('enrola positivos e negativos', () {
      expect(normalizarSetor(8), 0);
      expect(normalizarSetor(9), 1);
      expect(normalizarSetor(-1), 7);
      expect(normalizarSetor(-4), 4);
      expect(normalizarSetor(-8), 0);
    });
  });

  group('Posicao', () {
    test('celula() e quartos() concordam na conversão', () {
      final Posicao a = Posicao.celula(3, 5);
      expect(a.yQuartos, 3 * unidadesPorCelula);
      expect(a.xQuartos, 5 * unidadesPorCelula);
      expect(a.emCelulas(), (3.0, 5.0));
    });

    test('celulaExata() devolve a célula quando alinhado', () {
      final Posicao a = Posicao.celula(2, 7);
      expect(a.celulaExata(), (2, 7));
    });

    test(
      'celulaExata() LANÇA para posição intermediária (fronteira de serialização)',
      () {
        // Meio passo diagonal: 2 quartos num eixo, não múltiplo de 4.
        final Posicao intermediaria = Posicao.quartos(2, 0);
        expect(() => intermediaria.celulaExata(), throwsStateError);
      },
    );

    test('igualdade estrutural', () {
      expect(Posicao.quartos(1, 2), Posicao.quartos(1, 2));
      expect(Posicao.quartos(1, 2) == Posicao.quartos(1, 3), isFalse);
    });
  });
}
