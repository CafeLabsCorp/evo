import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:evo_motor/evo_motor.dart';
import 'package:flutter/material.dart';

import '../playback/controlador_playback.dart';
import '../tema/paleta_provisoria.dart';

// Paleta de desenho PROVISÓRIA — ver `tema/paleta_provisoria.dart`. Fundo
// escuro, grade e rosa dos ventos em cinza discreto, pessoas em cinza
// claro/branco. Âmbar só onde carrega significado (batida/destaque).
const Color _corGrade = PaletaProvisoria.grade;
const Color _corGradePonto = PaletaProvisoria.gradePonto;
const Color _corFundo = PaletaProvisoria.fundo;
const Color _corDestaque = PaletaProvisoria.acento;

enum _EstiloBorda { solida, tracejada, pontilhada }

class _EstiloCadencia {
  const _EstiloCadencia({
    required this.cor,
    required this.glifo,
    required this.borda,
  });
  final Color cor;
  final String glifo;
  final _EstiloBorda borda;
}

/// Cadência codificada em três canais — cor + glifo + estilo de borda —
/// nunca só cor, pra não depender de daltonismo/contraste de projetor.
/// Numa paleta de cinzas a distinção por cor (aqui, luminosidade) encolhe
/// bastante, então o glifo (efetivamente desenhado em [_desenharPessoa],
/// não só carregado como dado) e o estilo de borda carregam mais peso.
const Map<Cadencia, _EstiloCadencia> _estilos = <Cadencia, _EstiloCadencia>{
  Cadencia.firme: _EstiloCadencia(
    cor: Color(0xFFD3D6DA),
    glifo: '■',
    borda: _EstiloBorda.solida,
  ),
  Cadencia.descansar: _EstiloCadencia(
    cor: Color(0xFF6A6E74),
    glifo: '○',
    borda: _EstiloBorda.tracejada,
  ),
  Cadencia.marcandoPasso: _EstiloCadencia(
    cor: Color(0xFF9BA0A6),
    glifo: '×',
    borda: _EstiloBorda.pontilhada,
  ),
  Cadencia.marchando: _EstiloCadencia(
    cor: Color(0xFFF2F3F5),
    glifo: '▲',
    borda: _EstiloBorda.solida,
  ),
};

/// Desenha o pelotão inteiro sobre um `Canvas` — pessoa = quadrado +
/// triângulo de facing, nunca boneco; grade como linhas/pontos, nunca
/// células pintadas (com xadrez, um boneco entre cruzamentos lê como bug).
///
/// Enquadramento automático (correção de 2026-09-14): a célula NÃO tem
/// tamanho fixo em px — ela é derivada do `size` real recebido em [paint] e
/// do retângulo [enquadramento] (bounding box, em células, de tudo que a
/// formação ocupa ao longo de toda a faixa em reprodução — não só o tique
/// atual, ver [TransformacaoEnquadramento]). Antes disso o campo padrão
/// 20×20 com célula fixa de 36px simplesmente não cabia num retrato de
/// celular — boa parte do pelotão era desenhada fora da área visível, e o
/// sintoma reportado ("os quadradinhos ficaram horríveis de ver as setas e
/// as informações") era, literalmente, informação desenhada fora da tela.
class FormacaoPainter extends CustomPainter {
  FormacaoPainter({
    required this.estados,
    required this.campo,
    required this.enquadramento,
    this.mostrarLinhas = false,
    this.mostrarPontos = true,
  });

  final List<EstadoRenderizado> estados;
  final Campo campo;

  /// Bounding box (linha/coluna, em células, SEM margem ainda) de todas as
  /// posições ocupadas ao longo de toda a faixa em reprodução atual —
  /// calculado por [ControladorPlayback.enquadramentoCelulas], não aqui:
  /// isso é uma pergunta de domínio ("quais células a evolução usa"), este
  /// painter só decide COMO enquadrar esse retângulo (margem, teto/piso de
  /// escala). Ver a documentação de classe.
  final Rect enquadramento;

  /// Margem ao redor do conteúdo, em células, pra nenhuma pessoa ficar
  /// colada na borda. Pelo menos meia célula de cada lado: o `design`
  /// mediu que uma formação 5×5 pode ocupar ~1,41× da caixa original só
  /// com uma oitava (giro de 45°) — meia célula cobre essa expansão sem
  /// cortar ninguém contra a borda do enquadramento.
  static const double margemCelulas = 0.5;

