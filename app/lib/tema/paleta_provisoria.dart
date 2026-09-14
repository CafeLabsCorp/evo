import 'package:flutter/material.dart';

/// Paleta PROVISÓRIA de tema escuro — fundo escuro, elementos em cinza e
/// branco, âmbar usado só onde carrega significado (seleção, parte atual
/// em reprodução, aviso).
///
/// Isto existe só pra destravar o preview no celular depois que a
/// identidade visual anterior (navy + âmbar saturado) foi rejeitada no
/// teste de 2026-09-14 ("a identidade visual não ficou muito bonita
/// não"). O `design` está refazendo a direção visual completa em
/// paralelo — quando ela chegar, esta paleta inteira é descartada e
/// substituída pela definitiva. NÃO tratar nada aqui como identidade
/// final do Evo Lab, nem espalhar esses valores em lugares novos: quando
/// a paleta do `design` chegar, a expectativa é apagar este arquivo
/// inteiro, não editá-lo peça por peça.
class PaletaProvisoria {
  const PaletaProvisoria._();

  static const Color fundo = Color(0xFF121212);
  static const Color superficie = Color(0xFF1E1E1E);
  static const Color claro = Color(0xFFECECEC);
  static const Color cinzaMedio = Color(0xFF9AA0A6);
  static const Color cinzaEscuro = Color(0xFF3A3A3C);
  /// Linhas do grid — bem mais discretas que os pontos de cruzamento de
  /// propósito: competiam com o conteúdo (reclamação de legibilidade de
  /// 2026-09-14) e viraram opcionais (ver [FormacaoPainter.mostrarLinhas]).
  /// Reduzido de 0x33 (~20% opacidade) pra isto (~8%) a pedido.
  static const Color grade = Color(0x14FFFFFF);
  static const Color gradePonto = Color(0x59FFFFFF);

  /// Uso parcimonioso e deliberado: seleção, parte atual em reprodução,
  /// aviso/destaque de batida. Nunca decoração — numa paleta de cinzas,
  /// cor tem que continuar sinalizando algo específico, senão vira ruído
  /// visual sem função.
  static const Color acento = Color(0xFFFFB300);

  static const Color erro = Colors.redAccent;
  static const Color erroSuperficie = Color(0xFF3B1F1F);
}
