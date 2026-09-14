import 'package:evo_motor/evo_motor.dart';
import 'package:flutter/material.dart';

import '../modelo/carregador_evolucao.dart';
import '../playback/controlador_playback.dart';
import '../pintura/formacao_painter.dart';
import '../tema/paleta_provisoria.dart';

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
      appBar: AppBar(title: const Text('Evo Lab — playback')),
      body: FutureBuilder<PacoteEvolucao>(
        future: _futuro,
        builder:
            (BuildContext context, AsyncSnapshot<PacoteEvolucao> snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: PaletaProvisoria.claro,
                  ),
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
            const Icon(
              Icons.error_outline,
              color: PaletaProvisoria.erro,
              size: 48,
            ),
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
                color: PaletaProvisoria.fundo,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _aspecto(controlador),
                    child: CustomPaint(
                      painter: FormacaoPainter(
                        estados: controlador.estadosRenderizados(),
                        campo: const Campo(),
                        enquadramento: controlador.enquadramentoCelulas,
                        mostrarLinhas: controlador.mostrarLinhasGrade,
                        mostrarPontos: controlador.mostrarPontosGrade,
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

  /// Proporção do retângulo de desenho — casada com o CONTEÚDO enquadrado
  /// (bounding box da faixa em reprodução + a mesma margem que
  /// [FormacaoPainter] usa internamente), não com o campo 20×20 inteiro.
  /// Antes disto, a área de desenho era sempre quadrada (proporção do
  /// campo default) e o [FormacaoPainter] "sobrava" espaço nos dois lados
  /// do eixo mais curto pra manter a escala uniforme — funcionalmente
  /// correto (nada cortado), mas desperdiçava tela à toa numa evolução
  /// claramente não-quadrada (ex.: uma faixa alta e estreita). Casar a
  /// proporção aqui faz a mesma escala preencher o retângulo inteiro.
  double _aspecto(ControladorPlayback c) {
    if (c.pacote.resultado.porTique.isEmpty) return 1;
    final Rect caixa = c.enquadramentoCelulas.inflate(
      FormacaoPainter.margemCelulas,
    );
    if (caixa.width <= 0 || caixa.height <= 0) return 1;
    return caixa.width / caixa.height;
  }
}

class _FaixaDiagnosticos extends StatelessWidget {
  const _FaixaDiagnosticos({required this.pacote});
  final PacoteEvolucao pacote;

  @override
  Widget build(BuildContext context) {
    final int n = pacote.diagnosticosDeErro.length;
    return Material(
      color: PaletaProvisoria.erroSuperficie,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: <Widget>[
            const Icon(Icons.warning_amber_rounded, color: PaletaProvisoria.acento),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$n diagnóstico(s) de erro nesta evolução — a animação segue completa '
                '(com a continuação implícita nos slots afetados), mas confira antes '
                'de levar pro campo.',
                style: const TextStyle(color: PaletaProvisoria.claro),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Multiplicadores do seletor de velocidade, relativos ao novo
/// [ControladorPlayback.velocidadeBase1xTiquesPorSegundo] ("1x"). `0.25x`
/// foi adicionado a pedido — o "1x" recalibrado já é a metade do "1x"
/// antigo, e ainda assim ele quis uma opção mais lenta que essa.
const List<double> _multiplicadoresVelocidade = <double>[0.25, 0.5, 1, 1.5, 2];

String _rotuloVelocidade(double multiplicador) {
  final bool inteiro = multiplicador == multiplicador.roundToDouble();
  return inteiro ? '${multiplicador.toInt()}x' : '${multiplicador}x';
}

class _Controles extends StatelessWidget {
  const _Controles({required this.controlador});
  final ControladorPlayback controlador;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      color: PaletaProvisoria.superficie,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  iconSize: 36,
                  color: PaletaProvisoria.claro,
                  icon: Icon(
                    controlador.tocando
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                  ),
                  onPressed: controlador.alternarPlayPause,
                ),
                Expanded(
                  child: Slider(
                    activeColor: PaletaProvisoria.acento,
                    inactiveColor: PaletaProvisoria.cinzaMedio.withValues(
                      alpha: 0.3,
                    ),
                    min: controlador.tiqueInicioFaixa.toDouble(),
                    max: controlador.tiqueFimFaixa.toDouble(),
                    value: controlador.tiqueAtual.clamp(
                      controlador.tiqueInicioFaixa.toDouble(),
                      controlador.tiqueFimFaixa.toDouble(),
                    ),
                    onChanged: controlador.mudarParaTique,
                  ),
                ),
                Text(
                  'tique ${controlador.tiqueAtual.round()}',
                  style: const TextStyle(color: PaletaProvisoria.claro),
                ),
                _BotaoOpcoesGrade(controlador: controlador),
              ],
            ),
            const SizedBox(height: 8),
            _SeletorModo(controlador: controlador),
            const SizedBox(height: 8),
            _FaixaBolinhas(controlador: controlador),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  const Text(
                    'Velocidade',
                    style: TextStyle(color: PaletaProvisoria.claro),
                  ),
                  const SizedBox(width: 8),
                  ..._multiplicadoresVelocidade.map(
                    (double m) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(_rotuloVelocidade(m)),
                        selected:
                            controlador.velocidadeTiquesPorSegundo ==
                            m *
                                ControladorPlayback
                                    .velocidadeBase1xTiquesPorSegundo,
                        selectedColor: PaletaProvisoria.acento.withValues(
                          alpha: 0.35,
                        ),
                        backgroundColor: PaletaProvisoria.cinzaEscuro,
                        labelStyle: const TextStyle(
                          color: PaletaProvisoria.claro,
                        ),
                        onSelected: (_) => controlador.definirVelocidade(
                          m *
                              ControladorPlayback
                                  .velocidadeBase1xTiquesPorSegundo,
                        ),
                      ),
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

/// Botão que abre as opções de grade (linhas/pontos) num bottom sheet, em
/// vez de uma linha própria nos controles — pedido de 2026-09-14 foi por
/// dois switches independentes, mas a barra de controles do retrato de
/// celular já está cheia (play/slider, seletor de modo, fileira de partes,
/// velocidade); um menu evita competir por espaço vertical com a vista de
/// cima, que é o que importa ver. Cabe na mesma linha do play/slider, sem
/// aumentar a altura da barra.
class _BotaoOpcoesGrade extends StatelessWidget {
  const _BotaoOpcoesGrade({required this.controlador});
  final ControladorPlayback controlador;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Opções de grade',
      iconSize: 28,
      color: PaletaProvisoria.claro,
      icon: const Icon(Icons.grid_on),
      onPressed: () => _abrirOpcoes(context),
    );
  }

  void _abrirOpcoes(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PaletaProvisoria.superficie,
      builder: (BuildContext context) {
        return AnimatedBuilder(
          animation: controlador,
          builder: (BuildContext context, Widget? child) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 4),
                    child: Text(
                      'Grade',
                      style: TextStyle(
                        color: PaletaProvisoria.claro,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text(
                      'Linhas',
                      style: TextStyle(color: PaletaProvisoria.claro),
                    ),
                    activeThumbColor: PaletaProvisoria.acento,
                    value: controlador.mostrarLinhasGrade,
                    onChanged: controlador.alternarLinhasGrade,
                  ),
                  SwitchListTile(
                    title: const Text(
                      'Pontos',
                      style: TextStyle(color: PaletaProvisoria.claro),
                    ),
                    activeThumbColor: PaletaProvisoria.acento,
                    value: controlador.mostrarPontosGrade,
                    onChanged: controlador.alternarPontosGrade,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Toggle explícito e inequívoco entre os dois modos de playback:
/// "evolução completa" (o playhead nunca trava numa fronteira de parte) e
/// "parte isolada" (trava no início/fim da parte selecionada). Escolher
/// "parte isolada" sem nenhuma parte ainda selecionada assume a parte 1 —
/// nunca fica num estado ambíguo "isolada, mas de qual parte?".
class _SeletorModo extends StatelessWidget {
  const _SeletorModo({required this.controlador});
  final ControladorPlayback controlador;

  @override
  Widget build(BuildContext context) {
    final bool completa = controlador.indiceParteSelecionada == null;
    final bool temPartes = controlador.faixas.isNotEmpty;
    return Row(
      children: <Widget>[
        Expanded(
          child: ChoiceChip(
            label: const Text('Evolução completa'),
            selected: completa,
            selectedColor: PaletaProvisoria.acento.withValues(alpha: 0.35),
            backgroundColor: PaletaProvisoria.cinzaEscuro,
            labelStyle: const TextStyle(color: PaletaProvisoria.claro),
            onSelected: (_) => controlador.definirFaixa(null),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ChoiceChip(
            label: const Text('Parte isolada'),
            selected: !completa,
            selectedColor: PaletaProvisoria.acento.withValues(alpha: 0.35),
            backgroundColor: PaletaProvisoria.cinzaEscuro,
            labelStyle: TextStyle(
              color: temPartes
                  ? PaletaProvisoria.claro
                  : PaletaProvisoria.cinzaMedio,
            ),
            onSelected: temPartes
                ? (_) => controlador.definirFaixa(
                    controlador.indiceParteSelecionada ?? 0,
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

/// Núcleo navegável da fileira de partes pedida no lugar do dropdown
/// antigo: `○1 → ○2 → ○3 → ... → (+)`. O `design` ainda vai desenhar os
/// estados completos (colisão com 20+ partes, retrato de celular, parte
/// vazia) — isto é só o suficiente pra sentir a interação: rolagem
/// horizontal, bolinha da parte em reprodução destacada, toque começa o
/// playback a partir dali.
class _FaixaBolinhas extends StatelessWidget {
  const _FaixaBolinhas({required this.controlador});
  final ControladorPlayback controlador;

  @override
  Widget build(BuildContext context) {
    final List<FaixaParte> partes = controlador.faixas;
    final int? emReproducao = controlador.indiceParteEmReproducao;
    final bool modoCompleto = controlador.indiceParteSelecionada == null;

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: <Widget>[
          for (int i = 0; i < partes.length; i++) ...<Widget>[
            _Bolinha(
              numero: i + 1,
              nome: partes[i].nome,
              destacada: emReproducao == i,
              onTap: () => modoCompleto
                  ? controlador.irParaParte(i)
                  : (() {
                      controlador.definirFaixa(i);
                      controlador.tocar();
                    })(),
            ),
            if (i < partes.length - 1) const _Seta(),
          ],
          if (partes.isNotEmpty) const _Seta(),
          const _BotaoAdicionarParte(),
        ],
      ),
    );
  }
}

class _Bolinha extends StatelessWidget {
  const _Bolinha({
    required this.numero,
    required this.destacada,
    required this.onTap,
    this.nome,
  });

  final int numero;
  final String? nome;
  final bool destacada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String rotulo = 'Parte $numero${nome != null ? ' — $nome' : ''}';
    return Tooltip(
      message: destacada ? '$rotulo (em reprodução)' : rotulo,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: destacada
                ? PaletaProvisoria.acento.withValues(alpha: 0.25)
                : PaletaProvisoria.cinzaEscuro,
            border: Border.all(
              color: destacada
                  ? PaletaProvisoria.acento
                  : PaletaProvisoria.cinzaMedio,
              width: destacada ? 2.5 : 1.5,
            ),
          ),
          child: Text(
            '$numero',
            style: TextStyle(
              color: destacada
                  ? PaletaProvisoria.acento
                  : PaletaProvisoria.claro,
              fontWeight: destacada ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _Seta extends StatelessWidget {
  const _Seta();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Icon(
        Icons.arrow_right_alt,
        color: PaletaProvisoria.cinzaMedio,
      ),
    );
  }
}

/// "+" pra adicionar a próxima parte ali mesmo — visível e desabilitado
/// por enquanto. Não existe editor nem persistência de partes ainda, e o
/// `design` vai especificar o fluxo de criação; inventar um agora seria
/// trabalho jogado fora. Desabilitado (em vez de ausente) porque comunica
/// "isto vem a seguir", não "isto não existe" — ausente deixaria a fileira
/// parecendo incompleta, como se faltasse implementar a rolagem até o
/// fim, e não uma decisão deliberada de adiar a criação de partes.
class _BotaoAdicionarParte extends StatelessWidget {
  const _BotaoAdicionarParte();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: 'em breve',
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: PaletaProvisoria.cinzaMedio.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Icon(
            Icons.add,
            color: PaletaProvisoria.cinzaMedio.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}
