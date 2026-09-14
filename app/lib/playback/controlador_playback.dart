import 'dart:math' as math;

import 'package:evo_motor/evo_motor.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../modelo/carregador_evolucao.dart';

/// Estado de render de um slot num instante — já interpolado, em células
/// (double) e graus. O motor nunca produz ângulo intermediário; isso é
/// puramente uma dica de apresentação.
class EstadoRenderizado {
  const EstadoRenderizado({
    required this.slot,
    required this.linha,
    required this.coluna,
    required this.anguloGraus,
    required this.cadencia,
    required this.destacado,
  });

  final int slot;
  final double linha;
  final double coluna;
  final double anguloGraus;
  final Cadencia cadencia;

  /// `true` por uma janela curta ao redor de uma batida de ritmo — pulso
  /// visual simples, sem áudio na v1.
  final bool destacado;
}

/// Controla o playback de uma [PacoteEvolucao]: play/pause, velocidade,
/// scrub por tique, e seleção de faixa (parte isolada / evolução
/// completa). Os três modos de playback da spec são a mesma simulação já
/// pronta (`pacote.resultado`), só fatiada diferente — não há nova
/// simulação por modo.
///
/// `ChangeNotifier` + `Ticker` é deliberadamente simples: é uma única tela
/// com um relógio e alguns controles, sem estado cross-screen pra
/// justificar Riverpod/Bloc aqui.
class ControladorPlayback extends ChangeNotifier {
  ControladorPlayback({required this.pacote, required TickerProvider vsync}) {
    _combinados = <EstadoFormacao>[
      pacote.evolucao.estadoInicial,
      ...pacote.resultado.porTique,
    ];
    _eventosPorSlot = <int, List<EventoRotacao>>{};
    for (final Evento evento in pacote.resultado.eventos) {
      if (evento is EventoRotacao) {
        _eventosPorSlot
            .putIfAbsent(evento.slot, () => <EventoRotacao>[])
            .add(evento);
      }
    }
    _ticker = vsync.createTicker(_aoTicar);
    definirFaixa(null);
  }

  final PacoteEvolucao pacote;

  late final List<EstadoFormacao> _combinados; // [inicial, ...porTique]
  late Map<int, List<EventoRotacao>> _eventosPorSlot;
  late final Ticker _ticker;
  Duration _ultimoTique = Duration.zero;

  /// `null` = evolução completa; caso contrário, índice da parte
  /// selecionada (ver `pacote.resultado.faixas`).
  int? _indiceParteSelecionada;

  /// Velocidade-base do PLAYER (apresentação) que o seletor chama de
  /// "1x" — em tiques por segundo. Isto é calibração de *reprodução na
  /// tela*, nunca a duração real de um tique da simulação em si (o motor
  /// não tem noção de tempo real, só de tiques discretos) e — mais
  /// importante — **não é o mesmo conceito** de um eventual atributo de
  /// domínio "velocidade" (0.5x/1x/2x de marcha, atribuído a uma pessoa
  /// dentro de uma parte do catálogo). Se esse atributo existir um dia,
  /// ele muda o resultado da simulação (quantos tiques uma pessoa leva pra
  /// percorrer uma distância); isto aqui só muda o quão rápido o mesmo
  /// resultado já simulado é mostrado. Não compartilhe constante nem nome
  /// entre os dois — hoje eles não têm nenhuma relação no código, e é pra
  /// continuar assim.
  ///
  /// Recalibrado em 2026-09: o "1x" antigo (6 tiques/s) estava rápido
  /// demais no teste no celular; o novo "1x" é a metade da velocidade
  /// antiga (o dobro da duração real de um tique — de ~166,7ms pra
  /// ~333,3ms). Os multiplicadores do seletor (0.25x/0.5x/1x/1.5x/2x) são
  /// sempre relativos a este valor.
  static const double velocidadeBase1xTiquesPorSegundo = 3;

  double _tiqueAtual = 0;
  double _velocidadeTiquesPorSegundo = velocidadeBase1xTiquesPorSegundo;
  bool _tocando = false;

  int? get indiceParteSelecionada => _indiceParteSelecionada;
  double get tiqueAtual => _tiqueAtual;
  bool get tocando => _tocando;
  double get velocidadeTiquesPorSegundo => _velocidadeTiquesPorSegundo;

  int get tiqueInicioFaixa => _indiceParteSelecionada == null
      ? 0
      : pacote.resultado.faixas[_indiceParteSelecionada!].tiqueInicio;

  int get tiqueFimFaixa => _indiceParteSelecionada == null
      ? pacote.resultado.porTique.length
      : pacote.resultado.faixas[_indiceParteSelecionada!].tiqueFim;

  List<FaixaParte> get faixas => pacote.resultado.faixas;

  void definirFaixa(int? indiceParte) {
    pausar();
    _indiceParteSelecionada = indiceParte;
    _tiqueAtual = tiqueInicioFaixa.toDouble();
    notifyListeners();
  }

  /// Índice da parte que contém o tique atual do playhead — usado só pra
  /// destacar a bolinha correspondente na fileira de partes. Funciona
  /// independente do modo (evolução completa ou parte isolada) e mesmo
  /// pausado: é sempre "onde o playhead está agora", não "qual faixa está
  /// selecionada" (`indiceParteSelecionada`, que é `null` em modo
  /// evolução completa mesmo com o playhead dentro de alguma parte).
  int? get indiceParteEmReproducao {
    for (final FaixaParte f in pacote.resultado.faixas) {
      if (_tiqueAtual >= f.tiqueInicio && _tiqueAtual < f.tiqueFim) {
        return f.indiceParte;
      }
    }
    if (pacote.resultado.faixas.isNotEmpty &&
        _tiqueAtual >= pacote.resultado.faixas.last.tiqueFim) {
      return pacote.resultado.faixas.last.indiceParte;
    }
    return null;
  }

