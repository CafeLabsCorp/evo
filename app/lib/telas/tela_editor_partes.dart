import 'dart:async';
import 'dart:math' as math;

import 'package:evo_motor/evo_motor.dart';
import 'package:flutter/material.dart';

import '../dados/controle_edicao.dart';
import '../dados/duplicar_evolucao.dart';
import '../dados/ordenacao_partes.dart';
import '../dados/repositorio_evo.dart';
import '../editor/controlador_editor_partes.dart';
import '../editor/descritores_movimento.dart';
import '../modelo/carregador_evolucao.dart';
import '../pintura/formacao_painter.dart';
import '../playback/controlador_playback.dart';
import '../tema/paleta.dart';
import 'tela_playback.dart';
import 'widgets_estado.dart';

/// Editor de partes — a tela make-or-break do produto (ver
/// `tarefas/empresa/evo.md`): entrada de dados touch-first para atribuir
/// movimento/direção/percussão a 1..N pessoas por parte, com o painel
/// filtrado pela cadência REAL da seleção (nunca uma lista cheia).
///
/// Largura ampla (desktop/tablet-paisagem, alvo primário): grid + painel
/// lado a lado. Retrato: painel vira bottom sheet, reaproveitando o MESMO
/// padrão de `_BotaoOpcoesGrade` em `tela_playback.dart` (nenhum componente
/// novo de apresentação responsiva).
class TelaEditorPartes extends StatelessWidget {
  const TelaEditorPartes({
    super.key,
    required this.repo,
    required this.evolucaoId,
    required this.controleEdicao,
  });

  final RepositorioEvo repo;
  final String evolucaoId;
  final ControleDeEdicao controleEdicao;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Paleta.fundo,
      body: StreamBuilder<EvolucaoDoc?>(
        stream: repo.evolucao(evolucaoId),
        builder: (BuildContext context, AsyncSnapshot<EvolucaoDoc?> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const CentroCarregando();
          }
          if (snapshot.hasError) {
            return CentroErro(erro: snapshot.error, aoTentarDeNovo: () {});
          }
          final EvolucaoDoc? evolucao = snapshot.data;
          if (evolucao == null) {
            return const CentroVazio(
              icone: Icons.edit_off_outlined,
              titulo: 'Esta evolução não existe mais',
              descricao: 'Ela pode ter sido apagada por você ou em outra sessão.',
            );
          }
          return _CorpoEditor(
            key: ValueKey<String>(evolucao.id),
            repo: repo,
            evolucaoId: evolucaoId,
            controleEdicao: controleEdicao,
            evolucaoInicial: evolucao,
          );
        },
      ),
    );
  }
}

class _CorpoEditor extends StatefulWidget {
  const _CorpoEditor({
    required super.key,
    required this.repo,
    required this.evolucaoId,
    required this.controleEdicao,
    required this.evolucaoInicial,
  });

  final RepositorioEvo repo;
  final String evolucaoId;
  final ControleDeEdicao controleEdicao;
  final EvolucaoDoc evolucaoInicial;

  @override
  State<_CorpoEditor> createState() => _CorpoEditorState();
}

class _CorpoEditorState extends State<_CorpoEditor> with SingleTickerProviderStateMixin {
  late final ControladorEditorPartes _controlador;
  StreamSubscription<List<ParteDoc>>? _subPartes;
  StreamSubscription<PelotaoDoc?>? _subPelotao;
  StreamSubscription<DonoDaTrava>? _subDono;
  Object? _erro;
  ControladorPlayback? _controladorPreview;
  PacoteEvolucao? _ultimoPacotePreview;

  @override
  void initState() {
    super.initState();
    _controlador = ControladorEditorPartes(repo: widget.repo, evolucaoId: widget.evolucaoId);
    _controlador.atualizarEvolucao(widget.evolucaoInicial);
    _assinar();
  }

  @override
  void didUpdateWidget(covariant _CorpoEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.evolucaoInicial != widget.evolucaoInicial) {
      _controlador.atualizarEvolucao(widget.evolucaoInicial);
    }
  }

  void _assinar() {
    _subPartes?.cancel();
    _subPelotao?.cancel();
    _subDono?.cancel();
    setState(() => _erro = null);
    _subPartes = widget.repo
        .partes(widget.evolucaoId)
        .listen(_controlador.atualizarPartes, onError: _tratarErro);
    _subPelotao = widget.repo
        .pelotao(widget.evolucaoInicial.pelotaoId)
        .listen(_controlador.atualizarPelotao, onError: _tratarErro);
    _subDono = widget.controleEdicao.dono().listen(_controlador.atualizarDono);
  }

  void _tratarErro(Object erro) {
    if (!mounted) return;
    setState(() => _erro = erro);
  }

  @override
  void dispose() {
    _controlador.flushPendente();
    _subPartes?.cancel();
    _subPelotao?.cancel();
    _subDono?.cancel();
    _controlador.dispose();
    _controladorPreview?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_erro != null) {
      return CentroErro(erro: _erro, aoTentarDeNovo: _assinar);
    }
    return AnimatedBuilder(
      animation: _controlador,
      builder: (BuildContext context, Widget? child) {
        if (_controlador.pelotao == null) {
          return const CentroCarregando();
        }
        return _ConteudoEditor(
          controlador: _controlador,
          repo: widget.repo,
          evolucaoId: widget.evolucaoId,
          pacotePreview: _construirPacotePreview(),
          controladorPreview: _obterControladorPreview(),
        );
      },
    );
  }

  PacoteEvolucao? _construirPacotePreview() {
    if (!_controlador.modoPreview) return null;
    final EvolucaoDoc? evo = _controlador.evolucao;
    if (evo == null) return null;
    final Evolucao evolucao = Evolucao(
      nome: evo.nome,
      estadoInicial: estadoFormacaoDoJson(evo.estadoInicial),
      partes: emOrdem(_controlador.partes),
    );
    return simularEvolucao(evolucao);
  }

  ControladorPlayback? _obterControladorPreview() {
    final PacoteEvolucao? pacote = _construirPacotePreview();
    if (pacote == null) {
      _controladorPreview?.dispose();
      _controladorPreview = null;
      _ultimoPacotePreview = null;
      return null;
    }
    if (!identical(pacote, _ultimoPacotePreview)) {
      _controladorPreview?.dispose();
      _controladorPreview = ControladorPlayback(pacote: pacote, vsync: this);
      _ultimoPacotePreview = pacote;
    }
    return _controladorPreview;
  }
}

