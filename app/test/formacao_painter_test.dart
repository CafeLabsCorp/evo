import 'package:evo_app/pintura/formacao_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cobre a correção de 2026-09-14: célula de tamanho fixo (36px) não cabia
/// no retrato de um celular pro campo padrão 20×20, e boa parte do pelotão
/// era desenhada fora da área visível. A partir daqui a escala é derivada
/// do `size` real e de um enquadramento de conteúdo (bounding box de toda a
/// faixa em reprodução, não só o tique atual) — estes testes cobrem só a
/// matemática pura de [TransformacaoEnquadramento], sem precisar montar um
/// `Canvas`/`CustomPaint` de verdade (isso é coberto pelos testes de
/// widget em `widget_test.dart`, que verificam o [Rect] real vindo do
/// `ControladorPlayback` pra evolução de exemplo).
void main() {
  group('TransformacaoEnquadramento.calcular', () {
    test(
      'escolhe a escala que faz a caixa (com margem) caber inteira na tela, '
      'usando o eixo mais restritivo',
      () {
        // Conteúdo 4×4 células (formação 5×5, ex.: coluna 0..4 x linha
        // 0..4 -> width=4, height=4), tela retrato bem mais alta que
        // larga.
        final TransformacaoEnquadramento t =
            TransformacaoEnquadramento.calcular(
              enquadramento: const Rect.fromLTRB(0, 0, 4, 4),
              tela: const Size(390, 800),
              margemCelulas: 0.5,
              escalaMinimaPx: 18,
              escalaMaximaPx: 72,
            );

        // Caixa com margem: 5x5 células. Eixo restritivo é a largura:
        // 390 / 5 = 78 -> excede o teto de 72, então clampa em 72.
        expect(t.tamanhoCelulaPx, 72);
        expect(t.centroColuna, 2); // centro de [0,4] com margem simétrica
        expect(t.centroLinha, 2);
      },
    );

    test('clampa no piso quando a caixa é grande demais pra tela', () {
      // Evolução completa "real" (linha -8..9, coluna 0..6) — mesma ordem
      // de grandeza medida na evolução de exemplo em modo "evolução
      // completa".
      final TransformacaoEnquadramento t =
          TransformacaoEnquadramento.calcular(
            enquadramento: const Rect.fromLTRB(0, -8, 6, 9),
            tela: const Size(390, 500),
            margemCelulas: 0.5,
            escalaMinimaPx: 18,
            escalaMaximaPx: 72,
          );

      // Caixa com margem: largura 7, altura 18. 390/7≈55.7, 500/18≈27.8 —
      // eixo restritivo é a altura, e mesmo assim fica acima do piso aqui;
      // este teste garante que o piso existe e é respeitado quando a conta
      // ficar abaixo dele (tela mais apertada).
      final TransformacaoEnquadramento apertado =
          TransformacaoEnquadramento.calcular(
            enquadramento: const Rect.fromLTRB(0, -8, 6, 9),
            tela: const Size(200, 200),
            margemCelulas: 0.5,
            escalaMinimaPx: 18,
            escalaMaximaPx: 72,
          );
      expect(t.tamanhoCelulaPx, closeTo(500 / 18, 0.01));
      expect(apertado.tamanhoCelulaPx, 18); // 200/18≈11.1 < piso -> clampa
    });

    test(
      'clampa no teto quando só uma pessoa/área minúscula está em jogo — '
      'não vira um bloco gigante fora de proporção',
      () {
        final TransformacaoEnquadramento t =
            TransformacaoEnquadramento.calcular(
              enquadramento: const Rect.fromLTRB(0, 0, 0, 0),
              tela: const Size(390, 700),
              margemCelulas: 0.5,
              escalaMinimaPx: 18,
              escalaMaximaPx: 72,
            );

        // Caixa com margem 1x1 célula; sem teto daria min(390,700) = 390px
        // de célula — absurdo. Com teto, fica em 72.
        expect(t.tamanhoCelulaPx, 72);
      },
    );

    test(
      'o centro é o centro da caixa de conteúdo, não o centro da tela nem '
      'a origem do campo',
      () {
        final TransformacaoEnquadramento t =
            TransformacaoEnquadramento.calcular(
              enquadramento: const Rect.fromLTRB(2, 3, 6, 7),
              tela: const Size(390, 390),
              margemCelulas: 0.5,
              escalaMinimaPx: 18,
              escalaMaximaPx: 72,
            );

        expect(t.centroColuna, 4);
        expect(t.centroLinha, 5);
      },
    );
  });
}
