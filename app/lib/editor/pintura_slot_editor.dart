import 'dart:math' as math;

import 'package:evo_motor/evo_motor.dart';
import 'package:flutter/material.dart';

import '../tema/paleta.dart';

/// Glifo do badge de cadência — mesmos 4 desenhos vetoriais de
/// `pintura/formacao_painter.dart` (`_GlifoCadencia`), redeclarados aqui de
/// propósito: os dois arquivos pintam contextos diferentes o bastante
/// (playback animado com percussão/linha imaginária vs. grid estático do
/// editor com seleção/indicador de continuação) que fundir os dois
/// `CustomPainter`s custaria mais acoplamento do que vale — mas a TABELA
/// cor+glifo por cadência é a mesma intencionalmente (mesmo vocabulário
/// visual nas duas telas), então qualquer mudança nela precisa ser espelhada
/// nos dois lugares. Nenhuma lógica de domínio é duplicada aqui (isso
/// continua vivendo só em `evo_motor`) — é puramente a mesma decisão de
/// estilo copiada uma vez.
enum GlifoCadencia { quadrado, chevron, x, anelVazado }

class EstiloCadencia {
  const EstiloCadencia({required this.cor, required this.glifo});
  final Color cor;
  final GlifoCadencia glifo;
}

const Map<Cadencia, EstiloCadencia> estilosCadencia = <Cadencia, EstiloCadencia>{
  Cadencia.firme: EstiloCadencia(cor: Color(0xFFD3D6DA), glifo: GlifoCadencia.quadrado),
  Cadencia.descansar: EstiloCadencia(cor: Color(0xFF6A6E74), glifo: GlifoCadencia.anelVazado),
  Cadencia.marcandoPasso: EstiloCadencia(cor: Color(0xFF9BA0A6), glifo: GlifoCadencia.x),
  Cadencia.marchando: EstiloCadencia(cor: Color(0xFFF2F3F5), glifo: GlifoCadencia.chevron),
};

/// Desenha UMA silhueta do editor: corpo + contorno + badge de cadência
/// (canto superior direito, igual ao playback) + quadrado ciano de
/// "recebeu instrução nesta parte" (canto inferior ESQUERDO — posição
/// deliberadamente distinta do badge e do arco de percussão do playback,
/// ver o handoff do `design`: "forma e posição, não variação de cor").
///
/// Sem grade, sem arco de percussão, sem linha imaginária — isto é o editor
/// (slot é identidade, sempre desenhado na célula fixa do grid, nunca na
/// posição física simulada; ver dartdoc de `EstadoFormacao` em
/// `evo_motor`), não o playback.
class SlotEditorPainter extends CustomPainter {
  const SlotEditorPainter({
    required this.cadencia,
    required this.setor,
    required this.recebeuInstrucao,
    required this.temPercussao,
  });

  final Cadencia cadencia;
  final int setor;
  final bool recebeuInstrucao;
  final bool temPercussao;

  @override
  void paint(Canvas canvas, Size size) {
    final double escala = size.shortestSide / 36;
    final Offset centro = Offset(size.width / 2, size.height / 2);
    final EstiloCadencia estilo = estilosCadencia[cadencia]!;

    canvas.save();
    canvas.translate(centro.dx, centro.dy);
    canvas.rotate(setor * math.pi / 4);
    final Path silhueta = Path()
      ..moveTo(0, -15 * escala)
      ..lineTo(11 * escala, -5 * escala)
      ..lineTo(11 * escala, 13 * escala)
      ..lineTo(-11 * escala, 13 * escala)
      ..lineTo(-11 * escala, -5 * escala)
      ..close();
    canvas.drawPath(silhueta, Paint()..color = estilo.cor);
    canvas.drawPath(
      silhueta,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = escala
        ..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.restore();

    _badgeCadencia(canvas, centro, escala, estilo);
    if (recebeuInstrucao) _quadradoContinuacao(canvas, centro, escala);
    if (temPercussao) _marcaPercussao(canvas, centro, escala);
  }

  void _badgeCadencia(Canvas canvas, Offset centro, double escala, EstiloCadencia estilo) {
    final Offset centroBadge = centro + Offset(6 * escala, -8 * escala);
    final double raio = 6 * escala;
    canvas.drawCircle(centroBadge, raio, Paint()..color = const Color(0xF21C1C1E));
    final double r = raio * 0.55;
    final Paint traco = Paint()
      ..color = Paleta.claro
      ..style = PaintingStyle.stroke
      ..strokeWidth = raio * 0.22
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (estilo.glifo) {
      case GlifoCadencia.quadrado:
        canvas.drawRect(
          Rect.fromCenter(center: centroBadge, width: r * 1.3, height: r * 1.3),
          Paint()..color = Paleta.claro,
        );
      case GlifoCadencia.chevron:
        final Path chevron = Path()
          ..moveTo(centroBadge.dx - r * 0.8, centroBadge.dy - r * 0.35)
          ..lineTo(centroBadge.dx, centroBadge.dy + r * 0.65)
          ..lineTo(centroBadge.dx + r * 0.8, centroBadge.dy - r * 0.35);
        canvas.drawPath(chevron, traco);
      case GlifoCadencia.x:
        canvas.drawLine(
          Offset(centroBadge.dx - r * 0.75, centroBadge.dy - r * 0.75),
          Offset(centroBadge.dx + r * 0.75, centroBadge.dy + r * 0.75),
          traco,
        );
        canvas.drawLine(
          Offset(centroBadge.dx + r * 0.75, centroBadge.dy - r * 0.75),
          Offset(centroBadge.dx - r * 0.75, centroBadge.dy + r * 0.75),
          traco,
        );
      case GlifoCadencia.anelVazado:
        canvas.drawCircle(centroBadge, r * 0.8, traco);
    }
  }

  /// Quadrado ciano — canto inferior ESQUERDO, forma e posição (nunca cor
  /// alternativa) são o único canal desta marca, por legibilidade (ver
  /// rationale do `design`: um badge de cadência idêntico não distingue
  /// "reatribuído nesta parte" de "continuação implícita" quando todo mundo
  /// está marchando).
  void _quadradoContinuacao(Canvas canvas, Offset centro, double escala) {
    final Offset centroMarca = centro + Offset(-6 * escala, 8 * escala);
    const double lado = 7;
    canvas.drawRect(
      Rect.fromCenter(center: centroMarca, width: lado * escala, height: lado * escala),
      Paint()..color = Paleta.acento,
    );
  }

  /// Pontinho discreto no canto inferior direito indicando "tem percussão
  /// atribuída nesta parte" — o editor não precisa do arco completo de
  /// 120° do playback (que distingue mão/perna esquerda/perna direita por
  /// geometria): a legenda de texto do painel já diz qual membro; aqui só
  /// interessa "tem ou não tem", para não competir com o quadrado de
  /// continuação no mesmo canto.
  void _marcaPercussao(Canvas canvas, Offset centro, double escala) {
    final Offset p = centro + Offset(6 * escala, 8 * escala);
    canvas.drawCircle(p, 2.5 * escala, Paint()..color = Paleta.acento);
  }

  @override
  bool shouldRepaint(covariant SlotEditorPainter oldDelegate) =>
      oldDelegate.cadencia != cadencia ||
      oldDelegate.setor != setor ||
      oldDelegate.recebeuInstrucao != recebeuInstrucao ||
      oldDelegate.temPercussao != temPercussao;
}
