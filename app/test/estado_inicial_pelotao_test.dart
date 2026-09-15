import 'package:evo_app/dados/estado_inicial_pelotao.dart';
import 'package:evo_app/dados/repositorio_evo.dart';
import 'package:evo_app/dados/validacao_espelho.dart';
import 'package:evo_motor/evo_motor.dart';
import 'package:flutter_test/flutter_test.dart';

/// `estadoInicialDoGrid` é o único produtor de `EvolucaoDoc.estadoInicial`
/// no caminho de criação (`TelaCriarEvolucao`). Este teste usa o mesmo
/// validador-espelho que a escrita real usa (`validarEvolucao`, ver
/// `RepositorioEvoFirestore.gravarEvolucao`) para confirmar, sem precisar de
/// rede/emulador, que o documento produzido bate com o que
/// `firestore.rules` exige — e usa o motor de verdade (`estadoFormacaoDoJson`
/// + `simular`) para confirmar que o formato é literalmente o que o resto do
/// produto (editor, playback) sabe consumir.
void main() {
  PelotaoDoc pelotao({required int linhas, required int colunas, Map<String, String>? rotulos}) {
    final DateTime agora = DateTime.now();
    return PelotaoDoc(
      id: 'pelotao-1',
      nome: 'Exemplo',
      linhas: linhas,
      colunas: colunas,
      rotulos: rotulos ?? const <String, String>{},
      criadoEm: agora,
      atualizadoEm: agora,
    );
  }

  EvolucaoDoc evolucaoCom(Map<String, dynamic> estadoInicial) {
    final DateTime agora = DateTime.now();
    return EvolucaoDoc(
      id: 'evo-1',
      nome: 'Teste',
      pelotaoId: 'pelotao-1',
      estadoInicial: estadoInicial,
      versaoCatalogo: versaoCatalogo,
      criadoEm: agora,
      atualizadoEm: agora,
    );
  }

  group('estadoInicialDoGrid — todos os tamanhos de grid válidos passam no '
      'validador-espelho (o mesmo que a regra do servidor)', () {
    for (int lado = 1; lado <= maxLinhasOuColunas; lado++) {
      test('grid ${lado}x$lado', () {
        final PelotaoDoc p = pelotao(linhas: lado, colunas: lado);
        final Map<String, dynamic> estado = estadoInicialDoGrid(p);
        final String? motivo = validarEvolucao(evolucaoCom(estado), clubId: 'clube-1');
        expect(motivo, isNull, reason: motivo);
      });
    }

    test('grid retangular (não quadrado) também passa', () {
      final PelotaoDoc p = pelotao(linhas: 2, colunas: 6);
      final String? motivo = validarEvolucao(
        evolucaoCom(estadoInicialDoGrid(p)),
        clubId: 'clube-1',
      );
      expect(motivo, isNull, reason: motivo);
    });
  });

  test('inclui TODOS os slots do grid, com ou sem rótulo', () {
    final PelotaoDoc p = pelotao(
      linhas: 2,
      colunas: 3,
      rotulos: const <String, String>{'0': 'Alfa'}, // só o slot 0 tem rótulo
    );
    final Map<String, dynamic> slots =
        estadoInicialDoGrid(p)['slots'] as Map<String, dynamic>;
    expect(slots.keys.toSet(), <String>{'0', '1', '2', '3', '4', '5'});
  });

  test('slot i cai em (linha, coluna) = (i ~/ colunas, i % colunas) — a '
      'mesma fórmula de ControladorEditorPartes.linhaDoSlot/colunaDoSlot', () {
    final PelotaoDoc p = pelotao(linhas: 2, colunas: 3);
    final Map<String, dynamic> slots =
        estadoInicialDoGrid(p)['slots'] as Map<String, dynamic>;
    expect(slots['4'], <String, dynamic>{
      'linha': 1,
      'coluna': 1,
      'setor': 0,
      'cadencia': 'firme',
    });
  });

  test('todo mundo firme, setor 0 (Norte) — a formação de partida antes do '
      'primeiro comando', () {
    final PelotaoDoc p = pelotao(linhas: 3, colunas: 3);
    final Map<String, dynamic> estado = estadoInicialDoGrid(p);
    final EstadoFormacao formacao = estadoFormacaoDoJson(estado);
    for (final int slot in formacao.slots) {
      expect(formacao[slot].cad, Cadencia.firme);
      expect(formacao[slot].dir, 0);
    }
  });

  test('grid 6x6 cheio (36 slots) não estoura o teto de slots do orçamento '
      'de expressões da regra', () {
    final PelotaoDoc p = pelotao(linhas: 6, colunas: 6);
    final Map<String, dynamic> slots =
        estadoInicialDoGrid(p)['slots'] as Map<String, dynamic>;
    expect(slots.length, maxSlots);
  });
}
