import 'dart:async';

import 'package:evo_motor/evo_motor.dart';
import 'package:flutter/foundation.dart';

import '../dados/controle_edicao.dart';
import '../dados/ordem_fracionaria.dart';
import '../dados/ordenacao_partes.dart';
import '../dados/repositorio_evo.dart';
import 'descritores_movimento.dart';

/// Profundidade máxima da pilha de undo em memória — nunca serializada (ver
/// dartdoc de classe do controlador). Escopo: uma evolução, zerada ao sair
/// da tela (o `ControladorEditorPartes` é recriado a cada abertura).
const int profundidadeMaximaUndo = 50;

/// Um passo de undo: o comando inverso é sempre "gravar de volta o
/// documento anterior" (inverso de gravar é gravar o anterior) ou "apagar
/// de novo com o mesmo id/ordem" (inverso de apagar é gravar com o mesmo id
/// e a mesma ordem) — nunca uma serialização com rótulo de operação, que
/// faria o dado sobreviver à própria exclusão fora da sessão.
class _PassoUndo {
  const _PassoUndo({required this.parteAnterior, this.eraExclusao = false});

  /// Documento completo de ANTES da ação — `gravarParte` deste valor de
  /// volta desfaz tanto uma edição de atribuições quanto uma exclusão
  /// (upsert, então recriar com o mesmo id/ordem funciona igual).
  final ParteDoc parteAnterior;

  /// `true` quando a ação desfeita foi uma exclusão de parte inteira (só
  /// para a mensagem de UI ficar precisa — o mecanismo de desfazer é o
  /// mesmo `gravarParte` nos dois casos).
  final bool eraExclusao;
}

/// Estado "em edição" do painel de atribuição para a seleção corrente — os
/// valores que os controles (chips de N, segmented de aoTerminar, switch de
/// bateRitmoAoJuntar, chips de percussão) mostram e ajustam. `null` em
/// [tipo] significa "nenhum movimento escolhido ainda nesta seleção" (painel
/// mostra só a lista para escolher).
@immutable
class EstadoPainelAtribuicao {
  const EstadoPainelAtribuicao({
    this.tipo,
    this.quantidade = 1,
    this.aoTerminar = AoTerminarMarche.marchando,
    this.bateRitmoAoJuntar = false,
    this.percussao,
  });

  final String? tipo;

  /// Vale para `tempos` (#1/#2/#3/#4) OU `n` (#5) — ver `CampoQuantidade`.
  final int quantidade;
  final AoTerminarMarche aoTerminar;
  final bool bateRitmoAoJuntar;
  final MembroPercussao? percussao;

  EstadoPainelAtribuicao copiarCom({
    String? tipo,
    int? quantidade,
    AoTerminarMarche? aoTerminar,
    bool? bateRitmoAoJuntar,
    MembroPercussao? percussao,
    bool limparPercussao = false,
  }) => EstadoPainelAtribuicao(
    tipo: tipo ?? this.tipo,
    quantidade: quantidade ?? this.quantidade,
    aoTerminar: aoTerminar ?? this.aoTerminar,
    bateRitmoAoJuntar: bateRitmoAoJuntar ?? this.bateRitmoAoJuntar,
    percussao: limparPercussao ? null : (percussao ?? this.percussao),
  );
}

/// O controlador da tela do editor de partes — dona de toda a lógica que
/// não é puramente visual: seleção, painel de atribuição ao vivo, undo em
/// memória, debounce de escrita, subgrupos salvos, trava de edição.
///
/// Alimentado de fora por [atualizarPelotao]/[atualizarEvolucao]/
/// [atualizarPartes]/[atualizarDono] — chamados pela tela sempre que os
/// streams do [RepositorioEvo]/[ControleDeEdicao] emitem um valor novo.
/// Isto é o único jeito de novos dados entrarem aqui: o controlador nunca
/// lê o repositório sozinho.
///
/// -----------------------------------------------------------------------
/// SOBRE O BUFFER LOCAL E A REGRA DE DISCIPLINA #3
/// -----------------------------------------------------------------------
/// A disciplina do repositório diz "a tela nunca renderiza o valor que ela
/// mesma escreveu — escreve e espera o stream trazer de volta". Esta tela é
/// uma exceção DELIBERADA e ESCOPADA a essa regra, pelo motivo que a
/// própria spec do `design` pede: "aplicação ao vivo, sem botão confirmar"
/// — escolher um movimento precisa aparecer no grid NO MESMO TOQUE, e o
/// debounce de escrita (~500ms-1s) tornaria isso visivelmente atrasado se a
/// tela esperasse o round-trip do Firestore a cada toque.
///
/// A solução: [_bufferAtribuicoes] é um buffer PRÉ-ESCRITA (nunca
/// pós-escrita) — existe só entre "o usuário tocou" e "o timer de debounce
/// disparou `gravarParte`". No instante em que a escrita é de fato
/// disparada, o buffer correspondente é limpo (ver [_agendarEscrita]) e a
/// tela volta a confiar inteiramente no stream — inclusive se o servidor
/// rejeitar a escrita ou (multi-editor futuro) outra sessão tiver
/// sobrescrito a parte nesse meio-tempo, o stream sempre vence assim que
/// chega. Isto nunca é "renderizar o que já foi escrito"; é "mostrar o que
/// está prestes a ser escrito", e a janela em que os dois podem divergir do
/// servidor é no máximo a janela do debounce.
class ControladorEditorPartes extends ChangeNotifier {
  ControladorEditorPartes({
    required this.repo,
    required this.evolucaoId,
    this.duracaoDebounce = const Duration(milliseconds: 700),
  });

