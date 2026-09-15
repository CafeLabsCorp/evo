import 'package:flutter/material.dart';

import '../dados/repositorio_evo.dart';
import '../tema/paleta.dart';

/// Widgets de estado reaproveitados por todas as telas que consomem
/// `Stream`s do `RepositorioEvo`: carregando / vazio / erro. Existem aqui
/// para as quatro telas de navegação (pelotões, evoluções, configuração,
/// playback) tratarem esses estados de forma CONSISTENTE, em vez de cada
/// uma inventar o próprio spinner/mensagem.
class CentroCarregando extends StatelessWidget {
  const CentroCarregando({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(color: Paleta.claro));
}

class CentroVazio extends StatelessWidget {
  const CentroVazio({
    super.key,
    required this.icone,
    required this.titulo,
    required this.descricao,
    this.acao,
  });
  final IconData icone;
  final String titulo;
  final String descricao;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icone, color: Paleta.cinzaMedio, size: 48),
            const SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Paleta.claro,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              descricao,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Paleta.cinzaMedio),
            ),
            if (acao != null) ...<Widget>[const SizedBox(height: 16), acao!],
          ],
        ),
      ),
    );
  }
}

/// Mensagem amigável para um [FalhaPersistencia] — usada tanto aqui quanto
/// em qualquer `SnackBar`/diálogo de erro pontual de escrita. Único ponto
/// de tradução "falha técnica → texto para o instrutor".
String mensagemFalha(Object? erro) {
  if (erro is ErroPersistencia) {
    return switch (erro.falha) {
      ForaDoAr() =>
        'Sem conexão com o servidor agora. Assim que a conexão voltar, isto '
            'atualiza sozinho.',
      CotaEstourada() =>
        'O projeto atingiu a cota diária gratuita do Firebase. Ele volta a '
            'funcionar sozinho por volta da meia-noite (horário do '
            'Pacífico/EUA) — não é um erro do app.',
      SemPermissao() => 'Sua conta não tem permissão para isto agora. '
          'Tente sair e entrar de novo.',
      DocumentoInvalido() =>
        'Este dado não passou na validação do servidor. Confira os campos '
            'e tente de novo.',
      LimiteDeTamanho() => 'Este documento ficou grande demais para salvar.',
      SemTrava() => 'Outra pessoa está editando isto agora.',
    };
  }
  return 'Algo deu errado. Tente de novo.';
}

class CentroErro extends StatelessWidget {
  const CentroErro({super.key, required this.erro, required this.aoTentarDeNovo});
  final Object? erro;
  final VoidCallback aoTentarDeNovo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, color: Paleta.erro, size: 48),
            const SizedBox(height: 16),
            Text(
              mensagemFalha(erro),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Paleta.claro),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: aoTentarDeNovo, child: const Text('Tentar de novo')),
          ],
        ),
      ),
    );
  }
}
