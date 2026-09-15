import 'package:evo_motor/evo_motor.dart';

/// Agrupamento FIXO do painel de atribuição — ver o handoff do `design`
/// (wireframe do editor de partes, 2026-09-14): "Sem deslocar / Deslocar /
/// Girar parado / Girar em marcha + Alto". A ordem desta enum é a ordem de
/// exibição das seções no painel.
enum GrupoMovimento {
  semDeslocar('Sem deslocar'),
  deslocar('Deslocar'),
  girarParado('Girar parado'),
  girarEmMarchaEAlto('Girar em marcha + Alto');

  const GrupoMovimento(this.rotulo);
  final String rotulo;
}

/// Qual campo bruto de `ComandoDoCatalogo` o preset de quantidade ("N", 1
/// toque, valores 1/2/4/8) escreve — os dois nomes de campo do catálogo
/// (`tempos` para #1/#2/#3/#4, `n` só para #5) são o MESMO conceito de UI
/// ("por quantos tempos"), então o painel mostra um único controle; só a
/// serialização difere.
enum CampoQuantidade { tempos, n }

/// Descreve UM dos 16 tipos do catálogo para fins de UI: nome humano, grupo
/// fixo de exibição, e quais parâmetros o painel precisa oferecer.
///
/// Deliberadamente NÃO reimplementa a tabela de precondição (`exigido`,
/// `permiteTeleporteDeMarchando`, etc.) — isso mora só em `Catalogo`/
/// `Movimento`, uma única vez. Este descritor cobre só o que a TELA precisa
/// saber para desenhar (rótulo, agrupamento, quais campos mostrar); a
/// validade de cada tipo para uma cadência dada é sempre perguntada de
/// verdade a `Movimento.checarPrecondicao` (ver [movimentosValidosPara]),
/// nunca decidida aqui.
class DescritorMovimento {
  const DescritorMovimento({
    required this.tipo,
    required this.nome,
    required this.grupo,
    this.campoQuantidade,
    this.precisaAoTerminar = false,
    this.aceitaBateRitmoAoJuntar = false,
  });

  /// Mesmo discriminador de `ComandoDoCatalogo.tipo`.
  final String tipo;
  final String nome;
  final GrupoMovimento grupo;

  /// `null` = este movimento não tem parâmetro de quantidade (os 5 giros
  /// parados/#11..#16 duram um número fixo de tempos, sem escolha).
  final CampoQuantidade? campoQuantidade;

  bool get precisaQuantidade => campoQuantidade != null;

  /// Só `emFrenteMarche` — segmented de 3 (`marchando`/`marcandoPasso`/`firme`).
  final bool precisaAoTerminar;

  /// Todo movimento que termina numa junção opcionalmente sonora — ver
  /// dartdoc de `ComandoDoCatalogo.bateRitmoAoJuntar`: #3, #5 e #6..#16.
  /// Fica de fora só #1 (Sentido), #2 (Descansar) e #4 (Bater o ritmo), que
  /// não juntam nada.
  final bool aceitaBateRitmoAoJuntar;

  /// Constrói um [ComandoDoCatalogo] "sonda" com parâmetros neutros — só
  /// para poder chamar `.materializar().checarPrecondicao(...)` e
  /// `.cadenciaResultante` sem duplicar a tabela de exigências aqui. Os
  /// valores de `n`/`tempos`/`aoTerminar` usados aqui NÃO importam para
  /// `checarPrecondicao` (que só depende de `exigido`/
  /// `permiteTeleporteDeMarchando`/`transicaoDeMarchandoModelada`,
  /// invariantes por parâmetro) — só precisam ser não-nulos para os tipos
  /// que os exigem, senão `materializar()` lança.
  ComandoDoCatalogo comandoSonda() => ComandoDoCatalogo(
    tipo: tipo,
    n: campoQuantidade == CampoQuantidade.n ? 1 : null,
    aoTerminar: precisaAoTerminar ? AoTerminarMarche.marchando : null,
  );
}