  final RepositorioEvo repo;
  final String evolucaoId;
  final Duration duracaoDebounce;

  // ---- dados vindos dos streams (nunca escritos por nós) -------------------

  PelotaoDoc? _pelotao;
  EvolucaoDoc? _evolucao;
  List<ParteDoc> _partes = const <ParteDoc>[];
  DonoDaTrava _dono = DonoDaTrava.minha;

  PelotaoDoc? get pelotao => _pelotao;
  EvolucaoDoc? get evolucao => _evolucao;
  List<ParteDoc> get partes => _partes;
  bool get podeEditar => _dono == DonoDaTrava.minha;
  DonoDaTrava get dono => _dono;

  void atualizarPelotao(PelotaoDoc? p) {
    _pelotao = p;
    notifyListeners();
  }

  void atualizarEvolucao(EvolucaoDoc? e) {
    _evolucao = e;
    notifyListeners();
  }

  void atualizarPartes(List<ParteDoc> novasPartes) {
    _partes = novasPartes;
    // Se a parte selecionada sumiu (apagada por outra sessão, por exemplo),
    // recai na primeira disponível — nunca num índice fantasma.
    if (_indiceSelecionado != null && _indiceSelecionado! >= _partes.length) {
      _indiceSelecionado = _partes.isEmpty ? null : _partes.length - 1;
    }
    _indiceSelecionado ??= _partes.isNotEmpty ? 0 : null;
    notifyListeners();
  }

  void atualizarDono(DonoDaTrava d) {
    _dono = d;
    notifyListeners();
  }

  // ---- navegação de partes ---------------------------------------------

  int? _indiceSelecionado;
  int? get indiceSelecionado => _indiceSelecionado;

  ParteDoc? get parteSelecionada =>
      (_indiceSelecionado != null && _indiceSelecionado! < _partes.length)
      ? _partes[_indiceSelecionado!]
      : null;

  void selecionarParte(int indice) {
    if (indice < 0 || indice >= _partes.length) return;
    _indiceSelecionado = indice;
    _selecionados.clear();
    _painel = const EstadoPainelAtribuicao();
    notifyListeners();
  }

  // ---- geometria do grid (slot -> linha/coluna fixas, ver dartdoc do
  // motor: "slot é identidade, não localização") --------------------------

  int colunaDoSlot(int slot) => _pelotao == null ? 0 : slot % _pelotao!.colunas;
  int linhaDoSlot(int slot) => _pelotao == null ? 0 : slot ~/ _pelotao!.colunas;
  int slotDe(int linha, int coluna) => linha * (_pelotao?.colunas ?? 1) + coluna;

  // ---- cadência corrente por slot (para filtrar o painel) ----------------

  /// Cadência de cada slot ANTES da parte de índice [indiceParte] — dobra o
  /// `estadoInicial` através de todas as partes anteriores (continuação
  /// implícita = mantém a cadência; atribuição explícita = aplica
  /// `cadenciaResultante`). É a mesma semântica que o compilador usa, só que
  /// aqui só precisamos da CADÊNCIA (não posição), então isto é bem mais
  /// barato que rodar `simular`.
  Map<int, Cadencia> cadenciaAntesDaParte(int indiceParte) {
    final EvolucaoDoc? evo = _evolucao;
    if (evo == null) return const <int, Cadencia>{};
    final EstadoFormacao inicial = estadoFormacaoDoJson(evo.estadoInicial);
    final Map<int, Cadencia> atual = <int, Cadencia>{
      for (final int slot in inicial.slots) slot: inicial[slot].cad,
    };
    for (int i = 0; i < indiceParte && i < _partes.length; i++) {
      final Map<String, dynamic> atribuicoesCru = _partes[i].atribuicoes;
      for (final MapEntry<String, dynamic> e in atribuicoesCru.entries) {
        final int slot = int.parse(e.key);
        final Atribuicao a = atribuicaoDoJson(e.value as Map<String, dynamic>);
        final Cadencia entrada = atual[slot] ?? Cadencia.firme;
        atual[slot] = a.comando != null
            ? cadenciaResultanteDe(a.comando!, entrada)
            : a.movimento.cadenciaResultante(entrada);
      }
    }
    return atual;
  }