class _ConteudoEditor extends StatelessWidget {
  const _ConteudoEditor({
    required this.controlador,
    required this.repo,
    required this.evolucaoId,
    required this.pacotePreview,
    required this.controladorPreview,
  });

  final ControladorEditorPartes controlador;
  final RepositorioEvo repo;
  final String evolucaoId;
  final PacoteEvolucao? pacotePreview;
  final ControladorPlayback? controladorPreview;

  @override
  Widget build(BuildContext context) {
    final EvolucaoDoc? evolucao = controlador.evolucao;
    return Scaffold(
      backgroundColor: Paleta.fundo,
      appBar: AppBar(
        title: Text(evolucao?.nome ?? 'Editor de partes'),
        actions: <Widget>[
          IconButton(
            tooltip: controlador.proximoUndoEExclusao
                ? 'Desfazer exclusão de parte'
                : 'Desfazer',
            icon: const Icon(Icons.undo),
            onPressed: controlador.temUndo && controlador.podeEditar
                ? controlador.desfazer
                : null,
          ),
          PopupMenuButton<String>(
            onSelected: (String v) => _executarAcaoMenu(context, v),
            itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'duplicar_parte',
                child: Text('Duplicar parte atual'),
              ),
              PopupMenuItem<String>(
                value: 'duplicar_evolucao',
                child: Text('Duplicar evolução para outro pelotão'),
              ),
              PopupMenuItem<String>(
                value: 'apagar_parte',
                child: Text('Apagar parte atual'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (!controlador.podeEditar) const _BannerTrava(),
          _SeletorModoEdicaoPreview(controlador: controlador),
          Expanded(
            child: controlador.modoPreview
                ? _Preview(controlador: controladorPreview)
                : _AreaDeEdicao(controlador: controlador),
          ),
        ],
      ),
    );
  }

  Future<void> _executarAcaoMenu(BuildContext context, String acao) async {
    switch (acao) {
      case 'duplicar_parte':
        final int? i = controlador.indiceSelecionado;
        if (i == null) return;
        await controlador.duplicarParte(i);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Parte duplicada.')));
        }
      case 'apagar_parte':
        final bool? confirmar = await _confirmar(
          context,
          titulo: 'Apagar esta parte?',
          mensagem: 'Não dá para desfazer pelo undo desta sessão depois de fechar o editor.',
        );
        if (confirmar == true) await controlador.apagarParteAtual();
      case 'duplicar_evolucao':
        await _abrirDuplicarEvolucao(context);
    }
  }

  Future<bool?> _confirmar(
    BuildContext context, {
    required String titulo,
    required String mensagem,
  }) => showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      backgroundColor: Paleta.superficie,
      title: Text(titulo, style: const TextStyle(color: Paleta.claro)),
      content: Text(mensagem, style: const TextStyle(color: Paleta.cinzaMedio)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Paleta.erro),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Confirmar'),
        ),
      ],
    ),
  );

  Future<void> _abrirDuplicarEvolucao(BuildContext context) async {
    final EvolucaoDoc? evolucao = controlador.evolucao;
    if (evolucao == null) return;
    final List<PelotaoDoc> pelotoes = await repo.pelotoes().first;
    final List<PelotaoDoc> destinos = pelotoes
        .where((PelotaoDoc p) => p.id != evolucao.pelotaoId)
        .toList();
    if (!context.mounted) return;
    if (destinos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não há outro pelotão para duplicar esta evolução.'),
        ),
      );
      return;
    }
    final PelotaoDoc? destino = await showDialog<PelotaoDoc>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        backgroundColor: Paleta.superficie,
        title: const Text(
          'Duplicar para qual pelotão?',
          style: TextStyle(color: Paleta.claro),
        ),
        children: <Widget>[
          for (final PelotaoDoc p in destinos)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(p),
              child: Text(p.nome, style: const TextStyle(color: Paleta.claro)),
            ),
        ],
      ),
    );
    if (destino == null || !context.mounted) return;
    final ScaffoldMessengerState mensageiro = ScaffoldMessenger.of(context);
    try {
      final String novaId = await duplicarEvolucaoParaPelotao(
        repo: repo,
        evolucaoId: evolucaoId,
        pelotaoIdDestino: destino.id,
      );
      if (!context.mounted) return;
      mensageiro.showSnackBar(
        SnackBar(content: Text('Cópia criada para "${destino.nome}". Abrindo...')),
      );
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TelaEditorPartes(
            repo: repo,
            evolucaoId: novaId,
            controleEdicao: const TravaSempreMinha(),
          ),
        ),
      );
    } catch (erro) {
      mensageiro.showSnackBar(SnackBar(content: Text(mensagemFalha(erro))));
    }
  }
}

