/// (De)serialização JSON — a fronteira que a regra de `unidadesPorCelula`
/// nunca pode atravessar. Tudo aqui fala em CÉLULAS (`linha`, `coluna`),
/// setor 0..7 e cadência; quartos-de-célula nunca aparecem num campo JSON.
///
/// `Posicao.celulaExata()` (chamado por [estadoPessoaParaJson]) LANÇA se a
/// posição não cair numa fronteira de célula inteira — na prática, isso
/// significa que só o estado inicial/final gravado de uma evolução pode
/// ser serializado; um estado intermediário de uma diagonal em andamento
/// não tem `{linha, coluna}` inteiros para oferecer, e é exatamente isso
/// que deve estourar em vez de silenciosamente arredondar.
library;

import '../cadencia.dart';
import '../estado.dart';
import '../geometria.dart';
import '../movimento.dart';
import '../parte.dart';
import '../percussao.dart';
import '../preenchimento.dart';
import '../simulador.dart';
import 'comando_do_catalogo.dart';

Cadencia cadenciaDoJson(String valor) => switch (valor) {
  'firme' => Cadencia.firme,
  'descansar' => Cadencia.descansar,
  'marcandoPasso' => Cadencia.marcandoPasso,
  'marchando' => Cadencia.marchando,
  _ => throw FormatException('Cadência desconhecida no JSON: "$valor"'),
};

String cadenciaParaJson(Cadencia cadencia) => switch (cadencia) {
  Cadencia.firme => 'firme',
  Cadencia.descansar => 'descansar',
  Cadencia.marcandoPasso => 'marcandoPasso',
  Cadencia.marchando => 'marchando',
};

EstadoPessoa estadoPessoaDoJson(Map<String, dynamic> json) {
  final Posicao posicao = Posicao.celula(
    json['linha'] as int,
    json['coluna'] as int,
  );
  final int setor = json['setor'] as int;
  if (setor < 0 || setor > 7) {
    throw FormatException(
      'Setor fora do intervalo 0..7 no JSON: $setor. Setor é o facing '
      '(0=Norte, horário) e nunca é normalizado na leitura — um JSON '
      'malformado tem que estourar aqui, não virar silenciosamente um '
      'setor "enrolado" via módulo.',
    );
  }
  return EstadoPessoa(
    x: posicao.xQuartos,
    y: posicao.yQuartos,
    dir: setor,
    cad: cadenciaDoJson(json['cadencia'] as String),
  );
}

/// Serializa um [EstadoPessoa] para JSON. Lança [StateError] (propagado de
/// [Posicao.celulaExata]) se a posição não estiver alinhada a uma célula —
/// isso é o "teste que falha se alguém serializar quartos" pedido na spec,
/// aplicado como um invariante de runtime, não só como um teste isolado.
Map<String, dynamic> estadoPessoaParaJson(EstadoPessoa estado) {
  final (int linha, int coluna) = estado.posicao.celulaExata();
  return <String, dynamic>{
    'linha': linha,
    'coluna': coluna,
    'setor': estado.dir,
    'cadencia': cadenciaParaJson(estado.cad),
  };
}

EstadoFormacao estadoFormacaoDoJson(Map<String, dynamic> json) {
  final Map<String, dynamic> slots = json['slots'] as Map<String, dynamic>;
  return EstadoFormacao(<int, EstadoPessoa>{
    for (final MapEntry<String, dynamic> entrada in slots.entries)
      int.parse(entrada.key): estadoPessoaDoJson(
        entrada.value as Map<String, dynamic>,
      ),
  });
}

Map<String, dynamic> estadoFormacaoParaJson(EstadoFormacao formacao) =>
    <String, dynamic>{
      'slots': <String, dynamic>{
        for (final int slot in formacao.slots)
          '$slot': estadoPessoaParaJson(formacao[slot]),
      },
    };

/// Lê um [Movimento] compilado direto do JSON de `movimento`. Desde a
/// correção do buraco de round-trip, isto é só açúcar sobre o par
/// `ComandoDoCatalogo.doJson` + `materializar` — mantido porque é
/// conveniente quando só se quer RODAR o movimento (ex.: testes), sem
/// precisar guardar o comando para depois serializar de volta. Quem
/// precisa do round-trip completo (o caminho real de `atribuicaoDoJson`)
/// usa `ComandoDoCatalogo.doJson` diretamente, para reter o comando-fonte
/// dentro da `Atribuicao` — ver `atribuicaoDoJson` e o dartdoc de
/// `Atribuicao`.
Movimento movimentoDoJson(Map<String, dynamic> json) =>
    ComandoDoCatalogo.doJson(json).materializar();

/// Serializa um [ComandoDoCatalogo] para JSON — a metade de escrita que
/// faltava (ver dartdoc de `ComandoDoCatalogo`, que faz toda a decisão de
/// formato). Nome no plural de funções `xParaJson` deste arquivo por
/// simetria com `cadenciaParaJson`/`estadoPessoaParaJson`, embora a lógica
/// em si viva no método `ComandoDoCatalogo.paraJson`.
Map<String, dynamic> comandoParaJson(ComandoDoCatalogo comando) =>
    comando.paraJson();

Preenchimento? preenchimentoDoJson(Map<String, dynamic>? json) {
  if (json == null) return null;
  return Preenchimento.paraCadencia(cadenciaDoJson(json['cadencia'] as String));
}

/// Serializa um [Preenchimento]. Round-trippa sem trabalho: todo
/// `Preenchimento` é só uma cadência (`Preenchimento.paraCadencia` é a
/// única forma de construir um), então basta guardar essa cadência —
/// simétrico a [preenchimentoDoJson].
Map<String, dynamic> preenchimentoParaJson(Preenchimento preenchimento) =>
    <String, dynamic>{'cadencia': cadenciaParaJson(preenchimento.cadencia)};