  Cadencia cadenciaAtualDoSlot(int slot) {
    final int? i = _indiceSelecionado;
    if (i == null) return Cadencia.firme;
    return cadenciaAntesDaParte(i)[slot] ?? Cadencia.firme;
  }

  // ---- estado de ENTRADA da parte selecionada (posição + direção reais,
  // não só cadência) — correção de 2026-09-15 ------------------------------
  //
  // Até esta correção o grid do editor desenhava todo mundo "para cima",
  // na célula fixa do slot — o instrutor montava uma parte sem ver pra
  // onde as pessoas estavam viradas nem onde elas estavam de verdade. O
  // motor já entrega isso de graça: `simular(estadoInicial,
  // partes[0..k-1])` produz o estado ao final da parte anterior, que É o
  // estado de entrada da parte `k` (caso trivial: `k == 0` não tem parte
  // anterior, o estado de entrada é o `estadoInicial` gravado da
  // evolução).
  //
  // Isto é DELIBERADAMENTE um cache separado de [cadenciaAntesDaParte]
  // (que continua existindo, inalterado, para o painel de atribuição): a
  // função antiga é uma réplica manual e barata só da CADÊNCIA, pensada
  // para ser chamada uma vez por slot a cada rebuild do painel/seleção;
  // este cache guarda o [EstadoFormacao] inteiro (posição+direção+
  // cadência) vindo do `simular` de verdade, e é uso mais pesado o
  // suficiente para precisar de cache explícito por índice de parte — ver
  // o aviso de custo abaixo.
  //
  // CUSTO: editar a parte K (escolher movimento, ajustar parâmetro, etc.)
  // NUNCA muda o estado de ENTRADA dela — só o de K+1 em diante. Por isso
  // este cache só é invalidado por MUDANÇA DE SELEÇÃO ou por uma mudança
  // real no conteúdo de alguma parte ANTERIOR ao índice selecionado
  // (outra sessão editou, undo, duplicar, renormalização de ordens) —
  // nunca a cada toque no painel da parte atual. A checagem de validade é
  // uma ASSINATURA barata (id + `atualizadoEm` de cada parte antes do
  // índice, mais o `atualizadoEm` da evolução) — nunca o conteúdo inteiro
  // das atribuições — então "reler a cada rebuild" é seguro: só quando a
  // assinatura muda é que `simular` roda de novo.
  int? _indiceCacheEntrada;
  List<String> _assinaturaCacheEntrada = const <String>[];
  EstadoFormacao? _estadoEntradaCache;
  List<Diagnostico> _diagnosticosEntradaCache = const <Diagnostico>[];

  List<String> _assinaturaEntrada(int indice) => <String>[
    if (_evolucao != null) 'evo@${_evolucao!.atualizadoEm.microsecondsSinceEpoch}',
    for (int i = 0; i < indice && i < _partes.length; i++)
      '${_partes[i].id}@${_partes[i].atualizadoEm.microsecondsSinceEpoch}',
  ];

