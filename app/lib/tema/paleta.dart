import 'package:flutter/material.dart';

/// Paleta de tema escuro do Evo Lab — fundo escuro, elementos em cinza e
/// branco, acento ciano usado só onde carrega significado (seleção, parte
/// atual em reprodução, destaque de batida).
///
/// Até 2026-09-14 este arquivo se chamava `paleta_provisoria.dart` e o
/// comentário avisava que ele inteiro seria descartado assim que o `design`
/// entregasse a direção visual definitiva. Ela chegou: a investigação de
/// duas rejeições seguidas mostrou que o problema nunca foi a paleta — era
/// geometria (facing sobreposto, glifo em fonte, borda tracejada em 18px) —
/// e a troca de cor que sobrou (âmbar → `acento` ciano abaixo, medido contra
/// o fundo real) é a única mudança de cor da spec. Por isso o arquivo deixou
/// de ser descartável e ganhou nome definitivo.
class Paleta {
  const Paleta._();

  static const Color fundo = Color(0xFF121212);
  static const Color superficie = Color(0xFF1E1E1E);
  static const Color claro = Color(0xFFECECEC);
  static const Color cinzaMedio = Color(0xFF9AA0A6);
  static const Color cinzaEscuro = Color(0xFF3A3A3C);

  /// Linhas do grid — bem mais discretas que os pontos de cruzamento de
  /// propósito: competiam com o conteúdo (reclamação de legibilidade de
  /// 2026-09-14) e viraram opcionais (ver [FormacaoPainter.mostrarLinhas]).
  static const Color grade = Color(0x14FFFFFF);

  /// Ponto de cruzamento do grid. Alpha subido de 0x59 (~35%, contraste
  /// 3,2:1 contra o fundo) para 0x73 (~45%, 4,53:1) na correção de
  /// 2026-09-14: com as linhas desligadas por padrão, o ponto passou a ser
  /// a única referência estrutural do campo e precisa compensar sozinho.
  static const Color gradePonto = Color(0x73FFFFFF);

  /// Uso parcimonioso e deliberado: seleção, parte atual em reprodução,
  /// destaque de batida. Nunca decoração — cor sempre sinaliza algo
  /// específico, senão vira ruído visual sem função.
  ///
  /// Ciano (ex-âmbar `0xFFFFB300`, trocado na correção de 2026-09-14):
  /// 8,13:1 de contraste contra [fundo]. Regra permanente e não
  /// negociável — este tom só é desenhado sobre [fundo] (ou superfícies
  /// igualmente escuras), nunca sobreposto a um preenchimento claro (ex.:
  /// o corpo de uma pessoa em cadência `firme`/`marchando`). Foi
  /// exatamente essa sobreposição que quebrou o âmbar (a borda de destaque
  /// de batida chegava a 1,23:1 soldada ao contorno de um corpo claro) — o
  /// ciano quebraria do mesmo jeito na mesma posição. Por isso o anel de
  /// destaque de batida foi movido para fora da silhueta (ver
  /// `_desenharAnelDestaque` em `formacao_painter.dart`) em vez de só
  /// trocar a cor da borda antiga.
  static const Color acento = Color(0xFF29B6F6);

  static const Color erro = Colors.redAccent;
  static const Color erroSuperficie = Color(0xFF3B1F1F);
}