MembroPercussao membroPercussaoDoJson(String valor) => switch (valor) {
  'mao' => MembroPercussao.mao,
  'pernaEsquerda' => MembroPercussao.pernaEsquerda,
  'pernaDireita' => MembroPercussao.pernaDireita,
  _ => throw FormatException('Membro de percussão desconhecido no JSON: "$valor"'),
};

String membroPercussaoParaJson(MembroPercussao membro) => switch (membro) {
  MembroPercussao.mao => 'mao',
  MembroPercussao.pernaEsquerda => 'pernaEsquerda',
  MembroPercussao.pernaDireita => 'pernaDireita',
};

/// `percussao` é opcional em `atribuicao`; ausente ⇒ `null` ⇒ nenhum
/// evento (JSON já gravado sem o campo lê idêntico a antes). `membro`
/// desconhecido lança — nunca cai num membro default silencioso, no
/// mesmo estilo de `cadenciaDoJson`.
///
/// Reservado no schema (não implementado ainda): `aCadaTempos` e
/// `faseTempos`, para densidade de percussão diferente de "toda vez".
/// Ausentes hoje equivaleriam a `1`/`0` (uma batida por tempo, sem
/// deslocamento de fase) — que é a única densidade que o motor de fato
/// produz agora (ver a nota de densidade em `compilador.dart`).
Percussao? percussaoDoJson(Map<String, dynamic>? json) {
  if (json == null) return null;
  return Percussao(membro: membroPercussaoDoJson(json['membro'] as String));
}

/// Serializa uma [Percussao] — round-trippa sem trabalho, só `membro`.
Map<String, dynamic> percussaoParaJson(Percussao percussao) =>
    <String, dynamic>{'membro': membroPercussaoParaJson(percussao.membro)};

/// Lê uma [Atribuicao] do JSON. Sempre constrói com `comando` (nunca com
/// `movimento` direto) — é essa escolha, e só ela, que faz
/// `atribuicaoParaJson(atribuicaoDoJson(json))` fechar o round-trip: ver o
/// dartdoc do construtor de [Atribuicao].
Atribuicao atribuicaoDoJson(Map<String, dynamic> json) => Atribuicao(
  comando: ComandoDoCatalogo.doJson(json['movimento'] as Map<String, dynamic>),
  offsetInicialTiques: json['offsetInicialTiques'] as int? ?? 0,
  preenchimento: preenchimentoDoJson(
    json['preenchimento'] as Map<String, dynamic>?,
  ),
  percussao: percussaoDoJson(json['percussao'] as Map<String, dynamic>?),
);

/// Serializa uma [Atribuicao] para JSON. Só funciona para atribuições
/// construídas com `comando` — as construídas com `movimento` compilado
/// direto (o atalho que ~40 testes do motor usam para simular sem passar
/// por JSON) não têm de onde tirar tipo e parâmetros, e isto lança
/// [StateError] em vez de produzir um JSON incompleto ou inventado.
Map<String, dynamic> atribuicaoParaJson(Atribuicao atribuicao) {
  final ComandoDoCatalogo? comando = atribuicao.comando;
  if (comando == null) {
    throw StateError(
      'Atribuicao sem `comando` não pode virar JSON — foi construída com '
      '`movimento` compilado direto (atalho interno de simulação/testes, '
      'ver dartdoc de Atribuicao). Quem monta a partir do editor ou do '
      'banco deve sempre fornecer `comando`.',
    );
  }
  return <String, dynamic>{
    'movimento': comandoParaJson(comando),
    if (atribuicao.offsetInicialTiques != 0)
      'offsetInicialTiques': atribuicao.offsetInicialTiques,
    if (atribuicao.preenchimento != null)
      'preenchimento': preenchimentoParaJson(atribuicao.preenchimento!),
    if (atribuicao.percussao != null)
      'percussao': percussaoParaJson(atribuicao.percussao!),
  };
}

Parte parteDoJson(Map<String, dynamic> json) {
  final Map<String, dynamic> atribuicoes =
      json['atribuicoes'] as Map<String, dynamic>;
  return Parte(
    ordem: (json['ordem'] as num).toDouble(),
    nome: json['nome'] as String?,
    atribuicoes: <int, Atribuicao>{
      for (final MapEntry<String, dynamic> entrada in atribuicoes.entries)
        int.parse(entrada.key): atribuicaoDoJson(
          entrada.value as Map<String, dynamic>,
        ),
    },
  );
}

Map<String, dynamic> parteParaJson(Parte parte) => <String, dynamic>{
  'ordem': parte.ordem,
  if (parte.nome != null) 'nome': parte.nome,
  'atribuicoes': <String, dynamic>{
    for (final MapEntry<int, Atribuicao> entrada in parte.atribuicoes.entries)
      '${entrada.key}': atribuicaoParaJson(entrada.value),
  },
};

Evolucao evolucaoDoJson(Map<String, dynamic> json) => Evolucao(
  nome: json['nome'] as String,
  estadoInicial: estadoFormacaoDoJson(
    json['estadoInicial'] as Map<String, dynamic>,
  ),
  partes: <Parte>[
    for (final dynamic parte in json['partes'] as List<dynamic>)
      parteDoJson(parte as Map<String, dynamic>),
  ],
);

Map<String, dynamic> evolucaoParaJson(Evolucao evolucao) => <String, dynamic>{
  'nome': evolucao.nome,
  'estadoInicial': estadoFormacaoParaJson(evolucao.estadoInicial),
  'partes': <dynamic>[
    for (final Parte parte in evolucao.partes) parteParaJson(parte),
  ],
};
