import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dados/repositorio_evo.dart';
import '../tema/paleta.dart';
import 'widgets_estado.dart';

/// Configuração de pelotão: tamanho do grid (1..6 × 1..6) e rótulo de cada
/// posição. Único formulário de edição da Etapa 4 (não há editor de
/// evolução ainda) — e o único lugar do app inteiro onde dado pessoal de
/// membro do pelotão é digitado, por isso o microcopy de compliance fica
/// fixo, sempre visível, junto do grid (não escondido em tooltip).
///
/// `pelotaoExistente == null` → modo criar. Caso contrário → modo editar
/// (com ação de apagar o pelotão, Etapa 5).
class TelaConfiguracaoPelotao extends StatefulWidget {
  const TelaConfiguracaoPelotao({
    super.key,
    required this.repo,
    required this.pelotaoExistente,
  });

  final RepositorioEvo repo;
  final PelotaoDoc? pelotaoExistente;

  @override
  State<TelaConfiguracaoPelotao> createState() => _TelaConfiguracaoPelotaoState();
}

class _TelaConfiguracaoPelotaoState extends State<TelaConfiguracaoPelotao> {
  late final TextEditingController _nomeCtrl;
  late int _linhas;
  late int _colunas;
  late Map<int, TextEditingController> _rotuloCtrls;

  bool _salvando = false;
  String? _erro;

  bool get _editando => widget.pelotaoExistente != null;

  @override
  void initState() {
    super.initState();
    final PelotaoDoc? p = widget.pelotaoExistente;
    _nomeCtrl = TextEditingController(text: p?.nome ?? '');
    _linhas = p?.linhas ?? 3;
    _colunas = p?.colunas ?? 3;
    _rotuloCtrls = _controladoresParaGrid(p?.rotulos ?? const <String, String>{});
  }

  Map<int, TextEditingController> _controladoresParaGrid(
    Map<String, String> rotulosAtuais,
  ) => <int, TextEditingController>{
    for (int i = 0; i < _linhas * _colunas; i++)
      i: TextEditingController(text: rotulosAtuais['$i'] ?? ''),
  };

