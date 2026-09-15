import 'json/comando_do_catalogo.dart';
import 'movimento.dart';
import 'percussao.dart';
import 'preenchimento.dart';

/// O que um slot faz dentro de uma [Parte].
///
/// `preenchimento` cobre tanto os tiques antes do `offsetInicialTiques`
/// (esperando a deixa) quanto os de depois do movimento (até a parte
/// fechar em `T`). Se `null`, o default materializado é "continuação da
/// cadência final" do movimento (nunca `firme` hardcoded) — ver
/// [Preenchimento.paraCadencia]. A spec pede que esse default seja
/// materializado "na gravação, não resolvido na leitura"; a v1 não tem
/// editor, então materializamos no momento em que a [Atribuicao] é
/// construída/compilada — mesmo efeito prático (determinístico, nunca
/// recalculado de formas diferentes em execuções diferentes), documentado
/// aqui como simplificação de v1.
class Atribuicao {
  /// Aceita exatamente UM entre `movimento` (já compilado — segmentos
  /// concretos, sem identidade serializável) e `comando` (o descritor
  /// fonte do catálogo, round-trippable — ver [ComandoDoCatalogo]).
  ///
  /// Por que os dois caminhos, em vez de só `comando`: as ~40 atribuições
  /// que os testes do motor constroem hoje passam um [Movimento] pronto
  /// (`Catalogo.sentido(...)`, etc.) porque só querem simular — nunca
  /// serializam nada, e reescrever todas para montar um
  /// [ComandoDoCatalogo] não mudaria nenhum comportamento, só sintaxe.
  /// O que o editor e o codec JSON exigem é o caminho inverso: toda
  /// `Atribuicao` que vem de [atribuicaoDoJson] (via `evolucao_json.dart`)
  /// é construída com `comando`, nunca com `movimento` direto — e é por
  /// isso, e só por isso, que ela consegue voltar para JSON via
  /// `atribuicaoParaJson` (que lança [StateError] se `comando` for nulo).
  ///
  /// Nunca os dois ao mesmo tempo nem nenhum: isso eliminaria a garantia
  /// de fonte única — não existe como montar uma `Atribuicao` cujo
  /// [movimento] não bata com seu [comando], porque só um dos dois é a
  /// fonte real; o outro é sempre derivado dele.
  Atribuicao({
    Movimento? movimento,
    this.comando,
    this.offsetInicialTiques = 0,
    this.preenchimento,
    this.percussao,
  }) : assert(offsetInicialTiques >= 0),
       assert(
         (movimento == null) != (comando == null),
         'Atribuicao exige exatamente um entre `movimento` e `comando`, '
         'nunca os dois nem nenhum — ver dartdoc do construtor.',
       ),
       _movimentoExplicito = movimento {
    if (offsetInicialTiques.isOdd) {
      throw ArgumentError.value(
        offsetInicialTiques,
        'offsetInicialTiques',
        'precisa ser um número PAR de tiques — 1 tempo = 2 tiques sempre, '
        'e o motor não tem noção de "meio tempo" pra esperar antes de um '
        'comando. Um offset ímpar quebraria mais adiante, dentro do '
        'preenchimento de espera, com um erro bem menos claro do que este.',
      );
    }
  }

  final Movimento? _movimentoExplicito;

  /// O comando-fonte do catálogo (tipo + parâmetros) que originou esta
  /// atribuição, quando ela foi construída a partir dele — `null` quando
  /// foi construída com um [Movimento] já compilado direto (atalho interno
  /// usado por testes, não serializável).
  final ComandoDoCatalogo? comando;

  /// O movimento compilado (segmentos concretos) usado pelo motor para
  /// simular — derivado de [comando] quando presente, ou o valor recebido
  /// direto no construtor caso contrário. `compilador.dart` só enxerga
  /// isto, nunca [comando].
  Movimento get movimento => _movimentoExplicito ?? comando!.materializar();

  final int offsetInicialTiques;
  final Preenchimento? preenchimento;

  /// Percussão (mão na perna, pés se deslocando) atribuída a este slot
  /// nesta parte — `null` significa nenhuma. Ver a regra de emissão em
  /// `compilador.dart`: cobre TODA a faixa `0..T-1` do slot na parte
  /// (preenchimento de espera + movimento + preenchimento de fechamento),
  /// não só a janela do movimento, e é rejeitada (com diagnóstico, sem
  /// abortar) quando a cadência de entrada ou a resultante do movimento é
  /// `descansar`.
  final Percussao? percussao;
}

/// Um frame de instruções simultâneas: subgrupos diferentes fazendo
/// movimentos diferentes ao mesmo tempo. `ordem` é a posição da parte
/// dentro da evolução (permite reordenar sem renumerar).
class Parte {
  const Parte({required this.ordem, required this.atribuicoes, this.nome});

  final double ordem;
  final Map<int, Atribuicao> atribuicoes;
  final String? nome;
}
