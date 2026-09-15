import 'campo.dart';
import 'checagens/colisao.dart';
import 'checagens/encadeamento.dart';
import 'checagens/limites.dart';
import 'compilador.dart';
import 'diagnostico.dart';
import 'estado.dart';
import 'eventos.dart';
import 'parte.dart';

/// Faixa de tiques (índices GLOBAIS, 0-based, `tiqueFim` exclusivo) de uma
/// parte dentro de `porTique`. Os três modos de playback (parte isolada,
/// evolução completa, sequência) são a mesma função de simulação, fatiada
/// diferente: parte isolada K = fatiar `faixas[K]`; evolução completa =
/// `porTique` inteiro.
class FaixaParte {
  const FaixaParte({
    required this.indiceParte,
    required this.tiqueInicio,
    required this.tiqueFim,
    this.nome,
  });

  final int indiceParte;
  final int tiqueInicio;
  final int tiqueFim;
  final String? nome;
}

class ResultadoSimulacao {
  const ResultadoSimulacao({
    required this.porTique,
    required this.faixas,
    required this.eventos,
    required this.diagnosticos,
  });

  /// Um [EstadoFormacao] por tique, para toda a evolução (todas as
  /// partes concatenadas). NÃO inclui o estado inicial (tique "0 antes de
  /// tudo") — esse é o parâmetro `inicial` de [simular].
  final List<EstadoFormacao> porTique;
  final List<FaixaParte> faixas;
  final List<Evento> eventos;
  final List<Diagnostico> diagnosticos;

  /// Estado final da evolução — último tique, ou `inicial` se a evolução
  /// inteira for degenerada (0 partes ou todas com T=0).
  EstadoFormacao estadoFinal(EstadoFormacao inicialSeVazio) =>
      porTique.isEmpty ? inicialSeVazio : porTique.last;
}

/// Simula uma lista de [Parte]s a partir de um [EstadoFormacao] inicial.
/// Pura e determinística: sem `DateTime.now()`, sem RNG, sem tipos de UI ou
/// de rede.
///
/// As quatro checagens rodam todas aqui: comando impossível (checagem 1)
/// acontece dentro de `compilarParte`, por parte; colisão (3) e fora dos
/// limites (4) rodam sobre a timeline inteira já concatenada, porque
/// dependem do estado contínuo entre partes. Encadeamento (2) NÃO roda
/// aqui — ele compara o fim de uma evolução com o início de outra, então
/// vive em `simularSequencia`.
ResultadoSimulacao simular(
  EstadoFormacao inicial,
  List<Parte> partes, [
  Config cfg = const Config(),
]) {
  final List<Parte> ordenadas = List<Parte>.of(partes)
    ..sort((Parte a, Parte b) => a.ordem.compareTo(b.ordem));

  final List<EstadoFormacao> porTique = <EstadoFormacao>[];
  final List<FaixaParte> faixas = <FaixaParte>[];
  final List<Evento> eventos = <Evento>[];
  final List<Diagnostico> diagnosticos = <Diagnostico>[];

  EstadoFormacao cursor = inicial;

  for (int indice = 0; indice < ordenadas.length; indice++) {
    final Parte parte = ordenadas[indice];
    final ResultadoCompilacaoParte resultado = compilarParte(
      indice,
      cursor,
      parte,
    );

    final int inicioGlobal = porTique.length;
    porTique.addAll(resultado.tiques);
    final int fimGlobal = porTique.length;

    faixas.add(
      FaixaParte(
        indiceParte: indice,
        tiqueInicio: inicioGlobal,
        tiqueFim: fimGlobal,
        nome: parte.nome,
      ),
    );
    diagnosticos.addAll(resultado.diagnosticos);
    for (final Evento evento in resultado.eventos) {
      eventos.add(_deslocarEvento(evento, inicioGlobal));
    }
    if (resultado.tiques.isNotEmpty) {
      cursor = resultado.tiques.last;
    }
  }

  final List<EstadoFormacao> comInicial = <EstadoFormacao>[
    inicial,
    ...porTique,
  ];
  diagnosticos.addAll(
    verificarColisoes(
      comInicial,
      avisosHabilitados: cfg.avisosColisaoHabilitados,
    ),
  );
  diagnosticos.addAll(verificarLimites(porTique, cfg.campo));

  return ResultadoSimulacao(
    porTique: porTique,
    faixas: faixas,
    eventos: eventos,
    diagnosticos: diagnosticos,
  );
}

