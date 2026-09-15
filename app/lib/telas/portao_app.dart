import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/servico_autenticacao.dart';
import '../auth/tela_entrar.dart';
import '../clube/servico_clube.dart';
import '../dados/repositorio_evo.dart';
import '../dados/repositorio_evo_firestore.dart';
import '../tema/paleta.dart';
import 'tela_pelotoes.dart';

/// Raiz de navegação: gate de autenticação, depois gate de bootstrap do
/// clube, depois a tela de verdade. Único lugar do app que decide isso —
/// nenhuma outra tela verifica `FirebaseAuth.instance.currentUser` sozinha.
///
/// Estado de conta assumido nesta versão: um usuário pertence a exatamente
/// um clube (o bootstrap garante isso). Se um dia `meusClubes` devolver
/// mais de um, este gate pega o primeiro — não existe seletor de clube
/// ainda (não há por que existir em single-user).
class PortaoApp extends StatelessWidget {
  /// [servicoAutenticacao] e [firestore] são pontos de injeção para teste
  /// (ver `test/portao_app_test.dart`) — em produção ambos ficam `null` e
  /// o app usa `FirebaseAuth.instance`/`FirebaseFirestore.instance`, já
  /// inicializados em `main()`.
  const PortaoApp({super.key, ServicoAutenticacao? servicoAutenticacao, this.firestore})
    : _auth = servicoAutenticacao;

  final ServicoAutenticacao? _auth;
  final FirebaseFirestore? firestore;

  @override
  Widget build(BuildContext context) {
    final ServicoAutenticacao auth = _auth ?? ServicoAutenticacao();
    return StreamBuilder<User?>(
      stream: auth.mudancasDeUsuario(),
      builder: (BuildContext context, AsyncSnapshot<User?> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _TelaCarregando();
        }
        final User? usuario = snapshot.data;
        if (usuario == null) return TelaEntrar(servico: auth);
        return _PortaoClube(
          uid: usuario.uid,
          auth: auth,
          firestore: firestore ?? FirebaseFirestore.instance,
        );
      },
    );
  }
}

class _PortaoClube extends StatefulWidget {
  const _PortaoClube({required this.uid, required this.auth, required this.firestore});
  final String uid;
  final ServicoAutenticacao auth;
  final FirebaseFirestore firestore;

  @override
  State<_PortaoClube> createState() => _PortaoClubeState();
}

class _PortaoClubeState extends State<_PortaoClube> {
  late final ServicoClube _servicoClube = ServicoClube(firestore: widget.firestore);
  late Future<String> _bootstrap;

  @override
  void initState() {
    super.initState();
    _bootstrap = _servicoClube.bootstrap(uid: widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _bootstrap,
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _TelaCarregando();
        }
        if (snapshot.hasError) {
          return _TelaErroBootstrap(
            erro: snapshot.error,
            aoTentarDeNovo: () => setState(
              () => _bootstrap = _servicoClube.bootstrap(uid: widget.uid),
            ),
            aoSair: widget.auth.sair,
          );
        }
        final String clubId = snapshot.data!;
        final RepositorioEvo repo = RepositorioEvoFirestore(
          firestore: widget.firestore,
          clubId: clubId,
        );
        return TelaPelotoes(repo: repo, auth: widget.auth);
      },
    );
  }
}

class _TelaCarregando extends StatelessWidget {
  const _TelaCarregando();
  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Paleta.fundo,
    body: Center(child: CircularProgressIndicator(color: Paleta.claro)),
  );
}

class _TelaErroBootstrap extends StatelessWidget {
  const _TelaErroBootstrap({
    required this.erro,
    required this.aoTentarDeNovo,
    required this.aoSair,
  });
  final Object? erro;
  final VoidCallback aoTentarDeNovo;
  final Future<void> Function() aoSair;

  String get _mensagem {
    final Object? e = erro;
    if (e is ErroPersistencia) {
      return switch (e.falha) {
        ForaDoAr() =>
          'Sem conexão com o servidor agora. Isso normalmente se resolve '
              'sozinho — tente de novo em instantes.',
        CotaEstourada() =>
          'O projeto atingiu a cota diária do plano gratuito do Firebase. '
              'Ele volta a funcionar sozinho por volta da meia-noite '
              '(horário do Pacífico/EUA).',
        SemPermissao() =>
          'Sua conta não tem permissão para configurar um clube. '
              'Tente sair e entrar de novo.',
        _ => 'Não deu para configurar seu clube agora.',
      };
    }
    return 'Não deu para configurar seu clube agora.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Paleta.fundo,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.cloud_off, color: Paleta.erro, size: 48),
              const SizedBox(height: 12),
              Text(
                _mensagem,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Paleta.claro),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: aoTentarDeNovo, child: const Text('Tentar de novo')),
              TextButton(onPressed: aoSair, child: const Text('Sair')),
            ],
          ),
        ),
      ),
    );
  }
}
