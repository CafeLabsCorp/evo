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

  double _tiqueAtual = 0;
  double _velocidadeTiquesPorSegundo =
      6; // 3 tempos/s — cadência de marcha legível.
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