class _BannerTrava extends StatelessWidget {
  const _BannerTrava();

  @override
  Widget build(BuildContext context) {
    // A interface `ControleDeEdicao`/`DonoDaTrava` hoje (`TravaSempreMinha`)
    // não carrega QUEM é o outro editor — só "eu" ou "outra pessoa" (ver
    // dartdoc de `DonoDaTrava`). Quando a trava real (lease com
    // `editandoPor: {uid, nome, expiraEm}`, já decidida em
    // `tarefas/empresa/evo.md`) chegar, ela deve estender essa informação
    // para cá; até lá, o banner fica genérico em vez de inventar um nome.
    // NUNCA mostra contagem regressiva (decisão do `design`).
    return Material(
      color: Paleta.erroSuperficie,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: <Widget>[
            const Icon(Icons.lock_outline, color: Paleta.acento),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Outra pessoa está editando esta evolução agora — modo somente '
                'leitura.',
                style: TextStyle(color: Paleta.claro),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Toggle explícito Editando ↔ Pré-visualizando — a seleção fica guardada
/// mas oculta durante a prévia (ver `_AreaDeEdicao`, que só é montada em
/// modo Editando).
class _SeletorModoEdicaoPreview extends StatelessWidget {
  const _SeletorModoEdicaoPreview({required this.controlador});
  final ControladorEditorPartes controlador;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: ChoiceChip(
              label: const Text('Editando'),
              selected: !controlador.modoPreview,
              selectedColor: Paleta.acento.withValues(alpha: 0.35),
              backgroundColor: Paleta.cinzaEscuro,
              labelStyle: const TextStyle(color: Paleta.claro),
              onSelected: (_) {
                if (controlador.modoPreview) controlador.alternarPreview();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ChoiceChip(
              label: const Text('Pré-visualizando'),
              selected: controlador.modoPreview,
              selectedColor: Paleta.acento.withValues(alpha: 0.35),
              backgroundColor: Paleta.cinzaEscuro,
              labelStyle: const TextStyle(color: Paleta.claro),
              onSelected: (_) {
                if (!controlador.modoPreview) controlador.alternarPreview();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.controlador});
  final ControladorPlayback? controlador;

  @override
  Widget build(BuildContext context) {
    final ControladorPlayback? c = controlador;
    if (c == null) return const CentroCarregando();
    return CorpoPlayback(controlador: c);
  }
}

/// Corpo principal em modo "Editando": fileira de partes, chips de seleção,
/// grid, e o painel de atribuição — lado a lado em telas largas
/// (desktop/tablet-paisagem, alvo primário), ou o mesmo painel dentro de um
/// bottom sheet em telas estreitas (retrato), reaproveitando o padrão de
/// `_BotaoOpcoesGrade` de `tela_playback.dart`.
class _AreaDeEdicao extends StatelessWidget {
  const _AreaDeEdicao({required this.controlador});
  final ControladorEditorPartes controlador;

  static const double _limiarLargo = 900;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool largo = constraints.maxWidth >= _limiarLargo;
        final Widget grade = Column(
          children: <Widget>[
            _FaixaPartes(controlador: controlador),
            _BarraSelecao(controlador: controlador),
            Expanded(child: _GradeSlots(controlador: controlador)),
          ],
        );
        if (largo) {
          return Row(
            children: <Widget>[
              Expanded(child: grade),
              SizedBox(
                width: 340,
                child: Material(
                  color: Paleta.superficie,
                  child: _PainelAtribuicao(controlador: controlador),
                ),
              ),
            ],
          );
        }
        return Column(
          children: <Widget>[
            Expanded(child: grade),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  icon: const Icon(Icons.tune),
                  label: Text(
                    controlador.selecionados.isEmpty
                        ? 'Selecione alguém para atribuir'
                        : 'Atribuir movimento (${controlador.selecionados.length})',
                  ),
                  onPressed: controlador.selecionados.isEmpty
                      ? null
                      : () => _abrirPainelEmBottomSheet(context),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _abrirPainelEmBottomSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Paleta.superficie,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return AnimatedBuilder(
          animation: controlador,
          builder: (BuildContext context, Widget? child) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            expand: false,
            builder: (BuildContext context, ScrollController scroll) => SingleChildScrollView(
              controller: scroll,
              child: _PainelAtribuicao(controlador: controlador),
            ),
          ),
        );
      },
    );
  }
}

/// Fileira de bolinhas navegável — mesma linguagem visual de
/// `_FaixaBolinhas` em `tela_playback.dart`, mas interativa: "+" cria uma
/// parte nova de verdade (vazia, todo mundo em continuação implícita, com
/// toast confirmando).
class _FaixaPartes extends StatelessWidget {
  const _FaixaPartes({required this.controlador});
  final ControladorEditorPartes controlador;

  @override
  Widget build(BuildContext context) {
    final List<ParteDoc> partes = controlador.partes;
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: <Widget>[
          for (int i = 0; i < partes.length; i++) ...<Widget>[
            _BolinhaParte(
              numero: i + 1,
              nome: partes[i].nome,
              selecionada: controlador.indiceSelecionado == i,
              onTap: () => controlador.selecionarParte(i),
            ),
            if (i < partes.length - 1) const _Seta(),
          ],
          if (partes.isNotEmpty) const _Seta(),
          _BotaoAdicionarParteReal(controlador: controlador),
        ],
      ),
    );
  }
}

class _BolinhaParte extends StatelessWidget {
  const _BolinhaParte({
    required this.numero,
    required this.selecionada,
    required this.onTap,
    this.nome,
  });
  final int numero;
  final String? nome;
  final bool selecionada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Parte $numero${nome != null ? ' — $nome' : ''}',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selecionada ? Paleta.acento.withValues(alpha: 0.25) : Paleta.cinzaEscuro,
            border: Border.all(
              color: selecionada ? Paleta.acento : Paleta.cinzaMedio,
              width: selecionada ? 2.5 : 1.5,
            ),
          ),
          child: Text(
            '$numero',
            style: TextStyle(
              color: selecionada ? Paleta.acento : Paleta.claro,
              fontWeight: selecionada ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _Seta extends StatelessWidget {
  const _Seta();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 4),
    child: Icon(Icons.arrow_right_alt, color: Paleta.cinzaMedio),
  );
}

class _BotaoAdicionarParteReal extends StatelessWidget {
  const _BotaoAdicionarParteReal({required this.controlador});
  final ControladorEditorPartes controlador;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: 'Nova parte (vazia)',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: controlador.podeEditar ? () => _adicionar(context) : null,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Paleta.cinzaMedio, width: 1.5),
            ),
            child: const Icon(Icons.add, color: Paleta.cinzaMedio),
          ),
        ),
      ),
    );
  }

  Future<void> _adicionar(BuildContext context) async {
    final ParteDoc nova = await controlador.adicionarParteVazia();
    if (!context.mounted) return;
    controlador.selecionarParte(controlador.partes.indexWhere((ParteDoc p) => p.id == nova.id));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Parte nova criada — todo mundo em continuação.')),
    );
  }
}

