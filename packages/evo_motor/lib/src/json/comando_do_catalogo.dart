/// O comando-fonte de um movimento do catálogo — dado puro, sem closure,
/// que sabe se materializar num [Movimento] compilado e se (de)serializar
/// para JSON.
///
/// ## Por que isto existe (o buraco que fecha)
///
/// [Movimento] é documentado como "já resolvido em segmentos concretos": ele
/// guarda `nome` (rótulo humano, ex. `'Em frente, marche (AoTerminarMarche.
/// firme)'`) e `segmentos` como uma CLOSURE. Nenhum dos dois é serializável
/// — a closure obviamente não, e o `nome` é texto para humano, não um
/// discriminador estável (não há como voltar de `'Direita volver'` para
/// `direitaVolverParado(bateRitmoAoJuntar: true)` com segurança).
/// Consequência prática, antes desta classe existir: um `Movimento` não
/// volta para JSON, então `Atribuicao` não é round-trippable, e sem isso não
/// existe "gravar a parte que o usuário editou" — o editor não tinha por
/// onde começar.
///
/// A tentação óbvia seria dar um discriminador ao próprio `Movimento`
/// (guardar o `tipo` nele). **Deliberadamente não fizemos isso**: isso
/// criaria duas fontes de verdade dentro da mesma classe (o `tipo`
/// declarado e os `segmentos` de fato construídos) e permitiria montar um
/// `Movimento` cujo `tipo` não bate com o que ele realmente faz — um jeito
/// de mentir que o compilador não pegaria.
///
/// Em vez disso, `ComandoDoCatalogo` fica ao lado de `Movimento`, num nível
/// abaixo: é o "código-fonte" (tipo + parâmetros brutos, tudo dado, nada de
/// closure); `Movimento` continua sendo exclusivamente a forma "compilada"
/// (segmentos concretos), obtida chamando [materializar]. A mesma
/// distinção-fonte/compilado que o README já enuncia para posição
/// ("nenhuma posição calculada é persistida, só comandos" — corrigir o
/// catálogo re-renderiza tudo, sem migração) se aplica aqui um nível acima:
/// o editor e o banco manipulam `ComandoDoCatalogo` (fonte); o motor
/// consome `Movimento` (compilado), derivado na hora de simular. Corrigir
/// o catálogo (mudar o que `direitaVolverParado()` produz, por exemplo)
/// continua re-renderizando toda evolução gravada sem migração — porque o
/// que fica gravado é só `tipo` + parâmetros, nunca segmentos.
///
/// ## A única cópia da gramática
///
/// [materializar] contém o `switch (tipo)` que despacha para `Catalogo` —
/// **esta é a única cópia dessa lógica no pacote**; era exatamente o que
/// `movimentoDoJson` fazia antes, e continua sendo feito no mesmo lugar,
/// só que agora por trás de um objeto que também sabe voltar para JSON.
/// `movimentoDoJson` hoje é só `ComandoDoCatalogo.doJson(json)
/// .materializar()`.
///
/// [paraJson] também tem um `switch (tipo)`, mas é uma cópia de uma coisa
/// DIFERENTE: não é "que `Catalogo.xxx` este tipo chama" (isso mora só em
/// [materializar]), é "quais chaves opcionais fazem sentido no JSON deste
/// tipo" (puramente de formatação — para o JSON ficar tão enxuto quanto os
/// arquivos gravados à mão, sem `"tempos"` sobrando em movimentos que não
/// usam tempos). Mudar o que um movimento do catálogo FAZ nunca exige tocar
/// em [paraJson]; só mudar quais PARÂMETROS ele aceita exigiria.
library;

import '../catalogo.dart';
import '../movimento.dart';

/// Descreve um movimento do catálogo pelos dados brutos que o catálogo
/// aceita: `tipo` (o discriminador — a mesma string usada no JSON, ex.
/// `'direitaVolverParado'`) e os parâmetros que os 16 construtores de
/// [Catalogo] hoje aceitam entre si: `tempos`, `n`, `aoTerminar`,
/// `bateRitmoAoJuntar`. Nenhum movimento do catálogo atual precisa de mais
/// campos do que estes quatro — ver a tabela de uso em [materializar].
///
/// Deliberadamente SEM um `Map<String, dynamic> extras` para parâmetros
/// futuros: isso destruiria a garantia de round-trip total (um campo dentro
/// de `extras` poderia ser esquecido silenciosamente por qualquer um dos
/// dois lados do codec). Se um movimento novo do catálogo algum dia
/// precisar de um parâmetro que não caiba nestes quatro campos, o campo
/// novo entra aqui, nomeado, e os dois `switch` (`materializar`/`paraJson`)
/// passam a tratá-lo explicitamente para os tipos que o usam.
class ComandoDoCatalogo {
  const ComandoDoCatalogo({
    required this.tipo,
    this.tempos = 1,
    this.n,
    this.aoTerminar,
    this.bateRitmoAoJuntar = false,
  });

