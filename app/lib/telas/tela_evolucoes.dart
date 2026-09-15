import 'package:flutter/material.dart';

import '../dados/controle_edicao.dart';
import '../dados/export_json.dart';
import '../dados/repositorio_evo.dart';
import '../tema/paleta.dart';
import '../util/exportar_evolucao.dart';
import 'tela_editor_partes.dart';
import 'tela_playback_nuvem.dart';
import 'widgets_estado.dart';

/// Lista de evoluções de UM pelotão. `RepositorioEvo.evolucoes()` devolve
/// as evoluções do CLUBE inteiro (não tem parâmetro de pelotão — ver o
/// índice em `firestore.indexes.json`, que é só `clubId + atualizadoEm`);
/// o filtro por `pelotaoId` é feito aqui, do lado do cliente. Um clube
/// single-user com poucos pelotões/evoluções não paga preço nenhum por
/// isso, e evita um índice composto extra só para uma tela de navegação.
class TelaEvolucoes extends StatelessWidget {
  const TelaEvolucoes({super.key, required this.repo, required this.pelotao});
  final RepositorioEvo repo;
  final PelotaoDoc pelotao;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Paleta.fundo,
      appBar: AppBar(title: Text(pelotao.nome)),
      body: StreamBuilder<List<ResumoEvolucao>>(
        stream: repo.evolucoes(),
        builder:
            (BuildContext context, AsyncSnapshot<List<ResumoEvolucao>> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CentroCarregando();
              }
              if (snapshot.hasError) {
                return CentroErro(erro: snapshot.error, aoTentarDeNovo: () {});
              }
              final List<ResumoEvolucao> todas = snapshot.data ?? const <ResumoEvolucao>[];
              final List<ResumoEvolucao> destePelotao = <ResumoEvolucao>[
                for (final ResumoEvolucao r in todas)
                  if (r.pelotaoId == pelotao.id) r,
              ];
              if (destePelotao.isEmpty) {
                return const CentroVazio(
                  icone: Icons.movie_creation_outlined,
                  titulo: 'Nenhuma evolução ainda',
                  descricao:
                      'O editor de evoluções chega em breve. Por enquanto, esta '
                      'tela só mostra e reproduz evoluções já existentes.',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: destePelotao.length,
                itemBuilder: (BuildContext context, int i) {
                  final ResumoEvolucao r = destePelotao[i];
                  return Card(
                    color: Paleta.superficie,
                    child: ListTile(
                      title: Text(r.nome, style: const TextStyle(color: Paleta.claro)),
                      subtitle: Text(
                        'Atualizada em ${_formatarData(r.atualizadoEm)}',
                        style: const TextStyle(color: Paleta.cinzaMedio),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            tooltip: 'Editar partes',
                            icon: const Icon(Icons.edit_outlined, color: Paleta.cinzaMedio),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => TelaEditorPartes(
                                  repo: repo,
                                  evolucaoId: r.id,
                                  controleEdicao: const TravaSempreMinha(),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Exportar (JSON)',
                            icon: const Icon(Icons.download_outlined, color: Paleta.cinzaMedio),
                            onPressed: () => _exportar(context, r.id),
                          ),
                          IconButton(
                            tooltip: 'Apagar evolução',
                            icon: const Icon(Icons.delete_outline, color: Paleta.cinzaMedio),
                            onPressed: () => _apagar(context, r.id),
                          ),
                        ],
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              TelaPlaybackNuvem(repo: repo, evolucaoId: r.id),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
      ),
    );
  }

  Future<void> _exportar(BuildContext context, String evolucaoId) async {
    final ScaffoldMessengerState mensageiro = ScaffoldMessenger.of(context);
    try {
      final EvolucaoDoc? doc = await repo.evolucao(evolucaoId).first;
      if (doc == null) {
        mensageiro.showSnackBar(
          const SnackBar(content: Text('Esta evolução não existe mais.')),
        );
        return;
      }
      final List<ParteDoc> partesDoc = await repo.partes(evolucaoId).first;
      final Map<String, dynamic> json = construirJsonDeExport(doc, partesDoc);
      baixarJsonComoArquivo(nomeBaseArquivo: 'evo-lab-backup', json: json);
      mensageiro.showSnackBar(
        const SnackBar(content: Text('Export baixado — é o único backup deste dado.')),
      );
    } catch (erro) {
      mensageiro.showSnackBar(SnackBar(content: Text(mensagemFalha(erro))));
    }
  }

  Future<void> _apagar(BuildContext context, String evolucaoId) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: Paleta.superficie,
        title: const Text('Apagar evolução?', style: TextStyle(color: Paleta.claro)),
        content: const Text(
          'Isto apaga a evolução e TODAS as partes dela — não dá para desfazer. '
          'Exporte antes, se quiser guardar uma cópia: não há backup automático.',
          style: TextStyle(color: Paleta.cinzaMedio),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Paleta.erro),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    if (!context.mounted) return;
    final ScaffoldMessengerState mensageiro = ScaffoldMessenger.of(context);
    try {
      await repo.apagarEvolucao(evolucaoId);
    } catch (erro) {
      mensageiro.showSnackBar(SnackBar(content: Text(mensagemFalha(erro))));
    }
  }
}

String _formatarData(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