/// Chips de seleção: fileira N / coluna N / todos / inverter + subgrupos
/// salvos. Fileira/coluna/todos SUBSTITUEM a seleção corrente (1 toque =
/// "selecione exatamente isto", o caso mais comum ao passar de um subgrupo
/// para o próximo); toque individual num slot do grid é ADITIVO (ver
/// `ControladorEditorPartes.alternarSlot`) para montar combinações
/// manuais. "Inverter" opera sobre a seleção atual.
class _BarraSelecao extends StatelessWidget {
  const _BarraSelecao({required this.controlador});
  final ControladorEditorPartes controlador;

  @override
  Widget build(BuildContext context) {
    final PelotaoDoc? p = controlador.pelotao;
    if (p == null) return const SizedBox.shrink();
    // Trava: nenhum chip de seleção reage — o editor inteiro (não só o
    // painel de atribuição) fica somente-leitura enquanto outra pessoa
    // edita, para não deixar a tela num estado parcialmente interativo
    // (seleção muda, mas nada pode ser aplicado).
    final bool ativo = controlador.podeEditar;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: <Widget>[
          for (int l = 0; l < p.linhas; l++)
            _Chip(
              rotulo: 'Fileira ${l + 1}',
              onTap: ativo ? () => controlador.selecionarFileira(l) : null,
            ),
          for (int c = 0; c < p.colunas; c++)
            _Chip(
              rotulo: 'Coluna ${c + 1}',
              onTap: ativo ? () => controlador.selecionarColuna(c) : null,
            ),
          _Chip(rotulo: 'Todos', onTap: ativo ? controlador.selecionarTodos : null),
          _Chip(rotulo: 'Inverter', onTap: ativo ? controlador.inverterSelecao : null),
          _Chip(
            rotulo: 'Limpar',
            onTap: ativo && controlador.selecionados.isNotEmpty
                ? controlador.limparSelecao
                : null,
          ),
          for (final String nome in controlador.subgrupos.keys)
            _Chip(
              rotulo: nome,
              destacado: true,
              onTap: ativo ? () => controlador.aplicarSubgrupo(nome) : null,
              onLongPress: ativo ? () => controlador.apagarSubgrupo(nome) : null,
            ),
          if (ativo && controlador.selecionados.isNotEmpty)
            _Chip(
              rotulo: 'Salvar subgrupo',
              icone: Icons.bookmark_add_outlined,
              onTap: () => _pedirNomeSubgrupo(context),
            ),
        ],
      ),
    );
  }

  Future<void> _pedirNomeSubgrupo(BuildContext context) async {
    final TextEditingController ctrl = TextEditingController();
    final String? nome = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: Paleta.superficie,
        title: const Text('Nome do subgrupo', style: TextStyle(color: Paleta.claro)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Paleta.claro),
          decoration: const InputDecoration(hintText: 'ex.: Bravo'),
          onSubmitted: (String v) => Navigator.of(context).pop(v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (nome != null && nome.trim().isNotEmpty) {
      controlador.salvarSubgrupoAtual(nome);
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.rotulo,
    required this.onTap,
    this.onLongPress,
    this.icone,
    this.destacado = false,
  });
  final String rotulo;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final IconData? icone;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        avatar: icone == null ? null : Icon(icone, size: 16, color: Paleta.claro),
        label: Text(rotulo),
        backgroundColor: destacado
            ? Paleta.acento.withValues(alpha: 0.25)
            : Paleta.cinzaEscuro,
        labelStyle: TextStyle(color: onTap == null ? Paleta.cinzaMedio : Paleta.claro),
        onPressed: onTap,
      ),
    );
  }
}