  /// Discriminador do catálogo — mesma string do campo `tipo` no JSON de
  /// `movimento` (ex. `'sentido'`, `'emFrenteMarche'`,
  /// `'direitaVolverParado'`). Ver [materializar] para a lista completa dos
  /// 16 valores aceitos.
  final String tipo;

  /// Usado por #1 Sentido, #2 Descansar, #3 Marcar passo e #4 Bater o
  /// ritmo. Ignorado (mas presente, com o default `1`) para os demais 12
  /// tipos.
  final int tempos;

  /// Usado só por #5 Em frente, marche (`emFrenteMarche`) — quantidade de
  /// tempos de avanço. `null` para os outros 15 tipos.
  final int? n;

  /// Usado só por #5 Em frente, marche — como a marcha termina. `null`
  /// para os outros 15 tipos.
  final AoTerminarMarche? aoTerminar;

  /// Usado por #3, #5 e #6..#16 (todo movimento que termina numa junção
  /// opcionalmente sonora). Ignorado (default `false`) para #1, #2 e #4,
  /// que não juntam nada.
  final bool bateRitmoAoJuntar;

  /// Resolve este comando num [Movimento] compilado (segmentos concretos),
  /// delegando para o construtor correspondente de [Catalogo]. Único lugar
  /// do pacote que sabe "qual `tipo` chama qual função do catálogo" — a
  /// mesma responsabilidade que `movimentoDoJson` tinha antes desta classe
  /// existir.
  Movimento materializar() {
    switch (tipo) {
      case 'sentido':
        return Catalogo.sentido(tempos: tempos);
      case 'descansar':
        return Catalogo.descansar(tempos: tempos);
      case 'marcarPasso':
        return Catalogo.marcarPasso(
          tempos: tempos,
          bateRitmoAoJuntar: bateRitmoAoJuntar,
        );
      case 'baterORitmo':
        return Catalogo.baterORitmo(tempos: tempos);
      case 'emFrenteMarche':
        return Catalogo.emFrenteMarche(
          n as int,
          aoTerminar: aoTerminar as AoTerminarMarche,
          bateRitmoAoJuntar: bateRitmoAoJuntar,
        );
      case 'direitaVolverParado':
        return Catalogo.direitaVolverParado(
          bateRitmoAoJuntar: bateRitmoAoJuntar,
        );
      case 'esquerdaVolverParado':
        return Catalogo.esquerdaVolverParado(
          bateRitmoAoJuntar: bateRitmoAoJuntar,
        );
      case 'meiaVoltaParado':
        return Catalogo.meiaVoltaParado(bateRitmoAoJuntar: bateRitmoAoJuntar);
      case 'oitavaDireitaParado':
        return Catalogo.oitavaDireitaParado(
          bateRitmoAoJuntar: bateRitmoAoJuntar,
        );
      case 'oitavaEsquerdaParado':
        return Catalogo.oitavaEsquerdaParado(
          bateRitmoAoJuntar: bateRitmoAoJuntar,
        );
      case 'alto':
        return Catalogo.alto(bateRitmoAoJuntar: bateRitmoAoJuntar);
      case 'direitaVolverMarcha':
        return Catalogo.direitaVolverMarcha(
          bateRitmoAoJuntar: bateRitmoAoJuntar,
        );
      case 'esquerdaVolverMarcha':
        return Catalogo.esquerdaVolverMarcha(
          bateRitmoAoJuntar: bateRitmoAoJuntar,
        );
      case 'meiaVoltaMarcha':
        return Catalogo.meiaVoltaMarcha(bateRitmoAoJuntar: bateRitmoAoJuntar);
      case 'oitavaDireitaMarcha':
        return Catalogo.oitavaDireitaMarcha(
          bateRitmoAoJuntar: bateRitmoAoJuntar,
        );
      case 'oitavaEsquerdaMarcha':
        return Catalogo.oitavaEsquerdaMarcha(
          bateRitmoAoJuntar: bateRitmoAoJuntar,
        );
      default:
        throw FormatException('Movimento desconhecido no catálogo: "$tipo"');
    }
  }