  /// Piso de escala, em px lógicos — medido num retrato de 390px de
  /// largura (o menor comum, iPhone SE/mini): abaixo disso o indivíduo
  /// (sempre metade da célula, ver [_desenharPessoa]) fica menor que ~9px
  /// de lado, e nesse
  /// tamanho o glifo de cadência já não cabe dentro do quadrado e a borda
  /// tracejada/pontilhada vira ruído indistinguível de uma borda sólida —
  /// as três cadências deixam de ser diferenciáveis, que é o requisito de
  /// acessibilidade que [_estilos] documenta. Não é um número arbitrário
  /// confortável: é também, coincidentemente, ~o que a evolução de
  /// exemplo atual já força num retrato comum em modo "evolução completa"
  /// (17 células de altura) — não dá pra subir o piso sem cortar
  /// conteúdo real nesse caso.
  static const double escalaMinimaPx = 18;

  /// Teto de escala, em px lógicos, pela mesma referência de retrato de
  /// 390px. Sem teto, uma formação de um indivíduo só (ex.: uma fileira
  /// isolada marchando enquanto o resto do pelotão fica parado fora da
  /// faixa selecionada) encheria a tela com um quadrado gigante e fora de
  /// proporção com a densidade normal de um pelotão de 25 — 72px de célula
  /// dá um indivíduo de 36px de lado, grande o bastante pra examinar o
  /// glifo/facing de perto sem virar um bloco monolítico.
  static const double escalaMaximaPx = 72;

  /// Transformação (escala + centro) calculada no início de cada [paint] a
  /// partir do [size] real da vez — ver [TransformacaoEnquadramento].
  TransformacaoEnquadramento _transformacao = const TransformacaoEnquadramento(
    tamanhoCelulaPx: escalaMinimaPx,
    centroLinha: 0,
    centroColuna: 0,
  );

  /// Linhas conectando os cruzamentos do grid. Desligadas por padrão —
  /// competiam com o conteúdo (reclamação de legibilidade de 2026-09-14);
  /// quando ligadas, usam [PaletaProvisoria.grade], deliberadamente muito
  /// discreta. Independente de [mostrarPontos] — os quatro estados
  /// (nenhum/só linhas/só pontos/ambos) são válidos, inclusive "nenhum"
  /// (fundo limpo) durante o playback.
  final bool mostrarLinhas;

  /// Pontos nos cruzamentos do grid. Ligados por padrão — é a referência
  /// que ajuda a localizar onde uma pessoa "deveria" estar. Independente de
  /// [mostrarLinhas].
  final bool mostrarPontos;

  Offset _paraTela(Size size, double linha, double coluna) {
    final Offset centro = Offset(size.width / 2, size.height / 2);
    return centro +
        Offset(
          (coluna - _transformacao.centroColuna) * _transformacao.tamanhoCelulaPx,
          (linha - _transformacao.centroLinha) * _transformacao.tamanhoCelulaPx,
        );
  }

  /// Escala px/célula corrente — tudo que é desenhado (indivíduo, seta,
  /// glifo, espessura de traço, raio do ponto de grade) deriva desse valor
  /// em vez de usar px absoluto, senão célula e conteúdo dessincronizam de
  /// novo assim que a célula deixa de ser fixa.
  double get _tamanhoCelulaPx => _transformacao.tamanhoCelulaPx;

  @override
  void paint(Canvas canvas, Size size) {
    _transformacao = TransformacaoEnquadramento.calcular(
      enquadramento: enquadramento,
      tela: size,
      margemCelulas: margemCelulas,
      escalaMinimaPx: escalaMinimaPx,
      escalaMaximaPx: escalaMaximaPx,
    );
    canvas.drawRect(Offset.zero & size, Paint()..color = _corFundo);
    _desenharGrade(canvas, size);
    _desenharRosaDosVentos(canvas, size);
    for (final EstadoRenderizado e in estados) {
      _desenharPessoa(canvas, size, e);
    }
  }

  void _desenharGrade(Canvas canvas, Size size) {
    if (mostrarLinhas) _desenharLinhasGrade(canvas, size);
    if (mostrarPontos) _desenharPontosGrade(canvas, size);
  }