/// O grid do editor — correção de 2026-09-15: até aqui isto era um layout
/// FIXO por índice de slot, sempre desenhado "para cima" (facing nunca
/// acumulava giro parte a parte). O instrutor montava uma parte sem ver
/// pra onde as pessoas estavam viradas nem onde elas estavam de verdade —
/// exatamente a classe de erro que só aparece no ensaio.
///
/// Agora mostra o ESTADO DE ENTRADA real da parte selecionada (posição +
/// direção + cadência), obtido de [ControladorEditorPartes.
/// estadoEntradaSelecionada] — que é literalmente `simular(estadoInicial,
/// partes[0..k-1])`, nunca um valor aproximado. Continua valendo a
/// distinção do motor: **slot é identidade, não localização** — os chips
/// de "Fileira N"/"Coluna N" (`_BarraSelecao`) continuam operando sobre o
/// grid ORIGINAL do pelotão; é só o DESENHO que passou a refletir onde a
/// pessoa está de verdade.
class _GradeSlots extends StatelessWidget {
  const _GradeSlots({required this.controlador});
  final ControladorEditorPartes controlador;

  @override
  Widget build(BuildContext context) {
    final PelotaoDoc? p = controlador.pelotao;
    if (p == null || controlador.indiceSelecionado == null) {
      return const CentroVazio(
        icone: Icons.movie_creation_outlined,
        titulo: 'Nenhuma parte ainda',
        descricao: 'Toque em "+" na fileira acima para criar a primeira parte.',
      );
    }
    final EstadoFormacao? entrada = controlador.estadoEntradaSelecionada;
    if (entrada == null) {
      return const CentroCarregando();
    }
    final List<Diagnostico> diagnosticos = controlador.diagnosticosEntradaSelecionada;
    return Column(
      children: <Widget>[
        // Diagnósticos NUNCA ficam escondidos: se a simulação até a parte
        // anterior já encontrou comando impossível ou colisão, é
        // informação de que a parte que o instrutor está montando agora
        // parte de um estado quebrado — mostrar, nunca abortar (mesma
        // disciplina das quatro checagens do motor).
        if (diagnosticos.isNotEmpty) _AvisoDiagnosticosEntrada(diagnosticos: diagnosticos),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _FormacaoEditorInterativa(controlador: controlador, entrada: entrada, pelotao: p),
          ),
        ),
      ],
    );
  }
}

class _AvisoDiagnosticosEntrada extends StatelessWidget {
  const _AvisoDiagnosticosEntrada({required this.diagnosticos});
  final List<Diagnostico> diagnosticos;