  /// Serializa este comando para JSON — a metade de escrita que faltava.
  /// Emite só as chaves relevantes para `tipo` (ex.: `tempos` não aparece
  /// em `direitaVolverParado`, que não usa tempos) para que o JSON
  /// produzido fique no mesmo formato enxuto dos arquivos gravados à mão
  /// (ver `app/assets/evolucoes/exemplo.json`) — mas isto é só formatação;
  /// a gramática de "que tipo aceita que parâmetro" mora inteira em
  /// [materializar], não aqui (ver dartdoc de classe).
  Map<String, dynamic> paraJson() {
    final Map<String, dynamic> json = <String, dynamic>{'tipo': tipo};
    switch (tipo) {
      case 'sentido':
      case 'descansar':
      case 'baterORitmo':
        json['tempos'] = tempos;
      case 'marcarPasso':
        json['tempos'] = tempos;
        json['bateRitmoAoJuntar'] = bateRitmoAoJuntar;
      case 'emFrenteMarche':
        json['n'] = n as int;
        json['aoTerminar'] = _aoTerminarParaJson(aoTerminar as AoTerminarMarche);
        json['bateRitmoAoJuntar'] = bateRitmoAoJuntar;
      case 'direitaVolverParado':
      case 'esquerdaVolverParado':
      case 'meiaVoltaParado':
      case 'oitavaDireitaParado':
      case 'oitavaEsquerdaParado':
      case 'alto':
      case 'direitaVolverMarcha':
      case 'esquerdaVolverMarcha':
      case 'meiaVoltaMarcha':
      case 'oitavaDireitaMarcha':
      case 'oitavaEsquerdaMarcha':
        json['bateRitmoAoJuntar'] = bateRitmoAoJuntar;
      default:
        throw FormatException('Movimento desconhecido no catálogo: "$tipo"');
    }
    return json;
  }

  /// Lê um comando de JSON. Deliberadamente NÃO valida `tipo` aqui — só
  /// extrai os campos genéricos que aparecem no formato (`tipo`, `tempos`,
  /// `n`, `aoTerminar`, `bateRitmoAoJuntar`), com os mesmos defaults que
  /// `movimentoDoJson` sempre teve (`tempos` ausente ⇒ `1`,
  /// `bateRitmoAoJuntar` ausente ⇒ `false`). A rejeição de um `tipo`
  /// desconhecido acontece em [materializar] e em [paraJson] — cada
  /// consumidor deste comando decide sozinho se um tipo que não reconhece
  /// é erro, sem duplicar essa checagem aqui.
  static ComandoDoCatalogo doJson(Map<String, dynamic> json) {
    final String tipo = json['tipo'] as String;
    final dynamic aoTerminarJson = json['aoTerminar'];
    final AoTerminarMarche? aoTerminar = aoTerminarJson == null
        ? null
        : switch (aoTerminarJson as String) {
            'marchando' => AoTerminarMarche.marchando,
            'marcandoPasso' => AoTerminarMarche.marcandoPasso,
            'firme' => AoTerminarMarche.firme,
            final String outro => throw FormatException(
              'aoTerminar desconhecido: "$outro"',
            ),
          };
    return ComandoDoCatalogo(
      tipo: tipo,
      tempos: json['tempos'] as int? ?? 1,
      n: json['n'] as int?,
      aoTerminar: aoTerminar,
      bateRitmoAoJuntar: json['bateRitmoAoJuntar'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ComandoDoCatalogo &&
      other.tipo == tipo &&
      other.tempos == tempos &&
      other.n == n &&
      other.aoTerminar == aoTerminar &&
      other.bateRitmoAoJuntar == bateRitmoAoJuntar;

  @override
  int get hashCode => Object.hash(tipo, tempos, n, aoTerminar, bateRitmoAoJuntar);

  @override
  String toString() =>
      'ComandoDoCatalogo(tipo: $tipo, tempos: $tempos, n: $n, '
      'aoTerminar: $aoTerminar, bateRitmoAoJuntar: $bateRitmoAoJuntar)';
}

String _aoTerminarParaJson(AoTerminarMarche aoTerminar) => switch (aoTerminar) {
  AoTerminarMarche.marchando => 'marchando',
  AoTerminarMarche.marcandoPasso => 'marcandoPasso',
  AoTerminarMarche.firme => 'firme',
};
