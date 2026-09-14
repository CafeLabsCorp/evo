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
class FormacaoPainter extends CustomPainter {
  FormacaoPainter({
    required this.estados,
    required this.campo,
    this.tamanhoCelulaPx = 36,
  });

  final List<EstadoRenderizado> estados;
  final Campo campo;
  final double tamanhoCelulaPx;

  Offset _paraTela(Size size, double linha, double coluna) {
    final Offset centro = Offset(size.width / 2, size.height / 2);
    return centro + Offset(coluna * tamanhoCelulaPx, linha * tamanhoCelulaPx);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _corFundo);
    _desenharGrade(canvas, size);
    _desenharRosaDosVentos(canvas, size);
    for (final EstadoRenderizado e in estados) {
      _desenharPessoa(canvas, size, e);
    }
  }

  void _desenharGrade(Canvas canvas, Size size) {
    final Paint linha = Paint()
      ..color = _corGrade
      ..strokeWidth = 1;
    final Paint ponto = Paint()..color = _corGradePonto;

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
    // Pontos nos cruzamentos, mais visíveis que as linhas finas — ajuda a
    // localizar onde uma pessoa "deveria" estar quando ela está parada
    // fora de um cruzamento (posição diagonal intermediária).
    for (int l = -meiaAltura; l <= meiaAltura; l++) {
      for (int c = -meiaLargura; c <= meiaLargura; c++) {
        canvas.drawCircle(
          _paraTela(size, l.toDouble(), c.toDouble()),
          1.5,
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
    const double lado = 18;

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
      ..strokeWidth = e.destacado ? 3 : 1.5
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
    const double tamanhoFonte = 11;
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
      ..layout(const ui.ParagraphConstraints(width: 18));
    canvas.drawParagraph(
      paragrafo,
      centro + const Offset(-9, -tamanhoFonte * 0.72),
    );
  }

  void _desenharBorda(Canvas canvas, Rect r, _EstiloBorda estilo, Paint paint) {
    switch (estilo) {
      case _EstiloBorda.solida:
        canvas.drawRect(r, paint);
      case _EstiloBorda.tracejada:
        _desenharRetanguloTracejado(canvas, r, paint, tracoMm: 4, vaoMm: 3);
      case _EstiloBorda.pontilhada:
        _desenharRetanguloTracejado(canvas, r, paint, tracoMm: 1.5, vaoMm: 2.5);
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
      ..strokeWidth = 1;
    _desenharLinhaTracejada(canvas, p1, p2, tracejado, 3, 3);
  }

  bool _ehMeioInteiro(double v) => (v - v.floorToDouble() - 0.5).abs() < 1e-6;

  @override
  bool shouldRepaint(covariant FormacaoPainter oldDelegate) => true;
}