  /// Toque numa bolinha da fileira de partes, em modo evolução completa:
  /// pula o playhead pro início daquela parte e começa a tocar dali até o
  /// fim de verdade da evolução (não do início, e sem travar no fim da
  /// parte clicada — isso é o modo "parte isolada", que é outra seleção).
  void irParaParte(int indiceParte) {
    pausar();
    _indiceParteSelecionada = null;
    _tiqueAtual = pacote.resultado.faixas[indiceParte].tiqueInicio.toDouble();
    tocar();
  }

  void definirVelocidade(double tiquesPorSegundo) {
    _velocidadeTiquesPorSegundo = tiquesPorSegundo;
    notifyListeners();
  }

  void tocar() {
    if (_tocando) return;
    if (_tiqueAtual >= tiqueFimFaixa) {
      _tiqueAtual = tiqueInicioFaixa.toDouble();
    }
    _tocando = true;
    _ultimoTique = Duration.zero;
    _ticker.start();
    notifyListeners();
  }

  void pausar() {
    if (!_tocando) return;
    _tocando = false;
    _ticker.stop();
    notifyListeners();
  }

  void alternarPlayPause() => _tocando ? pausar() : tocar();

  void mudarParaTique(double tique) {
    pausar();
    _tiqueAtual = tique.clamp(
      tiqueInicioFaixa.toDouble(),
      tiqueFimFaixa.toDouble(),
    );
    notifyListeners();
  }

  void _aoTicar(Duration decorrido) {
    if (_ultimoTique == Duration.zero) {
      _ultimoTique = decorrido;
      return;
    }
    final double deltaSegundos =
        (decorrido - _ultimoTique).inMicroseconds /
        Duration.microsecondsPerSecond;
    _ultimoTique = decorrido;

    _tiqueAtual += deltaSegundos * _velocidadeTiquesPorSegundo;
    if (_tiqueAtual >= tiqueFimFaixa) {
      _tiqueAtual = tiqueFimFaixa.toDouble();
      pausar();
    }
    notifyListeners();
  }

  /// Estados interpolados de todos os slots pro tique fracionário atual.
  List<EstadoRenderizado> estadosRenderizados() {
    final double t = _tiqueAtual.clamp(0, (_combinados.length - 1).toDouble());
    final int piso = t.floor().clamp(0, _combinados.length - 1);
    final int teto = (piso + 1).clamp(0, _combinados.length - 1);
    final double fracao = teto == piso ? 0 : t - piso;

    final EstadoFormacao antes = _combinados[piso];
    final EstadoFormacao depois = _combinados[teto];

    final List<EstadoRenderizado> resultado = <EstadoRenderizado>[];
    for (final int slot in antes.slots) {
      final EstadoPessoa a = antes[slot];
      final EstadoPessoa b = depois.porSlot[slot] ?? a;

      final (double linhaA, double colunaA) = a.posicao.emCelulas();
      final (double linhaB, double colunaB) = b.posicao.emCelulas();
      final double linha = linhaA + (linhaB - linhaA) * fracao;
      final double coluna = colunaA + (colunaB - colunaA) * fracao;

      final double angulo = _anguloInterpolado(slot, t, a.dir);
      final bool destacado = _temBatidaPerto(slot, t);

      resultado.add(
        EstadoRenderizado(
          slot: slot,
          linha: linha,
          coluna: coluna,
          anguloGraus: angulo,
          cadencia: fracao < 0.5 ? a.cad : b.cad,
          destacado: destacado,
        ),
      );
    }
    return resultado;
  }

  double _anguloInterpolado(int slot, double t, int direcaoDiscretaAtual) {
    final List<EventoRotacao>? janelas = _eventosPorSlot[slot];
    if (janelas != null) {
      for (final EventoRotacao evento in janelas) {
        final JanelaRotacao j = evento.janela;
        if (t >= j.tiqueInicio &&
            t <= j.tiqueFim &&
            j.tiqueFim > j.tiqueInicio) {
          final double progresso =
              ((t - j.tiqueInicio) / (j.tiqueFim - j.tiqueInicio)).clamp(0, 1);
          return j.direcaoAntes * 45.0 + j.deltaSetor * 45.0 * progresso;
        }
      }
    }
    return direcaoDiscretaAtual * 45.0;
  }

  bool _temBatidaPerto(int slot, double t) {
    for (final Evento evento in pacote.resultado.eventos) {
      if (evento is EventoBatida && evento.slot == slot) {
        if ((evento.tiqueGlobal - t).abs() < 0.5) return true;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

/// Menor diferença angular assinada de [a] pra [b], em graus, no intervalo
/// (-180, 180] — não usada pela interpolação principal (que já tem o sinal
/// certo via `deltaSetor`), mas útil pra qualquer render auxiliar futuro.
double menorDiferencaAngular(double a, double b) {
  double diff = (b - a) % 360;
  if (diff > 180) diff -= 360;
  if (diff < -180) diff += 360;
  return diff;
}

double grausParaRadianos(double graus) => graus * math.pi / 180;