Evento _deslocarEvento(Evento evento, int offsetGlobal) => switch (evento) {
  EventoBatida(:final int slot, :final int tiqueGlobal, :final TipoBatida tipo) =>
    EventoBatida(
      slot: slot,
      tiqueGlobal: tiqueGlobal + offsetGlobal,
      tipo: tipo,
    ),
  EventoRotacao(:final int slot, :final JanelaRotacao janela) => EventoRotacao(
    slot: slot,
    janela: janela.deslocarPara(offsetGlobal),
  ),
};

/// Uma evolução completa: nome, estado inicial GRAVADO (o que foi
/// planejado) e as partes que a compõem.
class Evolucao {
  const Evolucao({
    required this.nome,
    required this.estadoInicial,
    required this.partes,
  });

  final String nome;
  final EstadoFormacao estadoInicial;
  final List<Parte> partes;
}

/// Modo de encadeamento de uma sequência de evoluções.
enum ModoSequencia {
  /// Cada evolução parte do seu `estadoInicial` GRAVADO — o que foi
  /// planejado, sem herdar imprecisões da evolução anterior.
  declarado,

  /// Cada evolução (exceto a primeira) parte do estado FINAL REAL da
  /// anterior — o que vai de fato acontecer no campo, incluindo qualquer
  /// divergência de encadeamento não corrigida.
  encadeado,
}

class ResultadoSequencia {
  const ResultadoSequencia({
    required this.porEvolucao,
    required this.diagnosticosEncadeamento,
  });

  /// Um [ResultadoSimulacao] por evolução, na ordem da sequência.
  final List<ResultadoSimulacao> porEvolucao;

  /// Diagnósticos de encadeamento entre cada par de evoluções consecutivas
  /// (índice 0 = entre a evolução 0 e a 1, etc.) — computados sempre
  /// comparando o fim REAL de uma contra o início EXIGIDO (gravado) da
  /// próxima, independente do `ModoSequencia` escolhido para tocar.
  final List<Diagnostico> diagnosticosEncadeamento;
}

/// Simula uma sequência de evoluções. Os dois modos são a mesma função
/// `simular`, diferindo só em qual estado alimenta cada evolução — é
/// literalmente a diferença que o produto existe para mostrar.
ResultadoSequencia simularSequencia(
  List<Evolucao> evolucoes,
  ModoSequencia modo, [
  Config cfg = const Config(),
]) {
  final List<ResultadoSimulacao> resultados = <ResultadoSimulacao>[];
  final List<Diagnostico> diagnosticosEncadeamento = <Diagnostico>[];

  EstadoFormacao? fimAnteriorReal;

  for (final Evolucao evolucao in evolucoes) {
    if (fimAnteriorReal != null) {
      diagnosticosEncadeamento.addAll(
        verificarEncadeamento(fimAnteriorReal, evolucao.estadoInicial),
      );
    }

    final EstadoFormacao entrada =
        (modo == ModoSequencia.encadeado && fimAnteriorReal != null)
        ? fimAnteriorReal
        : evolucao.estadoInicial;

    final ResultadoSimulacao resultado = simular(entrada, evolucao.partes, cfg);
    resultados.add(resultado);
    fimAnteriorReal = resultado.estadoFinal(entrada);
  }

  return ResultadoSequencia(
    porEvolucao: resultados,
    diagnosticosEncadeamento: diagnosticosEncadeamento,
  );
}