  /// Linhas conectando os cruzamentos — ver [mostrarLinhas]. Cor bem
  /// discreta de propósito (ver [PaletaProvisoria.grade]), pra não competir
  /// com o conteúdo quando ligada.
  void _desenharLinhasGrade(Canvas canvas, Size size) {
    final Paint linha = Paint()
      ..color = _corGrade
      ..strokeWidth = _escalar(1);

    final int meiaLargura = campo.larguraCelulas ~/ 2;
    final int meiaAltura = campo.alturaCelulas ~/ 2;

    for (int c = -meiaLargura; c <= meiaLargura; c++) {
      final Offset p1 = _paraTela(size, -meiaAltura.toDouble(), c.toDouble());
      final Offset p2 = _paraTela(size, meiaAltura.toDouble(), c.toDouble());
      canvas.drawLine(p1, p2, linha);
    }
    for (int l = -meiaAltura; l <= meiaAltura; l++) {
      final Offset p1 = _paraTela(size, l.toDouble(), -meiaLargura.toDouble());
      final Offset p2 = _paraTela(size, l.toDouble(), meiaLargura.toDouble());
      canvas.drawLine(p1, p2, linha);
    }
  }

  /// Pontos nos cruzamentos — ver [mostrarPontos]. Mais visíveis que as
  /// linhas finas de propósito: ajuda a localizar onde uma pessoa "deveria"
  /// estar quando ela está parada fora de um cruzamento (posição diagonal
  /// intermediária).
  void _desenharPontosGrade(Canvas canvas, Size size) {
    final Paint ponto = Paint()..color = _corGradePonto;

    final int meiaLargura = campo.larguraCelulas ~/ 2;
    final int meiaAltura = campo.alturaCelulas ~/ 2;

    for (int l = -meiaAltura; l <= meiaAltura; l++) {
      for (int c = -meiaLargura; c <= meiaLargura; c++) {
        canvas.drawCircle(
          _paraTela(size, l.toDouble(), c.toDouble()),
          _escalar(1.5),
          ponto,
        );
      }
    }
  }

