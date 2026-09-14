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
import '../catalogo.dart';
import '../estado.dart';
import '../geometria.dart';
import '../movimento.dart';
import '../parte.dart';
import '../percussao.dart';
import '../preenchimento.dart';
import '../simulador.dart';

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

Movimento movimentoDoJson(Map<String, dynamic> json) {
  final String tipo = json['tipo'] as String;
  final bool bate = json['bateRitmoAoJuntar'] as bool? ?? false;
  final int tempos = json['tempos'] as int? ?? 1;
  switch (tipo) {
    case 'sentido':
      return Catalogo.sentido(tempos: tempos);
    case 'descansar':
      return Catalogo.descansar(tempos: tempos);
    case 'marcarPasso':
      return Catalogo.marcarPasso(tempos: tempos, bateRitmoAoJuntar: bate);
    case 'baterORitmo':
      return Catalogo.baterORitmo(tempos: tempos);
    case 'emFrenteMarche':
      final int n = json['n'] as int;
      final AoTerminarMarche aoTerminar = switch (json['aoTerminar']
          as String) {
        'marchando' => AoTerminarMarche.marchando,
        'marcandoPasso' => AoTerminarMarche.marcandoPasso,
        'firme' => AoTerminarMarche.firme,
        final String outro => throw FormatException(
          'aoTerminar desconhecido: "$outro"',
        ),
      };
      return Catalogo.emFrenteMarche(
        n,
        aoTerminar: aoTerminar,
        bateRitmoAoJuntar: bate,
      );
    case 'direitaVolverParado':
      return Catalogo.direitaVolverParado(bateRitmoAoJuntar: bate);
    case 'esquerdaVolverParado':
      return Catalogo.esquerdaVolverParado(bateRitmoAoJuntar: bate);
    case 'meiaVoltaParado':
      return Catalogo.meiaVoltaParado(bateRitmoAoJuntar: bate);
    case 'oitavaDireitaParado':
      return Catalogo.oitavaDireitaParado(bateRitmoAoJuntar: bate);
    case 'oitavaEsquerdaParado':
      return Catalogo.oitavaEsquerdaParado(bateRitmoAoJuntar: bate);
    case 'alto':
      return Catalogo.alto(bateRitmoAoJuntar: bate);
    case 'direitaVolverMarcha':
      return Catalogo.direitaVolverMarcha(bateRitmoAoJuntar: bate);
    case 'esquerdaVolverMarcha':
      return Catalogo.esquerdaVolverMarcha(bateRitmoAoJuntar: bate);
    case 'meiaVoltaMarcha':
      return Catalogo.meiaVoltaMarcha(bateRitmoAoJuntar: bate);
    case 'oitavaDireitaMarcha':
      return Catalogo.oitavaDireitaMarcha(bateRitmoAoJuntar: bate);
    case 'oitavaEsquerdaMarcha':
      return Catalogo.oitavaEsquerdaMarcha(bateRitmoAoJuntar: bate);
    default:
      throw FormatException('Movimento desconhecido no catálogo: "$tipo"');
  }
}

Preenchimento? preenchimentoDoJson(Map<String, dynamic>? json) {
  if (json == null) return null;
  return Preenchimento.paraCadencia(cadenciaDoJson(json['cadencia'] as String));
}

MembroPercussao membroPercussaoDoJson(String valor) => switch (valor) {
  'mao' => MembroPercussao.mao,
  'pernaEsquerda' => MembroPercussao.pernaEsquerda,
  'pernaDireita' => MembroPercussao.pernaDireita,
  _ => throw FormatException('Membro de percussão desconhecido no JSON: "$valor"'),
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

Atribuicao atribuicaoDoJson(Map<String, dynamic> json) => Atribuicao(
  movimento: movimentoDoJson(json['movimento'] as Map<String, dynamic>),
  offsetInicialTiques: json['offsetInicialTiques'] as int? ?? 0,
  preenchimento: preenchimentoDoJson(
    json['preenchimento'] as Map<String, dynamic>?,
  ),
  percussao: percussaoDoJson(json['percussao'] as Map<String, dynamic>?),
);

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
