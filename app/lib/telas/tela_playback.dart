import 'package:evo_motor/evo_motor.dart';
import 'package:flutter/material.dart';

import '../modelo/carregador_evolucao.dart';
import '../playback/controlador_playback.dart';
import '../pintura/formacao_painter.dart';

const Color _corNavy = Color(0xFF1E3A5F);
const Color _corAmbar = Color(0xFFFFB300);

/// Tela única do v1: carrega o JSON de exemplo, simula, e mostra o
/// playback. Os três estados que importam aqui não são
/// "loading/offline/erro" de rede (é um asset embarcado, sempre
/// disponível) — são carregando / JSON malformado ou movimento
/// desconhecido / pronto (com diagnósticos da simulação visíveis, nunca
/// escondidos).
class TelaPlayback extends StatefulWidget {
  const TelaPlayback({
    super.key,
    required this.caminhoAsset,
    this.carregarParaTeste,
  });

  final String caminhoAsset;

  /// Ponto de injeção só para teste: evita bater no `rootBundle` de novo
  /// pra cada teste de widget de interação (play/pause, seletor de
  /// faixa) — o carregamento de asset em si já tem seu próprio teste
  /// dedicado. Em produção isso é sempre `null` e o app usa
  /// [carregarEvolucaoDoAsset] normalmente.
  @visibleForTesting
  final Future<PacoteEvolucao> Function()? carregarParaTeste;

  @override
  State<TelaPlayback> createState() => _TelaPlaybackState();
}

class _TelaPlaybackState extends State<TelaPlayback>
    with SingleTickerProviderStateMixin {
  late Future<PacoteEvolucao> _futuro;
  ControladorPlayback? _controlador;

  @override
  void initState() {
    super.initState();
    _futuro =
        (widget.carregarParaTeste ??
        () => carregarEvolucaoDoAsset(widget.caminhoAsset))();
  }

  @override
  void dispose() {
    _controlador?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Evo — playback de evolução')),
      body: FutureBuilder<PacoteEvolucao>(
        future: _futuro,
        builder:
            (BuildContext context, AsyncSnapshot<PacoteEvolucao> snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(color: _corNavy),
                );
              }
              if (snapshot.hasError) {
                return _ErroCarregamento(erro: snapshot.error.toString());
              }
              final PacoteEvolucao pacote = snapshot.data!;
              _controlador ??= ControladorPlayback(pacote: pacote, vsync: this);
              return _CorpoPlayback(controlador: _controlador!);
            },
      ),
    );
  }
}

class _ErroCarregamento extends StatelessWidget {
  const _ErroCarregamento({required this.erro});
  final String erro;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Não deu pra carregar a evolução',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(erro, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _CorpoPlayback extends StatelessWidget {
  const _CorpoPlayback({required this.controlador});
  final ControladorPlayback controlador;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controlador,
      builder: (BuildContext context, Widget? child) {
        return Column(
          children: <Widget>[
            if (controlador.pacote.diagnosticosDeErro.isNotEmpty)
              _FaixaDiagnosticos(pacote: controlador.pacote),
            Expanded(
              child: Container(
                color: const Color(0xFFF7F7F5),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: controlador.pacote.resultado.porTique.isEmpty
                        ? 1
                        : _aspecto(controlador),
                    child: CustomPaint(
                      painter: FormacaoPainter(
                        estados: controlador.estadosRenderizados(),
                        campo: const Campo(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _Controles(controlador: controlador),
          ],
        );
      },
    );
  }

  double _aspecto(ControladorPlayback c) {
    final Campo campo = const Campo();
    return campo.larguraCelulas / campo.alturaCelulas;
  }
}

class _FaixaDiagnosticos extends StatelessWidget {
  const _FaixaDiagnosticos({required this.pacote});
  final PacoteEvolucao pacote;

  @override
  Widget build(BuildContext context) {
    final int n = pacote.diagnosticosDeErro.length;
    return Material(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: <Widget>[
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$n diagnóstico(s) de erro nesta evolução — a animação segue completa '
                '(com a continuação implícita nos slots afetados), mas confira antes '
                'de levar pro campo.',
                style: const TextStyle(color: Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Controles extends StatelessWidget {
  const _Controles({required this.controlador});
  final ControladorPlayback controlador;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  iconSize: 36,
                  color: _corNavy,
                  icon: Icon(
                    controlador.tocando
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                  ),
                  onPressed: controlador.alternarPlayPause,
                ),
                Expanded(
                  child: Slider(
                    activeColor: _corAmbar,
                    inactiveColor: _corNavy.withValues(alpha: 0.2),
                    min: controlador.tiqueInicioFaixa.toDouble(),
                    max: controlador.tiqueFimFaixa.toDouble(),
                    value: controlador.tiqueAtual.clamp(
                      controlador.tiqueInicioFaixa.toDouble(),
                      controlador.tiqueFimFaixa.toDouble(),
                    ),
                    onChanged: controlador.mudarParaTique,
                  ),
                ),
                Text('tique ${controlador.tiqueAtual.round()}'),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  const Text('Velocidade'),
                  const SizedBox(width: 8),
                  ...<double>[3, 6, 9, 12].map(
                    (double v) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text('${v / 6}x'),
                        selected: controlador.velocidadeTiquesPorSegundo == v,
                        selectedColor: _corAmbar.withValues(alpha: 0.4),
                        onSelected: (_) => controlador.definirVelocidade(v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 220,
                    child: DropdownButton<int?>(
                      isExpanded: true,
                      value: controlador.indiceParteSelecionada,
                      hint: const Text('Faixa'),
                      items: <DropdownMenuItem<int?>>[
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Evolução completa'),
                        ),
                        for (final FaixaParte f in controlador.faixas)
                          DropdownMenuItem<int?>(
                            value: f.indiceParte,
                            child: Text(
                              'Parte ${f.indiceParte + 1}${f.nome != null ? ' — ${f.nome}' : ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: controlador.definirFaixa,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
