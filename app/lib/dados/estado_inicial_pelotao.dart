import 'modelos/pelotao_doc.dart';

/// Deriva o `estadoInicial` de uma evolução NOVA a partir do grid de um
/// pelotão — a formação de partida antes do primeiro comando: todo mundo
/// parado (`firme`), virado para o mesmo lado (setor 0, Norte), cada slot na
/// célula que corresponde à sua posição no grid.
///
/// Slot `i` mapeia para `(linha, coluna) = (i ~/ colunas, i % colunas)` —
/// MESMA fórmula usada em `ControladorEditorPartes.linhaDoSlot`/
/// `colunaDoSlot`, que é quem os chips "Fileira N"/"Coluna N" do editor
/// consultam. Divergir daqui faria o editor mostrar a formação inicial
/// deslocada em relação aos próprios chips de seleção.
///
/// TODOS os slots do grid entram, com ou sem rótulo — não só os rotulados.
/// Decisão deliberada, não a sugestão original do handoff (que era "só
/// rotulados"): o editor já trata slot sem rótulo como pessoa de verdade —
/// `_FormacaoEditorInterativa._rotulo` cai para `'Slot $slot'` quando
/// `pelotao.rotulos['$slot']` está ausente, e os chips de fileira/coluna
/// operam sobre `linhas × colunas`, não sobre `rotulos.keys`. Um pelotão
/// criado sem nenhum rótulo (o próprio fluxo padrão testado em
/// `tela_configuracao_pelotao_test.dart`, "grid 3×3 default, sem rótulos")
/// já é um estado válido e navegável hoje; excluir slots sem rótulo do
/// estado inicial recriaria a MESMA classe de beco sem saída que esta
/// correção existe para fechar — um grid que carrega ninguém para montar.
/// Rotular é reversível a qualquer momento em "Configurar pelotão"; entrar
/// tarde demais no fluxo de criação de evolução não seria.
Map<String, dynamic> estadoInicialDoGrid(PelotaoDoc pelotao) {
  final int total = pelotao.linhas * pelotao.colunas;
  return <String, dynamic>{
    'slots': <String, dynamic>{
      for (int slot = 0; slot < total; slot++)
        '$slot': <String, dynamic>{
          'linha': slot ~/ pelotao.colunas,
          'coluna': slot % pelotao.colunas,
          'setor': 0,
          'cadencia': 'firme',
        },
    },
  };
}
