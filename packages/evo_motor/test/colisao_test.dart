import 'package:evo_motor/evo_motor.dart';
import 'package:test/test.dart';

/// Constrói duas [EstadoFormacao] (antes/depois de um único tique) a partir
/// de posição inicial + deslocamento-no-tique de dois slots, e roda
/// `verificarColisoes` sobre elas. As coordenadas aqui são as mesmas
/// unidades que `EstadoPessoa.x`/`y` usam sempre (quartos-de-célula) —
/// os valores da tabela da spec já vêm nessa unidade (os limiares do
/// checker, derivados de `unidadesPorCelula`, batem com eles direto).
List<Diagnostico> _colidir(
  (int, int) a0,
  (int, int) va,
  (int, int) b0,
  (int, int) vb,
) {
  final EstadoFormacao antes = EstadoFormacao(<int, EstadoPessoa>{
    0: EstadoPessoa(x: a0.$1, y: a0.$2, dir: 0, cad: Cadencia.marchando),
    1: EstadoPessoa(x: b0.$1, y: b0.$2, dir: 0, cad: Cadencia.marchando),
  });
  final EstadoFormacao depois = EstadoFormacao(<int, EstadoPessoa>{
    0: EstadoPessoa(
      x: a0.$1 + va.$1,
      y: a0.$2 + va.$2,
      dir: 0,
      cad: Cadencia.marchando,
    ),
    1: EstadoPessoa(
      x: b0.$1 + vb.$1,
      y: b0.$2 + vb.$2,
      dir: 0,
      cad: Cadencia.marchando,
    ),
  });
  return verificarColisoes(<EstadoFormacao>[antes, depois]);
}

void main() {
  group('Checagem 3 — Colisão: 7 casos da tabela da spec', () {
    test('1. Travessia (troca de célula): dmin²=0, erro', () {
      final List<Diagnostico> diags = _colidir((0, 0), (2, 0), (4, 0), (-2, 0));
      final colisoes = diags.whereType<DiagnosticoColisao>().toList();
      expect(colisoes, hasLength(1));
      expect(colisoes.first.severidade, SeveridadeDiagnostico.erro);
      expect(colisoes.first.distanciaMinimaQuadradoQuartos, 0);
    });

    test(
      '2. Cruzamento no meio do tique: dmin²=0, erro — só a fórmula '
      'contínua pega (as pontas dão dist²=2 nos dois extremos)',
      () {
        final List<Diagnostico> diags = _colidir(
          (0, 1),
          (2, 0),
          (1, 0),
          (0, 2),
        );
        final colisoes = diags.whereType<DiagnosticoColisao>().toList();
        expect(colisoes, hasLength(1));
        expect(colisoes.first.severidade, SeveridadeDiagnostico.erro);
        expect(colisoes.first.distanciaMinimaQuadradoQuartos, 0);
      },
    );

    test('3. Formação em diagonal em uníssono, D=0: dmin²=32, ok', () {
      final List<Diagnostico> diags = _colidir((0, 0), (1, 1), (4, 4), (1, 1));
      expect(diags.whereType<DiagnosticoColisao>(), isEmpty);
    });

    test(
      '4. Coluna em fila, espaçamento exato de 1 célula: dmin²=16, ok — '
      'sentinela da desigualdade estrita (< vira aviso ruidoso se virar ≤)',
      () {
        final List<Diagnostico> diags = _colidir(
          (0, 0),
          (2, 0),
          (0, 4),
          (2, 0),
        );
        expect(diags.whereType<DiagnosticoColisao>(), isEmpty);
      },
    );

    test(
      '5. Dois slots sobrepostos, sem velocidade relativa (D=0): dmin²=0, '
      'erro, sem lançar exceção de divisão por zero',
      () {
        final List<Diagnostico> diags = _colidir(
          (0, 0),
          (0, 0),
          (0, 0),
          (0, 0),
        );
        final colisoes = diags.whereType<DiagnosticoColisao>().toList();
        expect(colisoes, hasLength(1));
        expect(colisoes.first.severidade, SeveridadeDiagnostico.erro);
        expect(colisoes.first.distanciaMinimaQuadradoQuartos, 0);
      },
    );

    test(
      '6a. Clamp em s*=0 (afastando-se, s* bruto seria −2,5): dmin²=25, ok',
      () {
        final List<Diagnostico> diags = _colidir(
          (0, 0),
          (-2, 0),
          (5, 0),
          (0, 0),
        );
        expect(diags.whereType<DiagnosticoColisao>(), isEmpty);
      },
    );

    test(
      '6b. Clamp em s*=1 com N>D (o clamp corta de verdade): dmin²=4, erro',
      () {
        final List<Diagnostico> diags = _colidir(
          (0, 0),
          (2, 0),
          (6, 0),
          (-2, 0),
        );
        final colisoes = diags.whereType<DiagnosticoColisao>().toList();
        expect(colisoes, hasLength(1));
        expect(colisoes.first.severidade, SeveridadeDiagnostico.erro);
        expect(colisoes.first.distanciaMinimaQuadradoQuartos, 4);
      },
    );
  });

  test(
    'Guarda de overflow: |Δp|²×|Δv|² no pior caso plausível fica muito '
    'abaixo de 2^53−1 (Flutter Web / int-como-double do JS)',
    () {
      // Pior caso plausível hoje: campo de 20 células (80 quartos) por
      // eixo — dois slots em cantos opostos — e uma velocidade relativa
      // folgada (bem maior que qualquer movimento do catálogo produz num
      // só tique). Rede de segurança pra quando `unidadesPorCelula`, o
      // tamanho do grid, ou a unidade de medida mudarem.
      const int maiorDeltaPPorEixo = 80; // quartos — campo 20x20 inteiro.
      const int maiorDeltaVPorEixo = 8; // quartos/tique — bem folgado.
      final int dpSq = maiorDeltaPPorEixo * maiorDeltaPPorEixo * 2; // 2 eixos
      final int dvSq = maiorDeltaVPorEixo * maiorDeltaVPorEixo * 2;
      final int piorCaso = dpSq * dvSq;
      expect(piorCaso, lessThan(9007199254740991));
    },
  );
}