  void _mudarTamanho({int? linhas, int? colunas}) {
    // Preserva o que já foi digitado nos slots que continuam existindo;
    // slots que saem do grid (grid encolheu) perdem o rótulo — é
    // comportamento esperado, não um bug: o slot deixou de existir.
    final Map<String, String> atuais = <String, String>{
      for (final MapEntry<int, TextEditingController> e in _rotuloCtrls.entries)
        if (e.value.text.trim().isNotEmpty) '${e.key}': e.value.text.trim(),
    };
    for (final TextEditingController c in _rotuloCtrls.values) {
      c.dispose();
    }
    setState(() {
      _linhas = linhas ?? _linhas;
      _colunas = colunas ?? _colunas;
      _rotuloCtrls = _controladoresParaGrid(atuais);
    });
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    for (final TextEditingController c in _rotuloCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    setState(() {
      _salvando = true;
      _erro = null;
    });
    final Map<String, String> rotulos = <String, String>{
      for (final MapEntry<int, TextEditingController> e in _rotuloCtrls.entries)
        if (e.value.text.trim().isNotEmpty) '${e.key}': e.value.text.trim(),
    };
    final DateTime agora = DateTime.now();
    final PelotaoDoc doc = PelotaoDoc(
      id: widget.pelotaoExistente?.id ?? widget.repo.novoId(),
      nome: _nomeCtrl.text.trim().isEmpty ? 'Pelotão sem nome' : _nomeCtrl.text.trim(),
      linhas: _linhas,
      colunas: _colunas,
      rotulos: rotulos,
      // `criadoEm` é ignorado pelo adaptador em updates (ver o comentário
      // em `RepositorioEvoFirestore.gravarPelotao`) — o valor aqui só
      // importa na criação, e mesmo aí o servidor decide via
      // `FieldValue.serverTimestamp()`, nunca este `DateTime` local.
      criadoEm: widget.pelotaoExistente?.criadoEm ?? agora,
      atualizadoEm: agora,
    );
    try {
      await widget.repo.gravarPelotao(doc);
      if (!mounted) return;
      // Regra de disciplina #3: não renderizamos aqui o que acabamos de
      // escrever — voltamos para a lista, que é quem escuta o stream e vai
      // mostrar o pelotão (novo ou atualizado) quando o servidor confirmar.
      Navigator.of(context).pop();
    } catch (erro) {
      if (!mounted) return;
      setState(() => _erro = mensagemFalha(erro));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _apagar() async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: Paleta.superficie,
        title: const Text('Apagar pelotão?', style: TextStyle(color: Paleta.claro)),
        content: const Text(
          'Isto apaga o pelotão e TODOS os rótulos dele — não dá para desfazer. '
          'Evoluções que usam este pelotão não são apagadas, mas ficam sem '
          'grid/rótulos associados.',
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
    try {
      await widget.repo.apagarPelotao(widget.pelotaoExistente!.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (erro) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mensagemFalha(erro))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Paleta.fundo,
      appBar: AppBar(
        title: Text(_editando ? 'Editar pelotão' : 'Novo pelotão'),
        actions: <Widget>[
          if (_editando)
            IconButton(
              tooltip: 'Apagar pelotão',
              icon: const Icon(Icons.delete_outline),
              onPressed: _apagar,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _nomeCtrl,
            style: const TextStyle(color: Paleta.claro),
            decoration: const InputDecoration(labelText: 'Nome do pelotão'),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: _SeletorTamanho(
                  rotulo: 'Linhas',
                  valor: _linhas,
                  onMudar: (int v) => _mudarTamanho(linhas: v),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _SeletorTamanho(
                  rotulo: 'Colunas',
                  valor: _colunas,
                  onMudar: (int v) => _mudarTamanho(colunas: v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Microcopy de compliance FIXO junto ao campo — nunca em tooltip,
          // nunca só na primeira vez: é a única barreira de fato (além do
          // teto de 24 caracteres, que a regra do servidor IMPÕE) contra
          // dado pessoal demais entrando aqui, e ela só funciona se for
          // vista no momento de digitar.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Paleta.superficie,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Paleta.cinzaEscuro),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.info_outline, color: Paleta.acento, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Use apelido ou primeiro nome. Não use nome completo, idade, '
                    'contato ou observações sobre a pessoa.',
                    style: TextStyle(color: Paleta.claro, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _linhas * _colunas,
            // Altura FIXA por célula (`mainAxisExtent`), não
            // `childAspectRatio`: com aspect ratio, a altura deriva da
            // largura disponível dividida por `_colunas` — num grid de
            // poucas colunas numa tela larga, cada célula vira um quadrado
            // gigante (centenas de px), empurrando "Salvar" para muito
            // além do viewport (o `RenderSliverList` só constrói filhos
            // dentro do cache extent — é a causa raiz de um teste de
            // widget não achar o botão sem nenhum erro de render). Altura
            // fixa mantém o grid inteiro num tamanho prático em qualquer
            // proporção de tela.
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _colunas,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 72,
            ),
            itemBuilder: (BuildContext context, int i) => _CampoRotulo(
              indice: i,
              controlador: _rotuloCtrls[i]!,
            ),
          ),
          const SizedBox(height: 24),
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
            onPressed: _salvando ? null : _salvar,
            child: _salvando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}

class _SeletorTamanho extends StatelessWidget {
  const _SeletorTamanho({
    required this.rotulo,
    required this.valor,
    required this.onMudar,
  });
  final String rotulo;
  final int valor;
  final ValueChanged<int> onMudar;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text('$rotulo: ', style: const TextStyle(color: Paleta.claro)),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: Paleta.cinzaMedio),
          onPressed: valor > 1 ? () => onMudar(valor - 1) : null,
        ),
        Text('$valor', style: const TextStyle(color: Paleta.claro, fontSize: 16)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, color: Paleta.cinzaMedio),
          onPressed: valor < maxLinhasOuColunas ? () => onMudar(valor + 1) : null,
        ),
      ],
    );
  }
}

class _CampoRotulo extends StatelessWidget {
  const _CampoRotulo({required this.indice, required this.controlador});
  final int indice;
  final TextEditingController controlador;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Paleta.superficie,
        border: Border.all(color: Paleta.cinzaEscuro),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            'Slot $indice',
            style: const TextStyle(color: Paleta.cinzaMedio, fontSize: 10),
          ),
          TextField(
            controller: controlador,
            maxLength: maxCaracteresRotulo,
            inputFormatters: <TextInputFormatter>[
              LengthLimitingTextInputFormatter(maxCaracteresRotulo),
            ],
            textAlign: TextAlign.center,
            style: const TextStyle(color: Paleta.claro, fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              counterStyle: TextStyle(color: Paleta.cinzaMedio, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}