/// As 16 entradas do catálogo — nomes humanos e agrupamento fixo do
/// `design`. Fonte única desta lista: qualquer tela que precise "os 16
/// movimentos" itera isto, nunca reconstrói a lista à mão.
const List<DescritorMovimento> descritoresCatalogo = <DescritorMovimento>[
  // Sem deslocar (#1, #2, #3, #4).
  DescritorMovimento(
    tipo: 'sentido',
    nome: 'Sentido',
    grupo: GrupoMovimento.semDeslocar,
    campoQuantidade: CampoQuantidade.tempos,
  ),
  DescritorMovimento(
    tipo: 'descansar',
    nome: 'Descansar',
    grupo: GrupoMovimento.semDeslocar,
    campoQuantidade: CampoQuantidade.tempos,
  ),
  DescritorMovimento(
    tipo: 'marcarPasso',
    nome: 'Marcar passo',
    grupo: GrupoMovimento.semDeslocar,
    campoQuantidade: CampoQuantidade.tempos,
    aceitaBateRitmoAoJuntar: true,
  ),
  DescritorMovimento(
    tipo: 'baterORitmo',
    nome: 'Bater o ritmo',
    grupo: GrupoMovimento.semDeslocar,
    campoQuantidade: CampoQuantidade.tempos,
  ),
  // Deslocar (#5).
  DescritorMovimento(
    tipo: 'emFrenteMarche',
    nome: 'Em frente, marche',
    grupo: GrupoMovimento.deslocar,
    campoQuantidade: CampoQuantidade.n,
    precisaAoTerminar: true,
    aceitaBateRitmoAoJuntar: true,
  ),
  // Girar parado (#6..#10).
  DescritorMovimento(
    tipo: 'direitaVolverParado',
    nome: 'Direita volver',
    grupo: GrupoMovimento.girarParado,
    aceitaBateRitmoAoJuntar: true,
  ),
  DescritorMovimento(
    tipo: 'esquerdaVolverParado',
    nome: 'Esquerda volver',
    grupo: GrupoMovimento.girarParado,
    aceitaBateRitmoAoJuntar: true,
  ),
  DescritorMovimento(
    tipo: 'meiaVoltaParado',
    nome: 'Meia-volta',
    grupo: GrupoMovimento.girarParado,
    aceitaBateRitmoAoJuntar: true,
  ),
  DescritorMovimento(
    tipo: 'oitavaDireitaParado',
    nome: 'Oitava à direita',
    grupo: GrupoMovimento.girarParado,
    aceitaBateRitmoAoJuntar: true,
  ),
  DescritorMovimento(
    tipo: 'oitavaEsquerdaParado',
    nome: 'Oitava à esquerda',
    grupo: GrupoMovimento.girarParado,
    aceitaBateRitmoAoJuntar: true,
  ),
  // Girar em marcha + Alto (#11..#16).
  DescritorMovimento(
    tipo: 'alto',
    nome: 'Alto',
    grupo: GrupoMovimento.girarEmMarchaEAlto,
    aceitaBateRitmoAoJuntar: true,
  ),
  DescritorMovimento(
    tipo: 'direitaVolverMarcha',
    nome: 'Direita volver (marcha)',
    grupo: GrupoMovimento.girarEmMarchaEAlto,
    aceitaBateRitmoAoJuntar: true,
  ),
  DescritorMovimento(
    tipo: 'esquerdaVolverMarcha',
    nome: 'Esquerda volver (marcha)',
    grupo: GrupoMovimento.girarEmMarchaEAlto,
    aceitaBateRitmoAoJuntar: true,
  ),
  DescritorMovimento(
    tipo: 'meiaVoltaMarcha',
    nome: 'Meia-volta (marcha)',
    grupo: GrupoMovimento.girarEmMarchaEAlto,
    aceitaBateRitmoAoJuntar: true,
  ),
  DescritorMovimento(
    tipo: 'oitavaDireitaMarcha',
    nome: 'Oitava à direita (marcha)',
    grupo: GrupoMovimento.girarEmMarchaEAlto,
    aceitaBateRitmoAoJuntar: true,
  ),
  DescritorMovimento(
    tipo: 'oitavaEsquerdaMarcha',
    nome: 'Oitava à esquerda (marcha)',
    grupo: GrupoMovimento.girarEmMarchaEAlto,
    aceitaBateRitmoAoJuntar: true,
  ),
];

