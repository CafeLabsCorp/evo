import 'cadencia.dart';
import 'movimento.dart';
import 'segmento.dart';

/// Catálogo congelado de movimentos de ordem unida. Cada função devolve um
/// [Movimento] já resolvido em segmentos concretos — a numeração dos
/// comentários (#1..#16) corresponde à tabela da spec.
///
/// Regra uniforme: `Giro` nunca consome tempo; todo tempo vem de `Avanco`
/// (diretamente) ou marcado por `Pausa`/`Juncao`. Nenhum movimento desloca
/// na direção NOVA — giros em marcha sempre deslocam 1 célula na direção
/// ANTIGA (o `Avanco(1)` vem sempre antes do `Giro`).
///
/// Versão do catálogo: incrementa a cada correção que muda o resultado de
/// evoluções já gravadas (nunca por refactor puro). Serializada nos
/// goldens (`test/golden/*.golden.json`, campo `versaoCatalogo`) para
/// distinguir "correção legítima de catálogo" (muitos goldens mudam, todos
/// com a versão nova) de "regressão" (um golden muda, mesma versão) — ver
/// `test/golden/regenerar.dart`.
///
/// - v1: catálogo original (nunca versionado explicitamente em código —
///   esta constante não existia ainda).
/// - v2: corrige "Marcar passo" (#3) a partir de `marchando` — antes virava
///   direto `P(N)` sem custar o passo de transição; agora é `A(1)·J·P(N)`,
///   simétrico ao "Alto!". Consequência: `emFrenteMarche(N, aoTerminar:
///   marcandoPasso)` também passa a ser `A(N)·J` (N+1 tempos), em vez de
///   `A(N)` sem junção.
const int versaoCatalogo = 2;

abstract final class Catalogo {
  /// #1 — Sentido / firme.
  static Movimento sentido({int tempos = 1}) => Movimento(
    nome: 'Sentido',
    exigido: null, // qualquer¹
    permiteTeleporteDeMarchando: true,
    segmentos: (_) => <Segmento>[Pausa(tempos)],
    cadenciaResultante: (_) => Cadencia.firme,
  );

  /// #2 — Descansar.
  static Movimento descansar({int tempos = 1}) => Movimento(
    nome: 'Descansar',
    exigido: const <Cadencia>{Cadencia.firme, Cadencia.marcandoPasso},
    permiteTeleporteDeMarchando: true, // ¹
    segmentos: (_) => <Segmento>[Pausa(tempos)],
    cadenciaResultante: (_) => Cadencia.descansar,
  );

  /// #3 — Marcar passo.
  ///
  /// Mecânica real: quem já está marchando não passa a marcar passo
  /// instantaneamente. O comando cai no pé esquerdo, dá-se mais 1 passo
  /// com o pé direito (desloca +1 célula na direção atual) e, em vez do
  /// próximo passo ser com o esquerdo, ele junta no lugar do direito — já
  /// marcando passo dali. Estrutura idêntica à do "Alto!" (`A(1)·J`),
  /// mudando só a cadência final (`marcandoPasso` em vez de `firme`).
  ///
  /// - De `firme`/`descansar`/`marcandoPasso` (já parado): `P(N)`, N
  ///   tempos, 0 deslocamento — como antes da correção de catálogo v2.
  /// - De `marchando`: `A(1)·J` de transição (2 tempos, +1 célula na
  ///   direção atual), depois `P(N)` marcando passo no lugar. Total N+2
  ///   tempos, deslocamento 1 célula.
  ///
  /// `bateRitmoAoJuntar` só tem efeito quando a transição de `marchando`
  /// de fato acontece (é a flag inerte da `Juncao` dessa transição, igual
  /// aos movimentos 6-16).
  static Movimento marcarPasso({
    int tempos = 1,
    bool bateRitmoAoJuntar = false,
  }) => Movimento(
    nome: 'Marcar passo',
    exigido: null, // qualquer — a transição de marchando é modelada de verdade
    transicaoDeMarchandoModelada: true,
    segmentos: (Cadencia entrada) => <Segmento>[
      if (entrada == Cadencia.marchando) ...<Segmento>[
        const Avanco(1),
        Juncao(bateRitmoAoJuntar: bateRitmoAoJuntar),
      ],
      Pausa(tempos, bateRitmo: true),
    ],
    cadenciaResultante: (_) => Cadencia.marcandoPasso,
  );

