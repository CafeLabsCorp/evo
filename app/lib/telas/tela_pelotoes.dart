import 'package:flutter/material.dart';

import '../auth/servico_autenticacao.dart';
import '../dados/repositorio_evo.dart';
import '../tema/paleta.dart';
import 'tela_configuracao_pelotao.dart';
import 'tela_evolucoes.dart';
import 'widgets_estado.dart';

/// Primeira tela de verdade depois do login/bootstrap: lista os pelotões do
/// clube. Navegação da Etapa 4: Clube → **pelotão** → lista de evoluções →
/// playback.
class TelaPelotoes extends StatelessWidget {
  const TelaPelotoes({super.key, required this.repo, required this.auth});
  final RepositorioEvo repo;
  final ServicoAutenticacao auth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Paleta.fundo,
      appBar: AppBar(
        title: const Text('Pelotões'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: auth.sair,
          ),
        ],
      ),
      body: StreamBuilder<List<PelotaoDoc>>(
        stream: repo.pelotoes(),
        builder: (BuildContext context, AsyncSnapshot<List<PelotaoDoc>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const CentroCarregando();
          }
          if (snapshot.hasError) {
            return CentroErro(
              erro: snapshot.error,
              aoTentarDeNovo: () {}, // StreamBuilder reconecta sozinho.
            );
          }
          final List<PelotaoDoc> pelotoes = snapshot.data ?? const <PelotaoDoc>[];
          if (pelotoes.isEmpty) {
            return const CentroVazio(
              icone: Icons.groups_outlined,
              titulo: 'Nenhum pelotão ainda',
              descricao:
                  'Crie um pelotão para começar a planejar evoluções — '
                  'defina o tamanho do grid e o rótulo de cada posição.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: pelotoes.length,
            itemBuilder: (BuildContext context, int i) {
              final PelotaoDoc p = pelotoes[i];
              return Card(
                color: Paleta.superficie,
                child: ListTile(
                  title: Text(p.nome, style: const TextStyle(color: Paleta.claro)),
                  subtitle: Text(
                    '${p.linhas}×${p.colunas} · ${p.rotulos.length} posição(ões) com rótulo'
                    '${p.pendente ? ' · salvando…' : ''}',
                    style: const TextStyle(color: Paleta.cinzaMedio),
                  ),
                  trailing: IconButton(
                    tooltip: 'Configurar pelotão',
                    icon: const Icon(Icons.tune, color: Paleta.cinzaMedio),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            TelaConfiguracaoPelotao(repo: repo, pelotaoExistente: p),
                      ),
                    ),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TelaEvolucoes(repo: repo, pelotao: p),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TelaConfiguracaoPelotao(repo: repo, pelotaoExistente: null),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Novo pelotão'),
      ),
    );
  }
}