  void _desenharRosaDosVentos(Canvas canvas, Size size) {
    const double raio = 22;
    final Offset centro = Offset(size.width - 40, 40);
    final Paint corpo = Paint()
      ..color = PaletaProvisoria.cinzaMedio.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(centro, raio, corpo);
    final ui.ParagraphBuilder pb =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 12),
          )
          ..pushStyle(ui.TextStyle(color: PaletaProvisoria.cinzaMedio))
          ..addText('N');
    final ui.Paragraph paragrafo = pb.build()
      ..layout(const ui.ParagraphConstraints(width: 20));
    canvas.drawParagraph(paragrafo, centro + const Offset(-6, -raio - 16));
    // Seta pra Norte (0 graus = topo, mesma convenção do facing setor 0).
    // Cinza discreto, não âmbar — a rosa dos ventos é referência
    // permanente, não um sinal de "algo aconteceu", então não gasta o
    // canal de cor reservado a seleção/parte atual/aviso.
    final Path seta = Path()
      ..moveTo(centro.dx, centro.dy - raio + 4)
      ..lineTo(centro.dx - 5, centro.dy - raio + 14)
      ..lineTo(centro.dx + 5, centro.dy - raio + 14)
      ..close();
    canvas.drawPath(seta, Paint()..color = PaletaProvisoria.cinzaMedio);
  }

  void _desenharPessoa(Canvas canvas, Size size, EstadoRenderizado e) {
    final Offset centro = _paraTela(size, e.linha, e.coluna);
    final _EstiloCadencia estilo = _estilos[e.cadencia]!;
    final double lado = _escalar(18);

    _desenharLinhaImaginariaSeNecessario(canvas, size, e);

    canvas.save();
    canvas.translate(centro.dx, centro.dy);
    canvas.rotate(grausParaRadianos(e.anguloGraus));

    final Paint preenchimento = Paint()..color = estilo.cor;
    final Rect quadrado = Rect.fromCenter(
      center: Offset.zero,
      width: lado,
      height: lado,
    );
    canvas.drawRect(quadrado, preenchimento);

    final Paint borda = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _escalar(e.destacado ? 3 : 1.5)
      ..color = e.destacado ? _corDestaque : Colors.black.withValues(alpha: 0.6);
    _desenharBorda(canvas, quadrado, estilo.borda, borda);

    // Triângulo de facing, apontando "pra cima" no referencial já
    // rotacionado (que corresponde ao facing atual). Preto translúcido,
    // não âmbar — é decoração de toda pessoa sempre presente, não um
    // sinal de "algo aconteceu" (esse canal é reservado a
    // seleção/parte atual/aviso/batida).
    final Path triangulo = Path()
      ..moveTo(0, -lado * 0.95)
      ..lineTo(-lado * 0.4, -lado * 0.25)
      ..lineTo(lado * 0.4, -lado * 0.25)
      ..close();
    canvas.drawPath(triangulo, Paint()..color = Colors.black.withValues(alpha: 0.55));

    canvas.restore();

    // Glifo da cadência — desenhado FORA do referencial rotacionado
    // (depois do `restore()`) de propósito: é um rótulo de estado, tem
    // que continuar legível não importa o facing (um "▲" ou "■" girado
    // 45° vira outra forma e some como sinal). O triângulo de facing
    // acima é a única coisa que deve girar.
    _desenharGlifo(canvas, centro, estilo);
  }

  void _desenharGlifo(Canvas canvas, Offset centro, _EstiloCadencia estilo) {
    final Color corTexto = estilo.cor.computeLuminance() > 0.5
        ? Colors.black.withValues(alpha: 0.75)
        : Colors.white.withValues(alpha: 0.9);
    final double tamanhoFonte = _escalar(11);
    final double largura = _escalar(18);
    final ui.ParagraphBuilder pb =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: TextAlign.center,
              fontSize: tamanhoFonte,
            ),
          )
          ..pushStyle(ui.TextStyle(color: corTexto))
          ..addText(estilo.glifo);
    final ui.Paragraph paragrafo = pb.build()
      ..layout(ui.ParagraphConstraints(width: largura));
    canvas.drawParagraph(
      paragrafo,
      centro + Offset(-largura / 2, -tamanhoFonte * 0.72),
    );
  }

  void _desenharBorda(Canvas canvas, Rect r, _EstiloBorda estilo, Paint paint) {
    switch (estilo) {
      case _EstiloBorda.solida:
        canvas.drawRect(r, paint);
      case _EstiloBorda.tracejada:
        _desenharRetanguloTracejado(
          canvas,
          r,
          paint,
          tracoMm: _escalar(4),
          vaoMm: _escalar(3),
        );
      case _EstiloBorda.pontilhada:
        _desenharRetanguloTracejado(
          canvas,
          r,
          paint,
          tracoMm: _escalar(1.5),
          vaoMm: _escalar(2.5),
        );
    }
  }

  void _desenharRetanguloTracejado(
    Canvas canvas,
    Rect r,
    Paint paint, {
    required double tracoMm,
    required double vaoMm,
  }) {
    final List<Offset> cantos = <Offset>[
      r.topLeft,
      r.topRight,
      r.bottomRight,
      r.bottomLeft,
      r.topLeft,
    ];
    for (int i = 0; i < 4; i++) {
      _desenharLinhaTracejada(
        canvas,
        cantos[i],
        cantos[i + 1],
        paint,
        tracoMm,
        vaoMm,
      );
    }
  }

  void _desenharLinhaTracejada(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint,
    double traco,
    double vao,
  ) {
    final double distancia = (b - a).distance;
    final Offset direcao = (b - a) / distancia;
    double percorrido = 0;
    bool desenhando = true;
    while (percorrido < distancia) {
      final double passo = math.min(
        desenhando ? traco : vao,
        distancia - percorrido,
      );
      if (desenhando) {
        canvas.drawLine(
          a + direcao * percorrido,
          a + direcao * (percorrido + passo),
          paint,
        );
      }
      percorrido += passo;
      desenhando = !desenhando;
    }
  }

  /// Quando a posição repousa numa fronteira de meia-célula (resultado de
  /// um número ímpar de tempos diagonais), desenha a "linha imaginária"
  /// entre os dois pontos de grade mais próximos — vocabulário do próprio
  /// domínio pra essa posição intermediária.
  ///
  /// Simplificação de v1: quando os dois eixos estão em meia-célula ao
  /// mesmo tempo (o caso comum, chegando por um facing diagonal), a linha
  /// é desenhada ao longo da diagonal correspondente ao facing ATUAL,
  /// quando o facing também é diagonal; se a pessoa já girou parada nesse
  /// meio-ponto (facing ortogonal), cai no par NE-SO por padrão — um
  /// detalhe puramente visual, sem efeito na simulação.
  void _desenharLinhaImaginariaSeNecessario(
    Canvas canvas,
    Size size,
    EstadoRenderizado e,
  ) {
    final bool meioColuna = _ehMeioInteiro(e.coluna);
    final bool meioLinha = _ehMeioInteiro(e.linha);
    if (!meioColuna && !meioLinha) return;

    final double l0 = e.linha.floorToDouble();
    final double c0 = e.coluna.floorToDouble();
    final double l1 = meioLinha ? l0 + 1 : l0;
    final double c1 = meioColuna ? c0 + 1 : c0;

    late Offset p1;
    late Offset p2;
    if (meioLinha && meioColuna) {
      final int setorArredondado = ((e.anguloGraus / 45.0).round()) % 8;
      final bool diagonalNeSo = setorArredondado.isOdd
          ? (setorArredondado == 1 || setorArredondado == 5)
          : true; // ortogonal: cai no default NE-SO.
      if (diagonalNeSo) {
        p1 = _paraTela(size, l0, c0);
        p2 = _paraTela(size, l1, c1);
      } else {
        p1 = _paraTela(size, l0, c1);
        p2 = _paraTela(size, l1, c0);
      }
    } else if (meioLinha) {
      p1 = _paraTela(size, l0, c0);
      p2 = _paraTela(size, l1, c0);
    } else {
      p1 = _paraTela(size, l0, c0);
      p2 = _paraTela(size, l0, c1);
    }

    final Paint tracejado = Paint()
      ..color = PaletaProvisoria.cinzaMedio.withValues(alpha: 0.5)
      ..strokeWidth = _escalar(1);
    _desenharLinhaTracejada(canvas, p1, p2, tracejado, _escalar(3), _escalar(3));
  }

  bool _ehMeioInteiro(double v) => (v - v.floorToDouble() - 0.5).abs() < 1e-6;

  /// Converte um valor calibrado pra uma célula de referência de 36px (o
  /// tamanho fixo antigo, antes desta correção) pra px reais na escala
  /// corrente — é assim que "tudo que é desenhado escala junto" (indivíduo,
  /// seta, glifo, espessura de traço, raio do ponto de grade): se a célula
  /// dobra, o indivíduo dobra.
  double _escalar(double valorEmCelulaDe36px) =>
      _tamanhoCelulaPx * valorEmCelulaDe36px / 36;

  @override
  bool shouldRepaint(covariant FormacaoPainter oldDelegate) =>
      true; // Sempre `true`: os pontos flutuantes de EstadoRenderizado (posições
  // interpoladas do playback) mudam a cada frame; comparar campo a campo
  // custaria mais do que simplesmente repintar.
}