  /// #4 — Bater o ritmo. Mantém a cadência de entrada (só é válida vindo
  /// de firme ou marcandoPasso).
  static Movimento baterORitmo({int tempos = 1}) => Movimento(
    nome: 'Bater o ritmo',
    exigido: const <Cadencia>{Cadencia.firme, Cadencia.marcandoPasso},
    segmentos: (_) => <Segmento>[Pausa(tempos, bateRitmo: true)],
    cadenciaResultante: (Cadencia entrada) => entrada,
  );

  /// #5 — Em frente, marche.
  ///
  /// - `aoTerminar: marchando` — `A(N)`, N tempos, sem junção.
  /// - `aoTerminar: marcandoPasso` — `A(N)·J`, N+1 tempos, deslocamento N
  ///   (a junção não anda). Simétrico a `aoTerminar: firme`: terminar uma
  ///   marcha marcando passo custa o mesmo passo de transição que "Marcar
  ///   passo" (#3) cobra a partir de `marchando` — ver catálogo v2.
  /// - `aoTerminar: firme` — `A(N)·J`, N+1 tempos, deslocamento continua
  ///   sendo N (a junção não anda).
  static Movimento emFrenteMarche(
    int n, {
    required AoTerminarMarche aoTerminar,
    bool bateRitmoAoJuntar = false,
  }) {
    assert(n >= 1);
    final Cadencia final_ = switch (aoTerminar) {
      AoTerminarMarche.marchando => Cadencia.marchando,
      AoTerminarMarche.marcandoPasso => Cadencia.marcandoPasso,
      AoTerminarMarche.firme => Cadencia.firme,
    };
    final List<Segmento> segmentos = <Segmento>[
      Avanco(n),
      if (aoTerminar == AoTerminarMarche.firme ||
          aoTerminar == AoTerminarMarche.marcandoPasso)
        Juncao(bateRitmoAoJuntar: bateRitmoAoJuntar),
    ];
    return Movimento(
      nome: 'Em frente, marche ($aoTerminar)',
      exigido: const <Cadencia>{
        Cadencia.firme,
        Cadencia.marcandoPasso,
        Cadencia.marchando,
      },
      segmentos: (_) => segmentos,
      cadenciaResultante: (_) => final_,
    );
  }

  /// #6 — Direita volver (parado). Pivô (1 tempo) + junção (1 tempo).
  static Movimento direitaVolverParado({bool bateRitmoAoJuntar = false}) =>
      _volverParado(
        nome: 'Direita volver',
        deltaSetor: 2,
        bateRitmoAoJuntar: bateRitmoAoJuntar,
      );

  /// #7 — Esquerda volver (parado).
  static Movimento esquerdaVolverParado({bool bateRitmoAoJuntar = false}) =>
      _volverParado(
        nome: 'Esquerda volver',
        deltaSetor: -2,
        bateRitmoAoJuntar: bateRitmoAoJuntar,
      );

  /// #8 — Meia-volta (parado). `-4` = meia-volta pela esquerda; `-4 ≡ +4
  /// (mod 8)` no estado, o sinal só orienta a janela de rotação pro render.
  static Movimento meiaVoltaParado({bool bateRitmoAoJuntar = false}) =>
      _volverParado(
        nome: 'Meia-volta',
        deltaSetor: -4,
        bateRitmoAoJuntar: bateRitmoAoJuntar,
      );

  /// #9 — Oitava à direita (parado).
  static Movimento oitavaDireitaParado({bool bateRitmoAoJuntar = false}) =>
      _volverParado(
        nome: 'Oitava à direita',
        deltaSetor: 1,
        bateRitmoAoJuntar: bateRitmoAoJuntar,
      );

  /// #10 — Oitava à esquerda (parado).
  static Movimento oitavaEsquerdaParado({bool bateRitmoAoJuntar = false}) =>
      _volverParado(
        nome: 'Oitava à esquerda',
        deltaSetor: -1,
        bateRitmoAoJuntar: bateRitmoAoJuntar,
      );

