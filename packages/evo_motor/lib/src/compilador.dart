import 'cadencia.dart';
import 'diagnostico.dart';
import 'estado.dart';
import 'eventos.dart';
import 'movimento.dart';
import 'parte.dart';
import 'preenchimento.dart';
import 'segmento.dart';

/// Resultado de compilar uma [Parte] a partir de um [EstadoFormacao] de
/// entrada: os estados por tique (um [EstadoFormacao] por tique, T no
/// total — sem incluir o estado de entrada), os eventos e os diagnósticos
/// encontrados (checagem 1 — comando impossível). Índices de tique aqui
/// são LOCAIS à parte (0..T-1); `simular` os desloca para o índice global.
class ResultadoCompilacaoParte {
  const ResultadoCompilacaoParte({
    required this.tiques,
    required this.duracaoTiques,
    required this.diagnosticos,
    required this.eventos,
  });

  final List<EstadoFormacao> tiques;
  final int duracaoTiques;
  final List<Diagnostico> diagnosticos;
  final List<Evento> eventos;
}

/// Compila uma [Parte] isolada. `indiceParte` só é usado para anotar
/// diagnósticos.
ResultadoCompilacaoParte compilarParte(
  int indiceParte,
  EstadoFormacao entrada,
  Parte parte,
) {
  // T = max(offsetInicial + duração estrutural do movimento) sobre as
  // atribuições, arredondado para cima até um número PAR de tiques. A
  // duração estrutural independe de a precondição de cadência bater — é
  // uma propriedade do movimento escolhido (e, para "Marcar passo", da
  // cadência de ENTRADA do slot na parte — ver `Movimento.duracaoTiquesPara`)
  // — nunca da validade do comando. Usamos a cadência de entrada na parte
  // (`entrada[slot].cad`), a mesma referência que `cadenciaResultante` já
  // usa mais abaixo — consistente mesmo quando há offset > 0.
  int duracaoBruta = 0;
  for (final MapEntry<int, Atribuicao> par in parte.atribuicoes.entries) {
    final Atribuicao atribuicao = par.value;
    final Cadencia cadenciaEntradaSlot = entrada[par.key].cad;
    final int fim =
        atribuicao.offsetInicialTiques +
        atribuicao.movimento.duracaoTiquesPara(cadenciaEntradaSlot);
    if (fim > duracaoBruta) duracaoBruta = fim;
  }
  final int t = duracaoBruta.isOdd ? duracaoBruta + 1 : duracaoBruta;

  final List<Diagnostico> diagnosticos = <Diagnostico>[];
  final List<Evento> eventos = <Evento>[];

  // slot -> lista de T EstadoPessoa (um por tique local desta parte).
  final Map<int, List<EstadoPessoa>> porSlot = <int, List<EstadoPessoa>>{};

  for (final int slot in entrada.slots) {
    final EstadoPessoa inicial = entrada[slot];
    final Atribuicao? atribuicao = parte.atribuicoes[slot];

    if (atribuicao == null) {
      porSlot[slot] = _continuacaoImplicita(inicial, t);
      continue;
    }

    final Movimento movimento = atribuicao.movimento;
    final int offset = atribuicao.offsetInicialTiques;

    // Default do preenchimento: continuação da cadência FINAL do
    // movimento — nunca hardcoded para firme. Aplicado igualmente ao
    // trecho antes do offset e ao trecho depois do movimento (é o mesmo
    // campo `preenchimento` para os dois, por spec). Nota: isso significa
    // que, se a cadência de entrada for diferente da final e houver
    // offset > 0, o trecho de espera já mostra a cadência de CHEGADA
    // (ex.: já "marchando" antes do comando ter sido dado) — é uma
    // consequência explícita do texto da spec ("Default do preenchimento
    // = continuação da cadência final"), não um bug; documentado aqui
    // para o próximo dev que for mexer nisso.
    final Cadencia cadenciaFinalMovimento = movimento.cadenciaResultante(
      inicial.cad,
    );
    final Preenchimento preenchimento =
        atribuicao.preenchimento ??
        Preenchimento.paraCadencia(cadenciaFinalMovimento);

    // Precondição (checagem 1 — comando impossível). É avaliada contra a
    // cadência com que o slot CHEGA ao início do movimento, isto é, depois
    // do preenchimento de espera (que pode já ter mudado a cadência,
    // conforme a nota acima).
    final EstadoPessoa estadoAntesDoMovimento = offset == 0
        ? inicial
        : executarSegmentos(
            inicial,
            preenchimento.segmentosPara(offset),
            cadenciaFinal: preenchimento.cadencia,
          ).estadoFinal;

    final ResultadoPrecondicao precondicao = movimento.checarPrecondicao(
      estadoAntesDoMovimento.cad,
    );

    if (!precondicao.ok) {
      diagnosticos.add(
        DiagnosticoComandoImpossivel(
          indiceParte: indiceParte,
          slot: slot,
          nomeMovimento: movimento.nome,
          cadenciaExigida: movimento.exigido,
          cadenciaAtual: estadoAntesDoMovimento.cad,
        ),
      );
      // "Não aborta": cai na continuação implícita a partir da cadência de
      // ENTRADA na parte (a atribuição inteira — inclusive o preenchimento
      // de espera — é descartada), pelos T tiques inteiros.
      porSlot[slot] = _continuacaoImplicita(inicial, t);
      continue;
    }

    if (precondicao.avisoTeleporte) {
      diagnosticos.add(
        DiagnosticoComandoImpossivel(
          indiceParte: indiceParte,
          slot: slot,
          nomeMovimento: movimento.nome,
          cadenciaExigida: movimento.exigido,
          cadenciaAtual: estadoAntesDoMovimento.cad,
          severidade: SeveridadeDiagnostico.aviso,
        ),
      );
    }

    final List<EstadoPessoa> linhaDoTempo = <EstadoPessoa>[];

    // Trecho antes do offset (espera pela deixa).
    EstadoPessoa cursor = inicial;
    if (offset > 0) {
      final ResultadoSegmentos antes = executarSegmentos(
        cursor,
        preenchimento.segmentosPara(offset),
        cadenciaFinal: preenchimento.cadencia,
      );
      linhaDoTempo.addAll(antes.tiques);
      _emitirEventos(eventos, slot, antes, offsetGlobalLocal: 0);
      cursor = antes.estadoFinal;
    }

    // O movimento em si. Os segmentos são resolvidos com `inicial.cad` —
    // a cadência de entrada NA PARTE, a mesma referência já usada acima
    // para `cadenciaResultante` e para o `T` da parte (`duracaoBruta`) —
    // não com `cursor.cad` (que, com offset > 0, já pode ter sido
    // adiantado pelo preenchimento de espera, ver nota acima sobre a
    // cadência de "chegada"). Usar uma fonte diferente aqui quebraria a
    // igualdade entre o `T` calculado e os tiques de fato produzidos
    // sempre que a duração de um movimento dependa da cadência de entrada
    // (hoje, só "Marcar passo" — ver `Movimento.duracaoTiquesPara`).
    final ResultadoSegmentos doMovimento = executarSegmentos(
      cursor,
      movimento.segmentosPara(inicial.cad),
      cadenciaFinal: cadenciaFinalMovimento,
    );
    linhaDoTempo.addAll(doMovimento.tiques);
    _emitirEventos(
      eventos,
      slot,
      doMovimento,
      offsetGlobalLocal: linhaDoTempo.length - doMovimento.tiques.length,
    );
    cursor = doMovimento.estadoFinal;

    // Trecho depois do movimento, até fechar T.
    final int restante = t - linhaDoTempo.length;
    if (restante > 0) {
      final ResultadoSegmentos depois = executarSegmentos(
        cursor,
        preenchimento.segmentosPara(restante),
        cadenciaFinal: preenchimento.cadencia,
      );
      _emitirEventos(
        eventos,
        slot,
        depois,
        offsetGlobalLocal: linhaDoTempo.length,
      );
      linhaDoTempo.addAll(depois.tiques);
    }

    assert(
      linhaDoTempo.length == t,
      'Slot $slot: linha do tempo com ${linhaDoTempo.length} tiques, '
      'esperado $t.',
    );
    porSlot[slot] = linhaDoTempo;
  }

  final List<EstadoFormacao> tiques = List<EstadoFormacao>.generate(t, (int i) {
    return EstadoFormacao(<int, EstadoPessoa>{
      for (final MapEntry<int, List<EstadoPessoa>> entrada in porSlot.entries)
        entrada.key: entrada.value[i],
    });
  });

  return ResultadoCompilacaoParte(
    tiques: tiques,
    duracaoTiques: t,
    diagnosticos: diagnosticos,
    eventos: eventos,
  );
}

List<EstadoPessoa> _continuacaoImplicita(EstadoPessoa inicial, int tiques) {
  final Preenchimento p = Preenchimento.paraCadencia(inicial.cad);
  if (tiques == 0) return const <EstadoPessoa>[];
  return executarSegmentos(
    inicial,
    p.segmentosPara(tiques),
    cadenciaFinal: p.cadencia,
  ).tiques;
}

void _emitirEventos(
  List<Evento> destino,
  int slot,
  ResultadoSegmentos resultado, {
  required int offsetGlobalLocal,
}) {
  for (final int tiqueRelativo in resultado.batidas) {
    destino.add(
      EventoBatida(slot: slot, tiqueGlobal: offsetGlobalLocal + tiqueRelativo),
    );
  }
  for (final JanelaRotacao janela in resultado.janelasRotacao) {
    destino.add(
      EventoRotacao(slot: slot, janela: janela.deslocarPara(offsetGlobalLocal)),
    );
  }
}