  @override
  Widget build(BuildContext context) {
    final int erros = diagnosticos
        .where((Diagnostico d) => d.severidade == SeveridadeDiagnostico.erro)
        .length;
    final int avisos = diagnosticos.length - erros;
    return Material(
      color: Paleta.erroSuperficie,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: <Widget>[
            const Icon(Icons.warning_amber_rounded, color: Paleta.acento),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'A simulação até esta parte encontrou $erros erro(s)'
                '${avisos > 0 ? ' e $avisos aviso(s)' : ''} — o estado de '
                'entrada mostrado abaixo pode não refletir o que vai '
                'acontecer de verdade no ensaio.',
                style: const TextStyle(color: Paleta.claro, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Desenha [entrada] com [FormacaoPainter] em modo editor (reaproveitado
/// do playback — ver dartdoc de [FormacaoPainter.modoEditor], nunca um
/// segundo `CustomPainter`) e faz o hit-testing por PROXIMIDADE: com gente
/// fora dos cruzamentos do grid original, "que slot está aqui" deixa de
/// ser divisão inteira — toque seleciona a pessoa mais perto, dentro de um
/// raio, nunca por índice de célula.
class _FormacaoEditorInterativa extends StatelessWidget {
  const _FormacaoEditorInterativa({
    required this.controlador,
    required this.entrada,
    required this.pelotao,
  });

  final ControladorEditorPartes controlador;
  final EstadoFormacao entrada;
  final PelotaoDoc pelotao;

  List<EstadoRenderizado> _estados() => <EstadoRenderizado>[
    for (final int slot in entrada.slots)
      _paraEstadoRenderizado(slot, entrada[slot]),
  ];

  EstadoRenderizado _paraEstadoRenderizado(int slot, EstadoPessoa pessoa) {
    final (double linha, double coluna) = pessoa.posicao.emCelulas();
    return EstadoRenderizado(
      slot: slot,
      linha: linha,
      coluna: coluna,
      anguloGraus: pessoa.dir * 45.0,
      cadencia: pessoa.cad,
      batidas: const <TipoBatida>{},
    );
  }

  Rect _enquadramento(List<EstadoRenderizado> estados) {
    if (estados.isEmpty) return Rect.zero;
    double minLinha = estados.first.linha;
    double maxLinha = minLinha;
    double minColuna = estados.first.coluna;
    double maxColuna = minColuna;
    for (final EstadoRenderizado e in estados) {
      if (e.linha < minLinha) minLinha = e.linha;
      if (e.linha > maxLinha) maxLinha = e.linha;
      if (e.coluna < minColuna) minColuna = e.coluna;
      if (e.coluna > maxColuna) maxColuna = e.coluna;
    }
    return Rect.fromLTRB(minColuna, minLinha, maxColuna, maxLinha);
  }

  /// Ajusta [disponivel] ao [aspecto] alvo preservando proporção (o mesmo
  /// que `AspectRatio` faria) — feito à mão, em vez de usar o widget,
  /// porque o hit-testing e o posicionamento dos rótulos precisam do
  /// `Size` exato da caixa de desenho, e `AspectRatio` não expõe isso sem
  /// uma segunda consulta ao `RenderBox` depois do layout.
  Size _ajustarAspecto(Size disponivel, double aspecto) {
    if (aspecto <= 0 || disponivel.width <= 0 || disponivel.height <= 0) {
      return disponivel;
    }
    double largura = disponivel.width;
    double altura = largura / aspecto;
    if (altura > disponivel.height) {
      altura = disponivel.height;
      largura = altura * aspecto;
    }
    return Size(largura, altura);
  }

  @override
  Widget build(BuildContext context) {
    final List<EstadoRenderizado> estados = _estados();
    final Rect enquadramento = _enquadramento(estados);
    final Map<String, dynamic> atribuicoes = controlador.atribuicoesEfetivas();
    final Set<int> continuacao = <int>{
      for (final EstadoRenderizado e in estados)
        if (controlador.recebeuAtribuicaoNestaParte(e.slot)) e.slot,
    };
    final Set<int> comPercussao = <int>{
      for (final EstadoRenderizado e in estados)
        if (atribuicoes['${e.slot}'] case final Map<String, dynamic> a
            when a['percussao'] != null)
          e.slot,
    };

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size disponivel = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
        );
        final Rect caixaComMargem = enquadramento.inflate(FormacaoPainter.margemCelulas);
        final double aspecto = (caixaComMargem.width <= 0 || caixaComMargem.height <= 0)
            ? 1
            : caixaComMargem.width / caixaComMargem.height;
        final Size caixa = _ajustarAspecto(disponivel, aspecto);
        final TransformacaoEnquadramento transformacao = TransformacaoEnquadramento.calcular(
          enquadramento: enquadramento,
          tela: caixa,
          margemCelulas: FormacaoPainter.margemCelulas,
          escalaMinimaPx: FormacaoPainter.escalaMinimaPx,
          escalaMaximaPx: FormacaoPainter.escalaMaximaPx,
        );
        return Center(
          child: SizedBox(
            width: caixa.width,
            height: caixa.height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: controlador.podeEditar
                  ? (TapUpDetails d) =>
                        _selecionarPorProximidade(d.localPosition, caixa, transformacao, estados)
                  : null,
              child: Stack(
                children: <Widget>[
                  CustomPaint(
                    size: caixa,
                    painter: FormacaoPainter(
                      estados: estados,
                      campo: const Campo(),
                      enquadramento: enquadramento,
                      mostrarPontos: true,
                      modoEditor: true,
                      slotsSelecionados: controlador.selecionados,
                      slotsComContinuacao: continuacao,
                      slotsComPercussaoEditor: comPercussao,
                    ),
                  ),
                  for (final EstadoRenderizado e in estados)
                    _rotulo(caixa, transformacao, e),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Toque -> pessoa mais perto, dentro de um raio (nunca por índice de
  /// célula — ver dartdoc de classe). Fora do raio, o toque é descartado
  /// (nenhuma seleção troca "por acidente" para alguém longe do dedo).
  void _selecionarPorProximidade(
    Offset local,
    Size caixa,
    TransformacaoEnquadramento transformacao,
    List<EstadoRenderizado> estados,
  ) {
    if (estados.isEmpty) return;
    // Meia célula de raio, com piso absoluto de 24px — mesmo espírito do
    // alvo de toque mínimo (~76px de lado) que o grid fixo antigo usava:
    // suficiente pra acertar com o dedo, sem roubar o toque de um vizinho
    // real a mais de meia célula de distância.
    final double raioPx = math.max(transformacao.tamanhoCelulaPx * 0.6, 24);
    EstadoRenderizado? maisPerto;
    double menorDistancia = double.infinity;
    for (final EstadoRenderizado e in estados) {
      final Offset tela = FormacaoPainter.converterParaTela(caixa, transformacao, e.linha, e.coluna);
      final double distancia = (tela - local).distance;
      if (distancia < menorDistancia) {
        menorDistancia = distancia;
        maisPerto = e;
      }
    }
    if (maisPerto != null && menorDistancia <= raioPx) {
      controlador.alternarSlot(maisPerto.slot);
    }
  }

  static const double _larguraRotulo = 64;

  Widget _rotulo(Size caixa, TransformacaoEnquadramento transformacao, EstadoRenderizado e) {
    final Offset centro = FormacaoPainter.converterParaTela(caixa, transformacao, e.linha, e.coluna);
    final String rotulo = pelotao.rotulos['${e.slot}'] ?? 'Slot ${e.slot}';
    return Positioned(
      left: centro.dx - _larguraRotulo / 2,
      top: centro.dy + transformacao.tamanhoCelulaPx * 0.5,
      width: _larguraRotulo,
      child: IgnorePointer(
        child: Text(
          rotulo,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Paleta.cinzaMedio, fontSize: 10),
        ),
      ),
    );
  }
}

/// O painel de atribuição — núcleo da tela. Filtra os 16 movimentos pela
/// cadência corrente da seleção via `checarPrecondicao` de verdade (ver
/// `descritores_movimento.dart`); grupo inteiro some quando nenhum item
/// dele é válido; parâmetros só aparecem quando o movimento os tem.
class _PainelAtribuicao extends StatelessWidget {
  const _PainelAtribuicao({required this.controlador});
  final ControladorEditorPartes controlador;

  @override
  Widget build(BuildContext context) {
    if (controlador.selecionados.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Selecione alguém no grid (ou use os chips de fileira/coluna) para '
          'ver os movimentos disponíveis.',
          style: TextStyle(color: Paleta.cinzaMedio),
        ),
      );
    }

    final List<MovimentoValido> validos = controlador.movimentosValidos;
    final Map<GrupoMovimento, List<MovimentoValido>> porGrupo = <GrupoMovimento, List<MovimentoValido>>{};
    for (final MovimentoValido m in validos) {
      porGrupo.putIfAbsent(m.descritor.grupo, () => <MovimentoValido>[]).add(m);
    }

    final DescritorMovimento? descritorAtual = validos
        .where((MovimentoValido m) => m.descritor.tipo == controlador.painel.tipo)
        .map((MovimentoValido m) => m.descritor)
        .firstOrNullOuSonda(controlador.painel.tipo);

    final bool desabilitado = !controlador.podeEditar;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '${controlador.selecionados.length} selecionado(s)',
            style: const TextStyle(color: Paleta.claro, fontWeight: FontWeight.bold),
          ),
          if (controlador.selecaoTemCadenciaMista) _AvisoCadenciaMista(controlador: controlador),
          if (validos.any((MovimentoValido m) => m.descritor.tipo == controlador.painel.tipo && m.avisoTeleporte))
            const _AvisoTeleporte(),
          const SizedBox(height: 8),
          for (final GrupoMovimento grupo in GrupoMovimento.values)
            if (porGrupo[grupo] case final List<MovimentoValido> itens when itens.isNotEmpty)
              _SecaoGrupo(
                grupo: grupo,
                itens: itens,
                tipoSelecionado: controlador.painel.tipo,
                habilitado: !desabilitado,
                onEscolher: controlador.escolherMovimento,
              ),
          if (descritorAtual != null) ...<Widget>[
            const Divider(color: Paleta.cinzaEscuro),
            _ParametrosMovimento(
              controlador: controlador,
              descritor: descritorAtual,
              habilitado: !desabilitado,
            ),
          ],
          const Divider(color: Paleta.cinzaEscuro),
          _SecaoPercussao(controlador: controlador, habilitado: !desabilitado),
          const SizedBox(height: 12),
          if (controlador.temUltimaAtribuicao)
            OutlinedButton.icon(
              icon: const Icon(Icons.repeat),
              label: const Text('Reaplicar última atribuição'),
              onPressed: desabilitado ? null : controlador.reaplicarUltimaAtribuicao,
            ),
        ],
      ),
    );
  }
}

extension _BuscaDescritor on Iterable<DescritorMovimento> {
  /// Acha o descritor pelo tipo já escolhido no painel mesmo quando a lista
  /// de válidos mudou (ex.: seleção mista momentânea) — cai no catálogo
  /// completo como fallback só para exibir os parâmetros do que já estava
  /// escolhido, nunca para reintroduzir um tipo inválido na LISTA de
  /// escolha (essa nunca inclui itens fora de `movimentosValidos`).
  DescritorMovimento? firstOrNullOuSonda(String? tipo) {
    if (tipo == null) return null;
    for (final DescritorMovimento d in this) {
      if (d.tipo == tipo) return d;
    }
    for (final DescritorMovimento d in descritoresCatalogo) {
      if (d.tipo == tipo) return d;
    }
    return null;
  }
}

class _AvisoCadenciaMista extends StatelessWidget {
  const _AvisoCadenciaMista({required this.controlador});
  final ControladorEditorPartes controlador;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Paleta.erroSuperficie,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Seleção com cadências diferentes — só movimentos válidos para '
            'todo mundo aparecem abaixo.',
            style: TextStyle(color: Paleta.claro, fontSize: 13),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: controlador.dividirSelecaoPorEstado,
              child: const Text('Dividir seleção por estado'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvisoTeleporte extends StatelessWidget {
  const _AvisoTeleporte();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Paleta.cinzaEscuro,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, color: Paleta.acento, size: 18),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Quem está marchando vai parar de repente (parada teleportada) '
              'com este comando.',
              style: TextStyle(color: Paleta.claro, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecaoGrupo extends StatelessWidget {
  const _SecaoGrupo({
    required this.grupo,
    required this.itens,
    required this.tipoSelecionado,
    required this.habilitado,
    required this.onEscolher,
  });

  final GrupoMovimento grupo;
  final List<MovimentoValido> itens;
  final String? tipoSelecionado;
  final bool habilitado;
  final ValueChanged<String> onEscolher;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            grupo.rotulo,
            style: const TextStyle(
              color: Paleta.cinzaMedio,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final MovimentoValido m in itens)
                ChoiceChip(
                  label: Text(m.descritor.nome),
                  selected: tipoSelecionado == m.descritor.tipo,
                  selectedColor: Paleta.acento.withValues(alpha: 0.35),
                  backgroundColor: Paleta.cinzaEscuro,
                  labelStyle: const TextStyle(color: Paleta.claro, fontSize: 12),
                  onSelected: habilitado ? (_) => onEscolher(m.descritor.tipo) : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

const List<int> _presetsQuantidade = <int>[1, 2, 4, 8];

class _ParametrosMovimento extends StatelessWidget {
  const _ParametrosMovimento({
    required this.controlador,
    required this.descritor,
    required this.habilitado,
  });

  final ControladorEditorPartes controlador;
  final DescritorMovimento descritor;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    final EstadoPainelAtribuicao painel = controlador.painel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (descritor.precisaQuantidade) ...<Widget>[
          const Text('Tempos', style: TextStyle(color: Paleta.cinzaMedio, fontSize: 11)),
          Wrap(
            spacing: 6,
            children: <Widget>[
              for (final int v in _presetsQuantidade)
                ChoiceChip(
                  label: Text('$v'),
                  selected: painel.quantidade == v,
                  selectedColor: Paleta.acento.withValues(alpha: 0.35),
                  backgroundColor: Paleta.cinzaEscuro,
                  labelStyle: const TextStyle(color: Paleta.claro),
                  onSelected: habilitado ? (_) => controlador.definirQuantidade(v) : null,
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (descritor.precisaAoTerminar) ...<Widget>[
          const Text('Ao terminar', style: TextStyle(color: Paleta.cinzaMedio, fontSize: 11)),
          Wrap(
            spacing: 6,
            children: <Widget>[
              for (final AoTerminarMarche v in AoTerminarMarche.values)
                ChoiceChip(
                  label: Text(_rotuloAoTerminar(v)),
                  selected: painel.aoTerminar == v,
                  selectedColor: Paleta.acento.withValues(alpha: 0.35),
                  backgroundColor: Paleta.cinzaEscuro,
                  labelStyle: const TextStyle(color: Paleta.claro),
                  onSelected: habilitado ? (_) => controlador.definirAoTerminar(v) : null,
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (descritor.aceitaBateRitmoAoJuntar)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Bater o ritmo ao juntar',
              style: TextStyle(color: Paleta.claro, fontSize: 13),
            ),
            activeThumbColor: Paleta.acento,
            value: painel.bateRitmoAoJuntar,
            onChanged: habilitado ? controlador.definirBateRitmoAoJuntar : null,
          ),
      ],
    );
  }
}

String _rotuloAoTerminar(AoTerminarMarche v) => switch (v) {
  AoTerminarMarche.marchando => 'Marchando',
  AoTerminarMarche.marcandoPasso => 'Marcando passo',
  AoTerminarMarche.firme => 'Firme',
};

/// Percussão: seção SEMPRE separada — 4 chips (Nenhuma/Mão/Perna E/Perna
/// D), desabilitada quando a cadência de entrada é `descansar` ou o
/// movimento escolhido é `Descansar`.
class _SecaoPercussao extends StatelessWidget {
  const _SecaoPercussao({required this.controlador, required this.habilitado});
  final ControladorEditorPartes controlador;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    final bool ativo = habilitado && !controlador.percussaoDesabilitada;
    final MembroPercussao? atual = controlador.painel.percussao;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('Percussão', style: TextStyle(color: Paleta.cinzaMedio, fontSize: 11)),
        Wrap(
          spacing: 6,
          children: <Widget>[
            ChoiceChip(
              label: const Text('Nenhuma'),
              selected: atual == null,
              selectedColor: Paleta.acento.withValues(alpha: 0.35),
              backgroundColor: Paleta.cinzaEscuro,
              labelStyle: TextStyle(color: ativo ? Paleta.claro : Paleta.cinzaMedio),
              onSelected: ativo ? (_) => controlador.definirPercussao(null) : null,
            ),
            for (final MembroPercussao m in MembroPercussao.values)
              ChoiceChip(
                label: Text(_rotuloMembro(m)),
                selected: atual == m,
                selectedColor: Paleta.acento.withValues(alpha: 0.35),
                backgroundColor: Paleta.cinzaEscuro,
                labelStyle: TextStyle(color: ativo ? Paleta.claro : Paleta.cinzaMedio),
                onSelected: ativo ? (_) => controlador.definirPercussao(m) : null,
              ),
          ],
        ),
        if (controlador.percussaoDesabilitada)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Descansar não aceita percussão.',
              style: TextStyle(color: Paleta.cinzaMedio, fontSize: 11),
            ),
          ),
      ],
    );
  }
}

String _rotuloMembro(MembroPercussao m) => switch (m) {
  MembroPercussao.mao => 'Mão',
  MembroPercussao.pernaEsquerda => 'Perna E',
  MembroPercussao.pernaDireita => 'Perna D',
};