  static Movimento _volverParado({
    required String nome,
    required int deltaSetor,
    required bool bateRitmoAoJuntar,
  }) => Movimento(
    nome: nome,
    exigido: const <Cadencia>{Cadencia.firme},
    segmentos: (_) => <Segmento>[
      Giro(deltaSetor),
      const Pausa(1),
      Juncao(bateRitmoAoJuntar: bateRitmoAoJuntar),
    ],
    cadenciaResultante: (_) => Cadencia.firme,
  );

  /// #11 — Alto. `A(1)·J`: 2 tempos, desloca 1 célula.
  static Movimento alto({bool bateRitmoAoJuntar = false}) => Movimento(
    nome: 'Alto',
    exigido: const <Cadencia>{Cadencia.marchando},
    segmentos: (_) => <Segmento>[
      const Avanco(1),
      Juncao(bateRitmoAoJuntar: bateRitmoAoJuntar),
    ],
    cadenciaResultante: (_) => Cadencia.firme,
  );

  /// #12 — Direita volver (marcha). `A(1)·P(1)·G(+2)·J`: 3 tempos, desloca
  /// 1 célula na direção ANTIGA (o `P(1)` é o passo do pé que "volta", não
  /// deslocamento extra).
  static Movimento direitaVolverMarcha({bool bateRitmoAoJuntar = false}) =>
      Movimento(
        nome: 'Direita volver (marcha)',
        exigido: const <Cadencia>{Cadencia.marchando},
        segmentos: (_) => <Segmento>[
          const Avanco(1),
          const Pausa(1),
          const Giro(2),
          Juncao(bateRitmoAoJuntar: bateRitmoAoJuntar),
        ],
        cadenciaResultante: (_) => Cadencia.firme,
      );

  /// #13 — Esquerda volver (marcha). `A(1)·G(-2)·J`: 2 tempos.
  static Movimento esquerdaVolverMarcha({bool bateRitmoAoJuntar = false}) =>
      Movimento(
        nome: 'Esquerda volver (marcha)',
        exigido: const <Cadencia>{Cadencia.marchando},
        segmentos: (_) => <Segmento>[
          const Avanco(1),
          const Giro(-2),
          Juncao(bateRitmoAoJuntar: bateRitmoAoJuntar),
        ],
        cadenciaResultante: (_) => Cadencia.firme,
      );

  /// #14 — Meia-volta (marcha). `A(1)·G(-4)·J`: 2 tempos.
  static Movimento meiaVoltaMarcha({bool bateRitmoAoJuntar = false}) =>
      Movimento(
        nome: 'Meia-volta (marcha)',
        exigido: const <Cadencia>{Cadencia.marchando},
        segmentos: (_) => <Segmento>[
          const Avanco(1),
          const Giro(-4),
          Juncao(bateRitmoAoJuntar: bateRitmoAoJuntar),
        ],
        cadenciaResultante: (_) => Cadencia.firme,
      );

  /// #15 — Oitava à direita (marcha). `A(1)·P(1)·G(+1)·J`: 3 tempos.
  static Movimento oitavaDireitaMarcha({bool bateRitmoAoJuntar = false}) =>
      Movimento(
        nome: 'Oitava à direita (marcha)',
        exigido: const <Cadencia>{Cadencia.marchando},
        segmentos: (_) => <Segmento>[
          const Avanco(1),
          const Pausa(1),
          const Giro(1),
          Juncao(bateRitmoAoJuntar: bateRitmoAoJuntar),
        ],
        cadenciaResultante: (_) => Cadencia.firme,
      );

  /// #16 — Oitava à esquerda (marcha). `A(1)·G(-1)·J`: 2 tempos.
  static Movimento oitavaEsquerdaMarcha({bool bateRitmoAoJuntar = false}) =>
      Movimento(
        nome: 'Oitava à esquerda (marcha)',
        exigido: const <Cadencia>{Cadencia.marchando},
        segmentos: (_) => <Segmento>[
          const Avanco(1),
          const Giro(-1),
          Juncao(bateRitmoAoJuntar: bateRitmoAoJuntar),
        ],
        cadenciaResultante: (_) => Cadencia.firme,
      );
}