/// Escala (px por célula) e centro (em células) usados por [FormacaoPainter]
/// pra converter linha/coluna em pixels de tela — extraído em função pura
/// só pra poder testar a matemática de enquadramento sem montar um `Canvas`
/// de verdade.
@visibleForTesting
class TransformacaoEnquadramento {
  const TransformacaoEnquadramento({
    required this.tamanhoCelulaPx,
    required this.centroLinha,
    required this.centroColuna,
  });

  final double tamanhoCelulaPx;
  final double centroLinha;
  final double centroColuna;

  /// Calcula a escala que faz o retângulo [enquadramento] (+ [margemCelulas]
  /// de cada lado) caber inteiro em [tela], respeitando [escalaMinimaPx] e
  /// [escalaMaximaPx]. O centro retornado é sempre o centro do retângulo
  /// COM margem — mas como [Rect.inflate] expande simetricamente, é o mesmo
  /// centro do retângulo original.
  factory TransformacaoEnquadramento.calcular({
    required Rect enquadramento,
    required Size tela,
    required double margemCelulas,
    required double escalaMinimaPx,
    required double escalaMaximaPx,
  }) {
    final Rect caixa = enquadramento.inflate(margemCelulas);
    final double larguraCelulas = math.max(caixa.width, 1e-6);
    final double alturaCelulas = math.max(caixa.height, 1e-6);
    final double escalaBruta = math.min(
      tela.width / larguraCelulas,
      tela.height / alturaCelulas,
    );
    return TransformacaoEnquadramento(
      tamanhoCelulaPx: escalaBruta.clamp(escalaMinimaPx, escalaMaximaPx),
      centroLinha: caixa.center.dy,
      centroColuna: caixa.center.dx,
    );
  }
}
