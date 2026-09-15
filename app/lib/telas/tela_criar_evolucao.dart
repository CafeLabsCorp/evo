import 'package:evo_motor/evo_motor.dart' show versaoCatalogo;
import 'package:flutter/material.dart';

import '../dados/controle_edicao.dart';
import '../dados/estado_inicial_pelotao.dart';
import '../dados/repositorio_evo.dart';
import '../tema/paleta.dart';
import 'tela_editor_partes.dart';
import 'widgets_estado.dart';

/// Cria a PRIMEIRA (ou uma nova) evolução de um pelotão. Sem esta tela, o
/// editor de partes existe mas é inalcançável — a lista de evoluções
/// (`TelaEvolucoes`) só sabe mostrar e apagar evoluções que já existem.
///
/// `estadoInicial` é derivado do grid do pelotão por [estadoInicialDoGrid]:
/// todo mundo parado, virado para o mesmo lado (setor 0), na célula que
/// corresponde à posição de cada slot — a formação de partida de qualquer
/// pelotão antes do primeiro comando.
///
/// Ao salvar, substitui esta tela pelo editor de partes (`pushReplacement`):
/// "Voltar" a partir do editor volta para a lista de evoluções, não para
/// este formulário — o mesmo padrão que "Duplicar evolução para outro
/// pelotão" já usa em `tela_editor_partes.dart`.
class TelaCriarEvolucao extends StatefulWidget {
  const TelaCriarEvolucao({super.key, required this.repo, required this.pelotao});

  final RepositorioEvo repo;
  final PelotaoDoc pelotao;

  @override
  State<TelaCriarEvolucao> createState() => _TelaCriarEvolucaoState();
}

class _TelaCriarEvolucaoState extends State<TelaCriarEvolucao> {
  late final TextEditingController _nomeCtrl;
  bool _salvando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _nomeCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    super.dispose();
  }

  Future<void> _criar() async {
    setState(() {
      _salvando = true;
      _erro = null;
    });
    final String nome = _nomeCtrl.text.trim().isEmpty
        ? 'Evolução sem nome'
        : _nomeCtrl.text.trim();
    final DateTime agora = DateTime.now();
    final EvolucaoDoc doc = EvolucaoDoc(
      id: widget.repo.novoId(),
      nome: nome,
      pelotaoId: widget.pelotao.id,
      estadoInicial: estadoInicialDoGrid(widget.pelotao),
      versaoCatalogo: versaoCatalogo,
      criadoEm: agora,
      atualizadoEm: agora,
    );
    try {
      await widget.repo.gravarEvolucao(doc);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => TelaEditorPartes(
            repo: widget.repo,
            evolucaoId: doc.id,
            controleEdicao: const TravaSempreMinha(),
          ),
        ),
      );
    } catch (erro) {
      if (!mounted) return;
      setState(() => _erro = mensagemFalha(erro));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Paleta.fundo,
      appBar: AppBar(title: const Text('Nova evolução')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            'Formação de partida: "${widget.pelotao.nome}" '
            '(${widget.pelotao.linhas}×${widget.pelotao.colunas}), todo '
            'mundo parado e virado para o mesmo lado. Você monta os '
            'movimentos na tela seguinte.',
            style: const TextStyle(color: Paleta.cinzaMedio),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nomeCtrl,
            autofocus: true,
            maxLength: 80,
            style: const TextStyle(color: Paleta.claro),
            decoration: const InputDecoration(labelText: 'Nome da evolução'),
            onSubmitted: (_) => _salvando ? null : _criar(),
          ),
          const SizedBox(height: 8),
          if (_erro != null) ...<Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Paleta.erroSuperficie,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_erro!, style: const TextStyle(color: Paleta.erro)),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Paleta.acento),
            onPressed: _salvando ? null : _criar,
            child: _salvando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Criar e abrir editor'),
          ),
        ],
      ),
    );
  }
}