/// Resultado de checar um [DescritorMovimento] contra uma cadência —
/// carrega o aviso de teleporte de `ResultadoPrecondicao` adiante, para a
/// tela decidir se mostra o aviso "parada teleportada" (nunca bloqueia).
class MovimentoValido {
  const MovimentoValido({required this.descritor, required this.avisoTeleporte});
  final DescritorMovimento descritor;
  final bool avisoTeleporte;
}

/// Filtra os 16 movimentos do catálogo pela cadência de entrada — ESTA é a
/// função que o painel de atribuição chama, e ela delega inteiramente a
/// `Movimento.checarPrecondicao` (a mesma checagem que o motor usa para
/// diagnosticar "comando impossível" no compilador). Nunca reimplementa a
/// tabela `exigido`/`permiteTeleporteDeMarchando` — só pergunta.
List<MovimentoValido> movimentosValidosPara(Cadencia cadenciaEntrada) {
  final List<MovimentoValido> validos = <MovimentoValido>[];
  for (final DescritorMovimento d in descritoresCatalogo) {
    final ResultadoPrecondicao r = d
        .comandoSonda()
        .materializar()
        .checarPrecondicao(cadenciaEntrada);
    if (r.ok) {
      validos.add(MovimentoValido(descritor: d, avisoTeleporte: r.avisoTeleporte));
    }
  }
  return validos;
}

/// Interseção dos movimentos válidos para TODAS as cadências em
/// [cadenciasEntrada] — usada quando a seleção corrente é mista (mais de um
/// estado de cadência entre os slots selecionados): só oferece um
/// movimento se ele for seguro para qualquer um dos estados presentes,
/// nunca um que o motor recusaria para uma parte da seleção.
List<MovimentoValido> movimentosValidosParaConjunto(Set<Cadencia> cadenciasEntrada) {
  if (cadenciasEntrada.isEmpty) return const <MovimentoValido>[];
  if (cadenciasEntrada.length == 1) {
    return movimentosValidosPara(cadenciasEntrada.single);
  }
  final Iterator<Cadencia> it = cadenciasEntrada.iterator..moveNext();
  Set<String> tiposValidos = movimentosValidosPara(
    it.current,
  ).map((MovimentoValido m) => m.descritor.tipo).toSet();
  while (it.moveNext()) {
    final Set<String> destaCadencia = movimentosValidosPara(
      it.current,
    ).map((MovimentoValido m) => m.descritor.tipo).toSet();
    tiposValidos = tiposValidos.intersection(destaCadencia);
  }
  // Aviso de teleporte não faz sentido bem definido para um conjunto misto
  // (cadências de entrada diferentes produziriam avisos diferentes) — como
  // a lista de interseção só existe enquanto a seleção estiver mista (a
  // tela oferece "dividir seleção por estado" para sair desse caso), nunca
  // mostramos o aviso aqui: `false` é seguro (o pior caso é o aviso não
  // aparecer numa tela que já está sinalizando "cadência mista" de outra
  // forma).
  return <MovimentoValido>[
    for (final DescritorMovimento d in descritoresCatalogo)
      if (tiposValidos.contains(d.tipo))
        MovimentoValido(descritor: d, avisoTeleporte: false),
  ];
}

/// A cadência resultante de aplicar [comando] a partir de [entrada] — usada
/// para: (a) decidir se a percussão deve ficar desabilitada (ver
/// `compilador.dart`: rejeitada quando entrada OU resultante é
/// `descansar`), (b) propagar a cadência corrente ao computar o estado
/// "antes desta parte" das partes seguintes.
Cadencia cadenciaResultanteDe(ComandoDoCatalogo comando, Cadencia entrada) =>
    comando.materializar().cadenciaResultante(entrada);
