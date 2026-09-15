import 'package:evo_app/editor/descritores_movimento.dart';
import 'package:evo_motor/evo_motor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('descritoresCatalogo — fonte única dos 16 tipos', () {
    test('16 entradas, tipos únicos, todos batem com um `tipo` real do '
        'catálogo (materializar não lança)', () {
      expect(descritoresCatalogo, hasLength(16));
      expect(
        descritoresCatalogo.map((DescritorMovimento d) => d.tipo).toSet(),
        hasLength(16),
      );
      for (final DescritorMovimento d in descritoresCatalogo) {
        expect(() => d.comandoSonda().materializar(), returnsNormally);
      }
    });

    test('agrupamento fixo do design: 4+1+5+6 = 16', () {
      final Map<GrupoMovimento, int> contagem = <GrupoMovimento, int>{};
      for (final DescritorMovimento d in descritoresCatalogo) {
        contagem[d.grupo] = (contagem[d.grupo] ?? 0) + 1;
      }
      expect(contagem[GrupoMovimento.semDeslocar], 4);
      expect(contagem[GrupoMovimento.deslocar], 1);
      expect(contagem[GrupoMovimento.girarParado], 5);
      expect(contagem[GrupoMovimento.girarEmMarchaEAlto], 6);
    });
  });

  group('movimentosValidosPara — delega em Movimento.checarPrecondicao de '
      'verdade, nunca reimplementa a tabela', () {
    test('de descansar, só 2 válidos: Sentido e Marcar passo (únicos com '
        'exigido == null ou permiteTeleporteDeMarchando)', () {
      final List<String> tipos = movimentosValidosPara(
        Cadencia.descansar,
      ).map((MovimentoValido m) => m.descritor.tipo).toList();
      expect(tipos, unorderedEquals(<String>['sentido', 'marcarPasso']));
    });

    test('de marcandoPasso, 5 válidos', () {
      final List<String> tipos = movimentosValidosPara(
        Cadencia.marcandoPasso,
      ).map((MovimentoValido m) => m.descritor.tipo).toList();
      expect(
        tipos,
        unorderedEquals(<String>[
          'sentido',
          'descansar',
          'marcarPasso',
          'baterORitmo',
          'emFrenteMarche',
        ]),
      );
    });

    test('de firme, 10 válidos (os 5 de marcandoPasso + os 5 giros parados)', () {
      final List<String> tipos = movimentosValidosPara(
        Cadencia.firme,
      ).map((MovimentoValido m) => m.descritor.tipo).toList();
      expect(tipos, hasLength(10));
      expect(tipos, contains('direitaVolverParado'));
      expect(tipos, isNot(contains('alto')));
    });

    test('de marchando: checarPrecondicao real dá 10 válidos (Sentido E '
        'Descansar carregam permiteTeleporteDeMarchando=true no catálogo '
        'atual — o handoff do design contou 9, só com Sentido; a diferença '
        'é uma divergência real entre a contagem manual do design e o '
        'código, não um bug desta implementação, que delega 100% em '
        'checarPrecondicao)', () {
      final List<MovimentoValido> validos = movimentosValidosPara(Cadencia.marchando);
      expect(validos, hasLength(10));
      final MovimentoValido sentido = validos.firstWhere(
        (MovimentoValido m) => m.descritor.tipo == 'sentido',
      );
      expect(sentido.avisoTeleporte, isTrue);
      final MovimentoValido descansar = validos.firstWhere(
        (MovimentoValido m) => m.descritor.tipo == 'descansar',
      );
      expect(descansar.avisoTeleporte, isTrue);
      final MovimentoValido marcarPasso = validos.firstWhere(
        (MovimentoValido m) => m.descritor.tipo == 'marcarPasso',
      );
      expect(
        marcarPasso.avisoTeleporte,
        isFalse,
        reason: 'transicaoDeMarchandoModelada=true — não é teleporte, é '
            'transição real',
      );
    });

    test('grupo inteiro pode ficar vazio: de descansar, "Girar parado" e '
        '"Girar em marcha + Alto" não têm nenhum item válido', () {
      final Set<GrupoMovimento> grupos = movimentosValidosPara(
        Cadencia.descansar,
      ).map((MovimentoValido m) => m.descritor.grupo).toSet();
      expect(grupos, isNot(contains(GrupoMovimento.girarParado)));
      expect(grupos, isNot(contains(GrupoMovimento.girarEmMarchaEAlto)));
    });
  });

  group('movimentosValidosParaConjunto — interseção para seleção mista', () {
    test('interseção de firme+marchando é subconjunto dos dois', () {
      final Set<String> tiposFirme = movimentosValidosPara(
        Cadencia.firme,
      ).map((MovimentoValido m) => m.descritor.tipo).toSet();
      final Set<String> tiposMarchando = movimentosValidosPara(
        Cadencia.marchando,
      ).map((MovimentoValido m) => m.descritor.tipo).toSet();
      final Set<String> intersecao = movimentosValidosParaConjunto(<Cadencia>{
        Cadencia.firme,
        Cadencia.marchando,
      }).map((MovimentoValido m) => m.descritor.tipo).toSet();
      expect(intersecao, tiposFirme.intersection(tiposMarchando));
      // Nunca oferece algo que não seja seguro pra QUALQUER um dos dois —
      // ex.: "Alto" só serve marchando, nunca aparece na interseção com
      // firme.
      expect(intersecao, isNot(contains('alto')));
    });

    test('conjunto de 1 cadência só delega em movimentosValidosPara', () {
      expect(
        movimentosValidosParaConjunto(<Cadencia>{Cadencia.firme}).length,
        movimentosValidosPara(Cadencia.firme).length,
      );
    });
  });

  group('percussão — regra de bateRitmoAoJuntar', () {
    test('exatamente os 13 tipos com junção aceitam bateRitmoAoJuntar '
        '(todos menos sentido/descansar/baterORitmo)', () {
      final List<String> semJuncao = descritoresCatalogo
          .where((DescritorMovimento d) => !d.aceitaBateRitmoAoJuntar)
          .map((DescritorMovimento d) => d.tipo)
          .toList();
      expect(semJuncao, unorderedEquals(<String>['sentido', 'descansar', 'baterORitmo']));
    });
  });
}
