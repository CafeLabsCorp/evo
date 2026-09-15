import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../tema/paleta.dart';
import 'servico_autenticacao.dart';

/// Tela de login — único jeito de entrar no Evo Lab é Google (ver Etapa 2
/// do handoff). Sem cadastro por e-mail/senha, sem visitante anônimo: o
/// clube exige um dono identificável (`clubes.dono`), e login social é o
/// caminho mais barato para isso sem o app ter que guardar senha nenhuma.
class TelaEntrar extends StatefulWidget {
  const TelaEntrar({super.key, required this.servico});
  final ServicoAutenticacao servico;

  @override
  State<TelaEntrar> createState() => _TelaEntrarState();
}

class _TelaEntrarState extends State<TelaEntrar> {
  bool _entrando = false;
  String? _erro;

  Future<void> _entrar() async {
    setState(() {
      _entrando = true;
      _erro = null;
    });
    try {
      await widget.servico.entrarComGoogle();
      // Sucesso não precisa navegar daqui: quem decide a próxima tela é o
      // `PortaoApp`, ouvindo `mudancasDeUsuario()` — este widget só some da
      // árvore quando o gate re-renderiza.
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _erro = _mensagemDeErro(e));
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _erro = 'Não deu para entrar agora. Verifique sua conexão e tente de novo.',
      );
    } finally {
      if (mounted) setState(() => _entrando = false);
    }
  }

  String _mensagemDeErro(FirebaseAuthException e) {
    switch (e.code) {
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        // Deny path do usuário: ele fechou o popup de propósito. Não é
        // erro — não mostra mensagem nenhuma, só volta pro botão.
        return '';
      case 'popup-blocked':
        return 'O navegador bloqueou a janela de login. Permita pop-ups '
            'para este site e tente de novo.';
      case 'network-request-failed':
        return 'Sem conexão com a internet no momento. Tente de novo '
            'quando a conexão voltar.';
      case 'operation-not-allowed':
        return 'Login com Google não está habilitado neste projeto '
            '(configuração pendente).';
      case 'unauthorized-domain':
        return 'Este domínio não está autorizado a fazer login '
            '(configuração pendente).';
      default:
        return 'Não deu para entrar (${e.code}). Tente de novo.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Paleta.fundo,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const _LogoEvo(),
                const SizedBox(height: 24),
                const Text(
                  'Evo Lab',
                  style: TextStyle(
                    color: Paleta.claro,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Planeje evoluções de ordem unida do seu clube.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Paleta.cinzaMedio),
                ),
                const SizedBox(height: 32),
                if (_erro != null && _erro!.isNotEmpty) ...<Widget>[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Paleta.erroSuperficie,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _erro!,
                      style: const TextStyle(color: Paleta.erro),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _entrando ? null : _entrar,
                    style: FilledButton.styleFrom(
                      backgroundColor: Paleta.acento,
                      foregroundColor: Paleta.fundo,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _entrando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Paleta.fundo,
                            ),
                          )
                        : const Icon(Icons.login),
                    label: Text(_entrando ? 'Entrando...' : 'Entrar com Google'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Silhueta pentagonal em acento ciano — mesma linguagem visual do corpo
/// desenhado em `formacao_painter.dart`, aqui só como marca da tela de
/// login (sem cadência/rotação: é logo, não playback).
class _LogoEvo extends StatelessWidget {
  const _LogoEvo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: CustomPaint(painter: _PentagonoPainter()),
    );
  }
}

class _PentagonoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint tinta = Paint()
      ..color = Paleta.acento
      ..style = PaintingStyle.fill;
    final Path caminho = Path();
    const int pontas = 5;
    final double raio = size.shortestSide / 2;
    final Offset centro = Offset(size.width / 2, size.height / 2);
    for (int i = 0; i < pontas; i++) {
      // Ponta pra cima (facing Norte), sentido horário — mesma convenção
      // de setor 0 = Norte usada no motor (`geometria.dart`).
      final double angulo = -math.pi / 2 + i * (2 * math.pi / pontas);
      final Offset ponto =
          centro + Offset(raio * math.cos(angulo), raio * math.sin(angulo));
      if (i == 0) {
        caminho.moveTo(ponto.dx, ponto.dy);
      } else {
        caminho.lineTo(ponto.dx, ponto.dy);
      }
    }
    caminho.close();
    canvas.drawPath(caminho, tinta);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