  bool _assinaturasIguais(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _garantirCacheEntrada(int indice) {
    final List<String> assinatura = _assinaturaEntrada(indice);
    if (_indiceCacheEntrada == indice &&
        _assinaturasIguais(_assinaturaCacheEntrada, assinatura)) {
      return; // cache válido — nada para recomputar.
    }
    _indiceCacheEntrada = indice;
    _assinaturaCacheEntrada = assinatura;

    final EvolucaoDoc? evo = _evolucao;
    if (evo == null) {
      _estadoEntradaCache = null;
      _diagnosticosEntradaCache = const <Diagnostico>[];
      return;
    }
    final EstadoFormacao inicial = estadoFormacaoDoJson(evo.estadoInicial);
    if (indice <= 0) {
      // Primeira parte: sem parte anterior — o estado de entrada é o
      // `estadoInicial` gravado da evolução, tratado explicitamente (não
      // um caso degenerado de `simular` com lista vazia, embora desse na
      // mesma: fica claro na leitura que é intencional).
      _estadoEntradaCache = inicial;
      _diagnosticosEntradaCache = const <Diagnostico>[];
      return;
    }
    final List<Parte> anteriores = emOrdem(_partes.sublist(0, indice));
    final ResultadoSimulacao resultado = simular(inicial, anteriores);
    _estadoEntradaCache = resultado.estadoFinal(inicial);
    _diagnosticosEntradaCache = resultado.diagnosticos;
  }

  /// Estado de entrada (posição/direção/cadência REAIS, uma por slot) da
  /// parte selecionada — `null` só quando não há evolução carregada ou
  /// nenhuma parte selecionada. Nunca inventado/aproximado: é sempre o que
  /// `simular` produziu para o fim da parte anterior (ou `estadoInicial`
  /// para a primeira parte).
  EstadoFormacao? get estadoEntradaSelecionada {
    final int? i = _indiceSelecionado;
    if (i == null) return null;
    _garantirCacheEntrada(i);
    return _estadoEntradaCache;
  }

  /// Diagnósticos (comando impossível, colisão, fora dos limites) que a
  /// simulação até a parte ANTERIOR à selecionada já produziu. Não-vazio
  /// significa "o estado de entrada mostrado no grid parte de algo que o
  /// motor já considera problemático" — a tela mostra isto sempre, nunca
  /// esconde nem aborta (mesma disciplina das quatro checagens do motor:
  /// nunca abortam a simulação, só se acumulam para quem vê decidir).
  List<Diagnostico> get diagnosticosEntradaSelecionada {
    final int? i = _indiceSelecionado;
    if (i == null) return const <Diagnostico>[];
    _garantirCacheEntrada(i);
    return _diagnosticosEntradaCache;
  }

  /// Lê de [atribuicoesEfetivas] (buffer se houver, senão o doc do stream)
  /// — o mesmo motivo do dartdoc de classe: o quadrado de continuação
  /// precisa aparecer NO MESMO TOQUE que a atribuição é escolhida, não só
  /// depois que o debounce grava e o stream confirma. Achado durante a
  /// verificação por screenshot (2026-09-15): antes desta correção, o
  /// pontinho de percussão (que já lia do buffer) aparecia na hora, mas o
  /// quadrado de continuação só depois do round-trip — os dois indicadores
  /// precisam da MESMA fonte de leitura para não divergir visualmente
  /// entre si dentro da janela de debounce.
  bool recebeuAtribuicaoNestaParte(int slot) => atribuicoesEfetivas().containsKey('$slot');

  /// Atribuições EFETIVAS da parte selecionada — o buffer local se existir
  /// um pendente para ela, senão o documento vindo do stream. Ver o aviso
  /// grande no topo da classe.
  Map<String, dynamic> atribuicoesEfetivas() {
    final ParteDoc? p = parteSelecionada;
    if (p == null) return const <String, dynamic>{};
    if (_bufferParteId == p.id) return _bufferAtribuicoes;
    return p.atribuicoes;
  }

  // ---- seleção -----------------------------------------------------------

  final Set<int> _selecionados = <int>{};
  Set<int> get selecionados => Set<int>.unmodifiable(_selecionados);

  void alternarSlot(int slot) {
    if (_selecionados.contains(slot)) {
      _selecionados.remove(slot);
    } else {
      _selecionados.add(slot);
    }
    _resincronizarPainelComSelecao();
    notifyListeners();
  }

  void selecionarFileira(int linha) {
    final PelotaoDoc? p = _pelotao;
    if (p == null) return;
    _selecionados
      ..clear()
      ..addAll(<int>[for (int c = 0; c < p.colunas; c++) slotDe(linha, c)]);
    _resincronizarPainelComSelecao();
    notifyListeners();
  }

  void selecionarColuna(int coluna) {
    final PelotaoDoc? p = _pelotao;
    if (p == null) return;
    _selecionados
      ..clear()
      ..addAll(<int>[for (int l = 0; l < p.linhas; l++) slotDe(l, coluna)]);
    _resincronizarPainelComSelecao();
    notifyListeners();
  }

  void selecionarTodos() {
    final PelotaoDoc? p = _pelotao;
    if (p == null) return;
    _selecionados
      ..clear()
      ..addAll(List<int>.generate(p.totalSlots, (int i) => i));
    _resincronizarPainelComSelecao();
    notifyListeners();
  }

  void inverterSelecao() {
    final PelotaoDoc? p = _pelotao;
    if (p == null) return;
    final Set<int> todos = <int>{
      for (int i = 0; i < p.totalSlots; i++) i,
    };
    final Set<int> invertido = todos.difference(_selecionados);
    _selecionados
      ..clear()
      ..addAll(invertido);
    _resincronizarPainelComSelecao();
    notifyListeners();
  }

  void limparSelecao() {
    _selecionados.clear();
    _painel = const EstadoPainelAtribuicao();
    notifyListeners();
  }

  // ---- subgrupos salvos e nomeáveis (session-only — ver README da tela:
  // o schema de `partes` não tem campo para isto, então não persiste no
  // Firestore; cortado de propósito para caber na janela) ------------------

  final Map<String, Set<int>> _subgrupos = <String, Set<int>>{};
  Map<String, Set<int>> get subgrupos => Map<String, Set<int>>.unmodifiable(_subgrupos);

  void salvarSubgrupoAtual(String nome) {
    if (nome.trim().isEmpty || _selecionados.isEmpty) return;
    _subgrupos[nome.trim()] = Set<int>.of(_selecionados);
    notifyListeners();
  }

  void aplicarSubgrupo(String nome) {
    final Set<int>? s = _subgrupos[nome];
    if (s == null) return;
    _selecionados
      ..clear()
      ..addAll(s);
    _resincronizarPainelComSelecao();
    notifyListeners();
  }

  void apagarSubgrupo(String nome) {
    _subgrupos.remove(nome);
    notifyListeners();
  }

  // ---- cadência mista ------------------------------------------------------

  Set<Cadencia> get cadenciasNaSelecao =>
      _selecionados.map(cadenciaAtualDoSlot).toSet();

  bool get selecaoTemCadenciaMista => cadenciasNaSelecao.length > 1;

  /// "Dividir seleção por estado" em 1 toque: reduz a seleção ao maior
  /// subconjunto homogêneo de cadência presente agora. Repetir a ação (se a
  /// seleção ainda ficar mista — não fica, por construção de "maior
  /// subconjunto", mas o método é idempotente mesmo assim) não quebra nada.
  void dividirSelecaoPorEstado() {
    if (!selecaoTemCadenciaMista) return;
    final Map<Cadencia, int> contagem = <Cadencia, int>{};
    for (final int slot in _selecionados) {
      final Cadencia c = cadenciaAtualDoSlot(slot);
      contagem[c] = (contagem[c] ?? 0) + 1;
    }
    final Cadencia maior = contagem.entries
        .reduce((MapEntry<Cadencia, int> a, MapEntry<Cadencia, int> b) => b.value > a.value ? b : a)
        .key;
    _selecionados.removeWhere((int slot) => cadenciaAtualDoSlot(slot) != maior);
    _resincronizarPainelComSelecao();
    notifyListeners();
  }

  // ---- painel de atribuição ao vivo --------------------------------------

  EstadoPainelAtribuicao _painel = const EstadoPainelAtribuicao();
  EstadoPainelAtribuicao get painel => _painel;

  List<MovimentoValido> get movimentosValidos =>
      movimentosValidosParaConjunto(cadenciasNaSelecao);

  /// Quando a seleção muda, tenta herdar o `tipo`/parâmetros de uma
  /// atribuição já comum a todos os slots selecionados nesta parte (edição
  /// de um grupo já atribuído); senão, zera o painel para "nada escolhido".
  void _resincronizarPainelComSelecao() {
    if (_selecionados.isEmpty) {
      _painel = const EstadoPainelAtribuicao();
      return;
    }
    final Map<String, dynamic> atribs = atribuicoesEfetivas();
    ComandoDoCatalogo? comum;
    MembroPercussao? percussaoComum;
    bool primeiro = true;
    for (final int slot in _selecionados) {
      final dynamic bruto = atribs['$slot'];
      if (bruto == null) {
        comum = null;
        percussaoComum = null;
        break;
      }
      final Map<String, dynamic> json = bruto as Map<String, dynamic>;
      final ComandoDoCatalogo c = ComandoDoCatalogo.doJson(
        json['movimento'] as Map<String, dynamic>,
      );
      final Percussao? perc = percussaoDoJson(json['percussao'] as Map<String, dynamic>?);
      if (primeiro) {
        comum = c;
        percussaoComum = perc?.membro;
        primeiro = false;
      } else if (comum != c) {
        comum = null;
        percussaoComum = null;
        break;
      }
    }
    if (comum == null) {
      _painel = const EstadoPainelAtribuicao();
    } else {
      _painel = EstadoPainelAtribuicao(
        tipo: comum.tipo,
        quantidade: comum.n ?? comum.tempos,
        aoTerminar: comum.aoTerminar ?? AoTerminarMarche.marchando,
        bateRitmoAoJuntar: comum.bateRitmoAoJuntar,
        percussao: percussaoComum,
      );
    }
  }

  /// Percussão fica desabilitada quando a cadência de ENTRADA da seleção é
  /// `descansar` OU o movimento escolhido é `Descansar` — as duas formas de
  /// `compilador.dart` rejeitar percussão (entrada OU resultante
  /// `descansar`). A spec do `design` simplifica para "o movimento é
  /// Descansar"; a checagem de entrada é reforço de correção (evita propor
  /// uma combinação que o motor vai descartar silenciosamente com um
  /// diagnóstico).
  bool get percussaoDesabilitada {
    if (_painel.tipo == 'descansar') return true;
    return cadenciasNaSelecao.length == 1 &&
        cadenciasNaSelecao.single == Cadencia.descansar;
  }

  DescritorMovimento? get _descritorEmEdicao {
    if (_painel.tipo == null) return null;
    for (final DescritorMovimento d in descritoresCatalogo) {
      if (d.tipo == _painel.tipo) return d;
    }
    return null;
  }

  /// Escolhe um movimento para a seleção corrente — aplica NA HORA (sem
  /// botão confirmar). Reaproveita os parâmetros já em [painel] quando o
  /// tipo aceita (ex.: trocar de "Em frente, marche" com N=4 para outro
  /// movimento que tenha N preserva o preset, senão volta ao default).
  void escolherMovimento(String tipo) {
    if (!podeEditar || _selecionados.isEmpty) return;
    _painel = _painel.copiarCom(tipo: tipo, limparPercussao: percussaoSeraInvalidaPara(tipo));
    _aplicarPainelNaSelecao();
  }

  bool percussaoSeraInvalidaPara(String tipo) => tipo == 'descansar';

  void definirQuantidade(int quantidade) {
    if (!podeEditar || _painel.tipo == null) return;
    _painel = _painel.copiarCom(quantidade: quantidade);
    _aplicarPainelNaSelecao();
  }

  void definirAoTerminar(AoTerminarMarche aoTerminar) {
    if (!podeEditar || _painel.tipo == null) return;
    _painel = _painel.copiarCom(aoTerminar: aoTerminar);
    _aplicarPainelNaSelecao();
  }

  void definirBateRitmoAoJuntar(bool valor) {
    if (!podeEditar || _painel.tipo == null) return;
    _painel = _painel.copiarCom(bateRitmoAoJuntar: valor);
    _aplicarPainelNaSelecao();
  }

  /// `null` = "Nenhuma" — remove a percussão dos slots selecionados que já
  /// têm atribuição nesta parte.
  void definirPercussao(MembroPercussao? membro) {
    if (!podeEditar || percussaoDesabilitada) return;
    _painel = _painel.copiarCom(percussao: membro, limparPercussao: membro == null);
    _aplicarPercussaoNaSelecao(membro);
  }

  void _aplicarPainelNaSelecao() {
    final ParteDoc? parte = parteSelecionada;
    final String? tipo = _painel.tipo;
    if (parte == null || tipo == null || _selecionados.isEmpty) return;
    final DescritorMovimento? d = _descritorEmEdicao;
    final ComandoDoCatalogo comando = ComandoDoCatalogo(
      tipo: tipo,
      tempos: d?.campoQuantidade == CampoQuantidade.tempos ? _painel.quantidade : 1,
      n: d?.campoQuantidade == CampoQuantidade.n ? _painel.quantidade : null,
      aoTerminar: (d?.precisaAoTerminar ?? false) ? _painel.aoTerminar : null,
      bateRitmoAoJuntar: (d?.aceitaBateRitmoAoJuntar ?? false) ? _painel.bateRitmoAoJuntar : false,
    );
    final Percussao? percussao = _painel.percussao == null
        ? null
        : Percussao(membro: _painel.percussao!);
    _registrarUndo(parte);
    _iniciarBufferSeNecessario(parte);
    for (final int slot in _selecionados) {
      _bufferAtribuicoes['$slot'] = atribuicaoParaJson(
        Atribuicao(comando: comando, percussao: percussao),
      );
    }
    ultimoComandoAplicado = comando;
    ultimaPercussaoAplicada = percussao;
    notifyListeners();
    _agendarEscrita(parte);
  }

  void _aplicarPercussaoNaSelecao(MembroPercussao? membro) {
    final ParteDoc? parte = parteSelecionada;
    if (parte == null || _selecionados.isEmpty) return;
    final Map<String, dynamic> atuais = atribuicoesEfetivas();
    bool mudouAlgo = false;
    _iniciarBufferSeNecessario(parte);
    for (final int slot in _selecionados) {
      final dynamic bruto = atuais['$slot'];
      if (bruto == null) continue; // continuação implícita: nada para anexar percussão.
      final Map<String, dynamic> json = bruto as Map<String, dynamic>;
      final ComandoDoCatalogo comando = ComandoDoCatalogo.doJson(
        json['movimento'] as Map<String, dynamic>,
      );
      _bufferAtribuicoes['$slot'] = atribuicaoParaJson(
        Atribuicao(
          comando: comando,
          percussao: membro == null ? null : Percussao(membro: membro),
        ),
      );
      mudouAlgo = true;
    }
    if (!mudouAlgo) return;
    _registrarUndo(parte);
    notifyListeners();
    _agendarEscrita(parte);
  }

  // ---- último comando aplicado (reaplicar em 1 toque) ---------------------

  ComandoDoCatalogo? ultimoComandoAplicado;
  Percussao? ultimaPercussaoAplicada;

  bool get temUltimaAtribuicao => ultimoComandoAplicado != null;

  void reaplicarUltimaAtribuicao() {
    if (!podeEditar || ultimoComandoAplicado == null || _selecionados.isEmpty) return;
    final ParteDoc? parte = parteSelecionada;
    if (parte == null) return;
    final ComandoDoCatalogo comando = ultimoComandoAplicado!;
    _registrarUndo(parte);
    _iniciarBufferSeNecessario(parte);
    for (final int slot in _selecionados) {
      _bufferAtribuicoes['$slot'] = atribuicaoParaJson(
        Atribuicao(comando: comando, percussao: ultimaPercussaoAplicada),
      );
    }
    // O painel também reflete o que foi reaplicado — sem isto, os chips de
    // movimento/parâmetro ficam "mudos" depois de reaplicar (a silhueta no
    // grid já mostra o resultado certo via `atribuicoesEfetivas`, mas o
    // usuário perderia a confirmação visual de qual movimento é esse na
    // hora de, por exemplo, ajustar mais um parâmetro em seguida).
    _painel = EstadoPainelAtribuicao(
      tipo: comando.tipo,
      quantidade: comando.n ?? comando.tempos,
      aoTerminar: comando.aoTerminar ?? AoTerminarMarche.marchando,
      bateRitmoAoJuntar: comando.bateRitmoAoJuntar,
      percussao: ultimaPercussaoAplicada?.membro,
    );
    notifyListeners();
    _agendarEscrita(parte);
  }

  // ---- buffer + debounce ---------------------------------------------------

  String? _bufferParteId;
  Map<String, dynamic> _bufferAtribuicoes = <String, dynamic>{};
  Timer? _timerDebounce;

  void _iniciarBufferSeNecessario(ParteDoc parte) {
    if (_bufferParteId == parte.id) return;
    _bufferParteId = parte.id;
    _bufferAtribuicoes = Map<String, dynamic>.of(parte.atribuicoes);
  }

  /// Debounce de ~700ms (dentro da janela 500ms-1s pedida): cada toque no
  /// painel reagenda o mesmo timer em vez de escrever na hora — "ajustar a
  /// direção de cinco pessoas é uma escrita, não cinco" também vale para
  /// "ajustar N três vezes seguidas é uma escrita, não três".
  void _agendarEscrita(ParteDoc parteBase) {
    _timerDebounce?.cancel();
    _timerDebounce = Timer(duracaoDebounce, () async {
      final String? idBuffer = _bufferParteId;
      final Map<String, dynamic> atribuicoes = Map<String, dynamic>.of(_bufferAtribuicoes);
      _timerDebounce = null;
      _bufferParteId = null;
      if (idBuffer == null) return;
      try {
        await repo.gravarParte(parteBase.copiarCom(atribuicoes: atribuicoes));
      } catch (_) {
        // Erro de escrita já vira `ErroPersistencia` dentro do repo; a tela
        // mostra isso via um `Future` observável separado (ver
        // `erroDeEscrita`) — aqui só evitamos que uma exceção não tratada
        // suba de dentro de um `Timer`.
        _ultimoErroDeEscrita = _traduzirErro(idBuffer);
        notifyListeners();
      }
    });
  }

  Object? _ultimoErroDeEscrita;
  Object? get ultimoErroDeEscrita => _ultimoErroDeEscrita;
  void limparErroDeEscrita() {
    _ultimoErroDeEscrita = null;
  }

  Object _traduzirErro(String idParte) => StateError('Falha ao gravar parte $idParte');

  /// Força o flush do buffer pendente (chamado ao trocar de parte/sair da
  /// tela) — nunca deixa uma escrita "no ar" só porque o usuário navegou
  /// antes do debounce disparar.
  Future<void> flushPendente() async {
    if (_timerDebounce == null || _bufferParteId == null) return;
    _timerDebounce!.cancel();
    _timerDebounce = null;
    final String idBuffer = _bufferParteId!;
    final Map<String, dynamic> atribuicoes = Map<String, dynamic>.of(_bufferAtribuicoes);
    _bufferParteId = null;
    final ParteDoc? base = _partes.where((ParteDoc p) => p.id == idBuffer).firstOrNull;
    if (base == null) return;
    await repo.gravarParte(base.copiarCom(atribuicoes: atribuicoes));
  }

  // ---- undo em memória (profundidade ~50, nunca serializado) --------------

  final List<_PassoUndo> _pilhaUndo = <_PassoUndo>[];
  bool get temUndo => _pilhaUndo.isNotEmpty;

  /// `true` quando o PRÓXIMO `desfazer()` reverte uma exclusão de parte
  /// inteira (não uma edição de atribuições) — só para a tela escolher a
  /// mensagem certa; o mecanismo é sempre o mesmo `gravarParte`.
  bool get proximoUndoEExclusao => _pilhaUndo.isNotEmpty && _pilhaUndo.last.eraExclusao;

  void _registrarUndo(ParteDoc parteAntesDaMudanca, {bool eraExclusao = false}) {
    // Snapshot é sempre o valor JÁ EFETIVO (buffer se houver, senão o doc do
    // stream) — inverso de "gravar" é "gravar o que estava valendo antes
    // desta ação", não necessariamente o último doc confirmado pelo
    // servidor (podem existir várias ações dentro da mesma janela de
    // debounce, e cada uma precisa desfazer só a sua).
    final Map<String, dynamic> atribuicoesAntes = _bufferParteId == parteAntesDaMudanca.id
        ? Map<String, dynamic>.of(_bufferAtribuicoes)
        : Map<String, dynamic>.of(parteAntesDaMudanca.atribuicoes);
    _pilhaUndo.add(
      _PassoUndo(
        parteAnterior: parteAntesDaMudanca.copiarCom(atribuicoes: atribuicoesAntes),
        eraExclusao: eraExclusao,
      ),
    );
    if (_pilhaUndo.length > profundidadeMaximaUndo) {
      _pilhaUndo.removeAt(0);
    }
  }

  Future<void> desfazer() async {
    if (_pilhaUndo.isEmpty || !podeEditar) return;
    final _PassoUndo passo = _pilhaUndo.removeLast();
    // Desfazer grava direto (sem debounce, sem buffer): é uma ação
    // discreta e explícita do usuário, não uma sequência de micro-ajustes
    // que precise coalescer.
    _bufferParteId = null;
    _timerDebounce?.cancel();
    _timerDebounce = null;
    await repo.gravarParte(passo.parteAnterior);
    notifyListeners();
  }

  /// Chamado depois de [RepositorioEvo.renormalizarOrdens]: a pilha de undo
  /// referencia `ordem` antigas que deixaram de existir — mantê-la
  /// significaria "desfazer" reintroduzir uma ordem fracionária já
  /// invalidada. Zera com aviso (a tela mostra o aviso, não este método).
  void limparUndoPorRenormalizacao() {
    _pilhaUndo.clear();
    notifyListeners();
  }

  // ---- prévia ao vivo -------------------------------------------------------

  bool _modoPreview = false;
  bool get modoPreview => _modoPreview;

  void alternarPreview() {
    _modoPreview = !_modoPreview;
    notifyListeners();
  }

  // ---- ações de parte (nova / duplicar) ------------------------------------

  /// Nova parte pelo "+": nasce VAZIA (todo mundo em continuação implícita)
  /// — nunca copia a parte anterior. A tela mostra um toast confirmando.
  Future<ParteDoc> adicionarParteVazia() async {
    final double ordem = _partes.isEmpty
        ? primeiraOrdem()
        : ordemNoFim(_partes.last.ordem);
    final DateTime agora = DateTime.now();
    final ParteDoc nova = ParteDoc(
      id: repo.novoId(),
      evolucaoId: evolucaoId,
      ordem: ordem,
      atribuicoes: const <String, dynamic>{},
      atualizadoEm: agora,
    );
    await repo.gravarParte(nova);
    return nova;
  }

  /// Duplicar parte: copia `atribuicoes` (formato bruto, já serializável)
  /// da parte de índice [indice] para uma nova, inserida logo depois dela.
  /// Se o espaço fracionário entre as duas vizinhas estiver esgotado,
  /// renormaliza antes (avisando a pilha de undo via
  /// [limparUndoPorRenormalizacao] — a tela decide o texto do aviso).
  Future<ParteDoc> duplicarParte(int indice) async {
    if (indice < 0 || indice >= _partes.length) {
      throw ArgumentError('Índice de parte inválido para duplicar: $indice');
    }
    final ParteDoc origem = _partes[indice];
    double ordem;
    if (indice == _partes.length - 1) {
      ordem = ordemNoFim(origem.ordem);
    } else {
      final ParteDoc proxima = _partes[indice + 1];
      if (ordemEsgotada(origem.ordem, proxima.ordem)) {
        await repo.renormalizarOrdens(evolucaoId);
        limparUndoPorRenormalizacao();
        // Depois de renormalizar, a tela recebe as novas ordens pelo
        // stream (`atualizarPartes`) — aqui só usamos um valor seguro
        // provisório; o próximo snapshot corrige a posição exata se
        // necessário. `ordemNoFim` nunca esgota, então isto é seguro mesmo
        // como fallback.
        ordem = ordemNoFim(origem.ordem);
      } else {
        ordem = ordemNoMeio(origem.ordem, proxima.ordem);
      }
    }
    final DateTime agora = DateTime.now();
    final ParteDoc copia = ParteDoc(
      id: repo.novoId(),
      evolucaoId: evolucaoId,
      ordem: ordem,
      nome: origem.nome == null ? null : '${origem.nome} (cópia)',
      atribuicoes: Map<String, dynamic>.of(origem.atribuicoes),
      atualizadoEm: agora,
    );
    await repo.gravarParte(copia);
    return copia;
  }

  Future<void> apagarParteAtual() async {
    final ParteDoc? p = parteSelecionada;
    if (p == null || !podeEditar) return;
    _registrarUndo(p, eraExclusao: true);
    await repo.apagarParte(p.id);
  }

  @override
  void dispose() {
    _timerDebounce?.cancel();
    super.dispose();
  }
}

extension _PrimeiroOuNulo<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
