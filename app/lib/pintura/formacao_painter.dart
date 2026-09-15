import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:evo_motor/evo_motor.dart';
import 'package:flutter/material.dart';

import '../playback/controlador_playback.dart';
import '../tema/paleta.dart';

// Paleta de desenho — ver `tema/paleta.dart`. Fundo escuro, grade e rosa dos
// ventos em cinza discreto, pessoas nas quatro cores de cadência. O acento
// ciano é usado só onde carrega significado (destaque de batida) e nunca
// sobreposto a um preenchimento claro — ver a doc de [Paleta.acento].
const Color _corGrade = Paleta.grade;
const Color _corGradePonto = Paleta.gradePonto;
const Color _corFundo = Paleta.fundo;
const Color _corDestaque = Paleta.acento;

/// Regra de PRECEDÊNCIA de pintura para um conjunto de [TipoBatida] ativos
/// no mesmo tique: percussão sobrepõe passo. Motivo geométrico, não de
/// prioridade semântica — a janela segura de raio (`17,03..18,97px` na
/// célula de referência) cabe UM anel, não dois concêntricos (ver
/// `FormacaoPainter._desenharAnelDestaque`). O motor guarda os dois no
/// [EstadoRenderizado.batidas] (áudio futuro toca os dois); só a pintura
/// colapsa aqui.
///
/// Função pura — sem `Canvas` — de propósito: é o que permite testar a
/// regra (conjunto de entrada → o que desenhar) sem golden de pixel.
/// Devolve `null` quando não há nada para desenhar.
@visibleForTesting
TipoBatida? tipoBatidaParaDesenhar(Set<TipoBatida> batidas) {
  for (final TipoBatida percussao in <TipoBatida>[
    TipoBatida.mao,
    TipoBatida.pernaDireita,
    TipoBatida.pernaEsquerda,
  ]) {
    if (batidas.contains(percussao)) return percussao;
  }
  if (batidas.contains(TipoBatida.passo)) return TipoBatida.passo;
  return null;
}

/// Glifo vetorial do badge de cadência — desenhado com [Path]/[Canvas.drawLine]
/// diretamente, nunca com `ui.ParagraphBuilder` (texto de fonte). Tamanho de
/// fonte não dá controle de proporção confiável num ícone de poucos pixels:
/// essa era a causa raiz literal do "glifo vira borrão" (fonte 11 ocupando
/// quase metade de um quadrado de 18px) — ver a correção de 2026-09-14 no
/// badge, abaixo.
enum _GlifoCadencia { quadrado, chevron, x, anelVazado }

class _EstiloCadencia {
  const _EstiloCadencia({required this.cor, required this.glifo});
  final Color cor;
  final _GlifoCadencia glifo;
}

/// Cadência codificada em dois canais — cor do corpo + glifo do badge —
/// nunca só cor, pra não depender de daltonismo/contraste de projetor.
///
/// Até 2026-09-14 havia um terceiro canal (estilo de borda: sólida/
/// tracejada/pontilhada). Cortado: redundante com o badge e ilegível no
/// tamanho real de um indivíduo (traço de 4px/vão de 3px num quadrado de
/// 18px resolve em ruído, não em três estilos distinguíveis) — ver
/// [_desenharContorno].
const Map<Cadencia, _EstiloCadencia> _estilos = <Cadencia, _EstiloCadencia>{
  Cadencia.firme: _EstiloCadencia(
    cor: Color(0xFFD3D6DA),
    glifo: _GlifoCadencia.quadrado,
  ),
  Cadencia.descansar: _EstiloCadencia(
    cor: Color(0xFF6A6E74),
    glifo: _GlifoCadencia.anelVazado,
  ),
  Cadencia.marcandoPasso: _EstiloCadencia(
    cor: Color(0xFF9BA0A6),
    glifo: _GlifoCadencia.x,
  ),
  Cadencia.marchando: _EstiloCadencia(
    cor: Color(0xFFF2F3F5),
    glifo: _GlifoCadencia.chevron,
  ),
};

/// Desenha o pelotão inteiro sobre um `Canvas` — pessoa = silhueta
/// pentagonal única que aponta (nunca quadrado + triângulo de facing
/// sobrepostos); grade como linhas/pontos, nunca células pintadas (com
/// xadrez, um boneco entre cruzamentos lê como bug).
///
/// Correção de geometria do indivíduo (2026-09-14, segunda rodada): depois
/// de corrigir o enquadramento, o `design` mediu o app renderizado e achou
/// que o problema nunca tinha sido paleta — era a arquitetura de desenho da
/// pessoa. Três causas, todas de geometria/proporção, não de cor:
/// 1. O triângulo de facing (preto a 55% opacidade) desaparecia contra o
///    fundo escuro quando a ponta apontava pra fora do quadrado claro
///    (4,30:1 sobre o corpo, 1,07:1 sobre o fundo) — virado ao sul, sumia
///    e sobrava um trapézio ambíguo.
/// 2. O glifo de cadência usava `ui.ParagraphBuilder` (texto de fonte) em
///    tamanho 11, ocupando quase metade do quadrado — virava borrão por
///    proporção, não por contraste (que já era bom, 8,36:1).
/// 3. O destaque de batida era uma borda colorida soldada ao contorno do
///    quadrado — nenhuma cor testada (7 matizes, incluindo o âmbar antigo)
///    passava de 2,6:1 nessa posição, porque a borda ficava colada num
///    preenchimento claro.
///
/// A correção: [_pathSilhueta] substitui quadrado+triângulo por uma forma
/// única ("casa" apontando) cuja PRÓPRIA rotação já comunica o facing — sem
/// nenhum elemento sobreposto que possa cair sobre o fundo escuro. O glifo
/// vira um badge vetorial de cor própria (não depende mais do preenchimento
/// do corpo). O destaque de batida vira um anel desenhado FORA da silhueta
/// (ver [_desenharAnelDestaque]), nunca mais recolorindo o contorno.
///
/// Enquadramento automático (correção de 2026-09-14, primeira rodada): a
/// célula NÃO tem tamanho fixo em px — ela é derivada do `size` real
/// recebido em [paint] e do retângulo [enquadramento] (bounding box, em
/// células, de tudo que a formação ocupa ao longo de toda a faixa em
/// reprodução — não só o tique atual, ver [TransformacaoEnquadramento]).
class FormacaoPainter extends CustomPainter {
  FormacaoPainter({
    required this.estados,
    required this.campo,
    required this.enquadramento,
    this.mostrarLinhas = false,
    this.mostrarPontos = true,
    this.modoEditor = false,
    this.slotsSelecionados = const <int>{},
    this.slotsComContinuacao = const <int>{},
    this.slotsComPercussaoEditor = const <int>{},
  });

  final List<EstadoRenderizado> estados;
  final Campo campo;

  /// Modo do editor de partes (grid touch-first) — correção de
  /// 2026-09-15: até aqui, `pintura/pintura_slot_editor.dart` (removido)
  /// desenhava o editor sobre um layout FIXO por índice de slot, sempre
  /// "para cima" — o instrutor montava uma parte sem ver direção nem
  /// posição real. Este painter já resolve "formação que não é mais um
  /// retângulo" (enquadramento automático) para o playback; reaproveitá-lo
  /// para o editor, em vez de duplicar um segundo `CustomPainter`, é só
  /// questão de acrescentar as três informações que só o editor precisa —
  /// seleção, continuação implícita, percussão ESTÁTICA — como parâmetro,
  /// nunca como um arquivo novo.
  ///
  /// `false` (default, playback) preserva o comportamento anterior:
  /// arco/anel de destaque de batida ANIMADOS (a partir de [batidas] de
  /// cada [EstadoRenderizado]), sem seleção, sem quadrado de continuação.
  /// `true` (editor) desliga o destaque animado — o editor não toca
  /// eventos, só mostra um frame estático — e liga os três indicadores
  /// abaixo.
  final bool modoEditor;

  /// Slots destacados como SELECIONADOS na tela do editor — ignorado fora
  /// de [modoEditor].
  final Set<int> slotsSelecionados;

  /// Slots que RECEBERAM atribuição explícita na parte em edição (por
  /// oposição a "continuação implícita da parte anterior") — mesmo
  /// significado e mesma posição (canto inferior esquerdo) do quadrado
  /// ciano que `pintura_slot_editor.dart` desenhava. Ignorado fora de
  /// [modoEditor].
  final Set<int> slotsComContinuacao;

  /// Slots com percussão atribuída na parte em edição. Ponto ESTÁTICO
  /// (canto inferior direito) — não o arco animado de [batidas], que é
  /// sobre EVENTOS de reprodução (um conceito que não existe no editor:
  /// aqui é só "esta atribuição tem ou não tem percussão"). Ignorado fora
  /// de [modoEditor].
  final Set<int> slotsComPercussaoEditor;

  /// Bounding box (linha/coluna, em células, SEM margem ainda) de todas as
  /// posições ocupadas ao longo de toda a faixa em reprodução atual —
  /// calculado por [ControladorPlayback.enquadramentoCelulas], não aqui:
  /// isso é uma pergunta de domínio ("quais células a evolução usa"), este
  /// painter só decide COMO enquadrar esse retângulo (margem, teto/piso de
  /// escala). Ver a documentação de classe.
  final Rect enquadramento;

  /// Margem ao redor do conteúdo, em células, pra nenhuma pessoa ficar
  /// colada na borda. Pelo menos meia célula de cada lado: o `design`
  /// mediu que uma formação 5×5 pode ocupar ~1,41× da caixa original só
  /// com uma oitava (giro de 45°) — meia célula cobre essa expansão sem
  /// cortar ninguém contra a borda do enquadramento.
  static const double margemCelulas = 0.5;

  /// Piso de escala, em px lógicos — medido num retrato de 390px de
  /// largura (o menor comum, iPhone SE/mini): abaixo disso o indivíduo
  /// fica pequeno demais pro badge de cadência continuar distinguível
  /// entre os 4 estados. Não é um número arbitrário confortável: é também,
  /// coincidentemente, ~o que a evolução de exemplo atual já força num
  /// retrato comum em modo "evolução completa" (17 células de altura) —
  /// não dá pra subir o piso sem cortar conteúdo real nesse caso.
  static const double escalaMinimaPx = 18;

  /// Teto de escala, em px lógicos, pela mesma referência de retrato de
  /// 390px. Sem teto, uma formação de um indivíduo só (ex.: uma fileira
  /// isolada marchando enquanto o resto do pelotão fica parado fora da
  /// faixa selecionada) encheria a tela com uma silhueta gigante e fora de
  /// proporção com a densidade normal de um pelotão de 25.
  static const double escalaMaximaPx = 72;

  /// Transformação (escala + centro) calculada no início de cada [paint] a
  /// partir do [size] real da vez — ver [TransformacaoEnquadramento].
  TransformacaoEnquadramento _transformacao = const TransformacaoEnquadramento(
    tamanhoCelulaPx: escalaMinimaPx,
    centroLinha: 0,
    centroColuna: 0,
  );

  /// Linhas conectando os cruzamentos do grid. Desligadas por padrão —
  /// competiam com o conteúdo (reclamação de legibilidade de 2026-09-14);
  /// quando ligadas, usam [Paleta.grade], deliberadamente muito discreta.
  /// Independente de [mostrarPontos] — os quatro estados (nenhum/só
  /// linhas/só pontos/ambos) são válidos, inclusive "nenhum" (fundo limpo)
  /// durante o playback.
  final bool mostrarLinhas;

  /// Pontos nos cruzamentos do grid. Ligados por padrão — é a referência
  /// que ajuda a localizar onde uma pessoa "deveria" estar. Com as linhas
  /// desligadas por padrão, o ponto passa a ser a ÚNICA referência
  /// estrutural do campo — por isso [Paleta.gradePonto] subiu de alpha na
  /// mesma correção (0,349 → 0,45) pra compensar sozinho. Independente de
  /// [mostrarLinhas].
  final bool mostrarPontos;

  Offset _paraTela(Size size, double linha, double coluna) =>
      converterParaTela(size, _transformacao, linha, coluna);

  /// Converte (linha, coluna) em células para um `Offset` de tela, dada
  /// uma [TransformacaoEnquadramento] já calculada — extraído como método
  /// ESTÁTICO (não mais só um detalhe privado de instância) porque o
  /// editor de partes precisa da mesma conversão para hit-testing por
  /// proximidade (toque -> slot mais próximo) e para posicionar os rótulos
  /// de nome sobre cada silhueta; nenhum dos dois lados pode ter sua
  /// própria cópia da matemática sem arriscar as duas divergirem.
  static Offset converterParaTela(
    Size tela,
    TransformacaoEnquadramento transformacao,
    double linha,
    double coluna,
  ) {
    final Offset centro = Offset(tela.width / 2, tela.height / 2);
    return centro +
        Offset(
          (coluna - transformacao.centroColuna) * transformacao.tamanhoCelulaPx,
          (linha - transformacao.centroLinha) * transformacao.tamanhoCelulaPx,
        );
  }

  /// Escala px/célula corrente — tudo que é desenhado (silhueta, badge,
  /// glifo, anel de destaque, espessura de traço, raio do ponto de grade)
  /// deriva desse valor em vez de usar px absoluto, senão célula e
  /// conteúdo dessincronizam de novo assim que a célula deixa de ser fixa.
  double get _tamanhoCelulaPx => _transformacao.tamanhoCelulaPx;

  @override
  void paint(Canvas canvas, Size size) {
    _transformacao = TransformacaoEnquadramento.calcular(
      enquadramento: enquadramento,
      tela: size,
      margemCelulas: margemCelulas,
      escalaMinimaPx: escalaMinimaPx,
      escalaMaximaPx: escalaMaximaPx,
    );
    canvas.drawRect(Offset.zero & size, Paint()..color = _corFundo);
    _desenharGrade(canvas, size);
    _desenharRosaDosVentos(canvas, size);
    for (final EstadoRenderizado e in estados) {
      _desenharPessoa(canvas, size, e);
    }
  }

  void _desenharGrade(Canvas canvas, Size size) {
    if (mostrarLinhas) _desenharLinhasGrade(canvas, size);
    if (mostrarPontos) _desenharPontosGrade(canvas, size);
  }

  /// Linhas conectando os cruzamentos — ver [mostrarLinhas]. Cor bem
  /// discreta de propósito (ver [Paleta.grade]), pra não competir com o
  /// conteúdo quando ligada.
  void _desenharLinhasGrade(Canvas canvas, Size size) {
    final Paint linha = Paint()
      ..color = _corGrade
      ..strokeWidth = _escalar(1);

    final int meiaLargura = campo.larguraCelulas ~/ 2;
    final int meiaAltura = campo.alturaCelulas ~/ 2;

    for (int c = -meiaLargura; c <= meiaLargura; c++) {
      final Offset p1 = _paraTela(size, -meiaAltura.toDouble(), c.toDouble());
      final Offset p2 = _paraTela(size, meiaAltura.toDouble(), c.toDouble());
      canvas.drawLine(p1, p2, linha);
    }
    for (int l = -meiaAltura; l <= meiaAltura; l++) {
      final Offset p1 = _paraTela(size, l.toDouble(), -meiaLargura.toDouble());
      final Offset p2 = _paraTela(size, l.toDouble(), meiaLargura.toDouble());
      canvas.drawLine(p1, p2, linha);
    }
  }

  /// Pontos nos cruzamentos — ver [mostrarPontos]. Mais visíveis que as
  /// linhas finas de propósito: ajuda a localizar onde uma pessoa "deveria"
  /// estar quando ela está parada fora de um cruzamento (posição diagonal
  /// intermediária).
  void _desenharPontosGrade(Canvas canvas, Size size) {
    final Paint ponto = Paint()..color = _corGradePonto;

    final int meiaLargura = campo.larguraCelulas ~/ 2;
    final int meiaAltura = campo.alturaCelulas ~/ 2;

    for (int l = -meiaAltura; l <= meiaAltura; l++) {
      for (int c = -meiaLargura; c <= meiaLargura; c++) {
        canvas.drawCircle(
          _paraTela(size, l.toDouble(), c.toDouble()),
          _escalar(1.5),
          ponto,
        );
      }
    }
  }

  void _desenharRosaDosVentos(Canvas canvas, Size size) {
    const double raio = 22;
    final Offset centro = Offset(size.width - 40, 40);
    final Paint corpo = Paint()
      ..color = Paleta.cinzaMedio.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(centro, raio, corpo);
    final ui.ParagraphBuilder pb =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 12),
          )
          ..pushStyle(ui.TextStyle(color: Paleta.cinzaMedio))
          ..addText('N');
    final ui.Paragraph paragrafo = pb.build()
      ..layout(const ui.ParagraphConstraints(width: 20));
    canvas.drawParagraph(paragrafo, centro + const Offset(-6, -raio - 16));
    // Seta pra Norte (0 graus = topo, mesma convenção do facing setor 0).
    // Cinza discreto, não o acento — a rosa dos ventos é referência
    // permanente, não um sinal de "algo aconteceu", então não gasta o
    // canal de cor reservado a seleção/parte atual/destaque de batida.
    final Path seta = Path()
      ..moveTo(centro.dx, centro.dy - raio + 4)
      ..lineTo(centro.dx - 5, centro.dy - raio + 14)
      ..lineTo(centro.dx + 5, centro.dy - raio + 14)
      ..close();
    canvas.drawPath(seta, Paint()..color = Paleta.cinzaMedio);
  }

  /// Vértices da silhueta pentagonal ("casa" apontando), em px calibrados
  /// pra célula de referência de 36px — convertidos pra escala real via
  /// [_escalar]. Bounding box 22×28 centrada horizontalmente no eixo de
  /// rotação; o ápice (0,-15) é o "bico" que aponta o facing quando a
  /// forma inteira gira — não existe mais um triângulo de facing separado
  /// (ver a doc de classe).
  Path _pathSilhueta() {
    return Path()
      ..moveTo(_escalar(0), _escalar(-15))
      ..lineTo(_escalar(11), _escalar(-5))
      ..lineTo(_escalar(11), _escalar(13))
      ..lineTo(_escalar(-11), _escalar(13))
      ..lineTo(_escalar(-11), _escalar(-5))
      ..close();
  }

  void _desenharPessoa(Canvas canvas, Size size, EstadoRenderizado e) {
    final Offset centro = _paraTela(size, e.linha, e.coluna);
    final _EstiloCadencia estilo = _estilos[e.cadencia]!;

    _desenharLinhaImaginariaSeNecessario(canvas, size, e);

    // Destaque de SELEÇÃO (só editor) é desenhado ANTES da silhueta, de
    // propósito: é um halo atrás da pessoa, nunca algo que compete com o
    // corpo/badge por cima dela.
    if (modoEditor && slotsSelecionados.contains(e.slot)) {
      _desenharDestaqueSelecaoEditor(canvas, centro);
    }

    canvas.save();
    canvas.translate(centro.dx, centro.dy);
    canvas.rotate(grausParaRadianos(e.anguloGraus));

    final Path silhueta = _pathSilhueta();
    canvas.drawPath(silhueta, Paint()..color = estilo.cor);
    _desenharContorno(canvas, silhueta);

    canvas.restore();

    // Anel/arco de destaque de batida, quadrado de continuação e badge de
    // cadência são desenhados FORA do referencial rotacionado, de
    // propósito: precisam continuar legíveis (e, no caso do anel/quadrado,
    // geometricamente corretos) não importa o facing atual. O arco de
    // percussão do PLAYBACK É relativo ao facing (ver
    // [tipoBatidaParaDesenhar] e [_desenharArcoPercussao]), mas o cálculo
    // do ângulo já incorpora `e.anguloGraus` explicitamente — não depende
    // do `save`/`restore`.
    if (modoEditor) {
      // Editor: nenhum evento de reprodução existe aqui (é um frame
      // estático, não uma animação) — os indicadores são sempre os
      // mesmos três que `pintura_slot_editor.dart` desenhava sobre o
      // layout fixo, agora sobre a posição REAL.
      if (slotsComContinuacao.contains(e.slot)) {
        _desenharQuadradoContinuacaoEditor(canvas, centro);
      }
      if (slotsComPercussaoEditor.contains(e.slot)) {
        _desenharMarcaPercussaoEditor(canvas, centro);
      }
    } else {
      final TipoBatida? destaque = tipoBatidaParaDesenhar(e.batidas);
      if (destaque == TipoBatida.passo) {
        _desenharAnelDestaque(canvas, centro);
      } else if (destaque != null) {
        _desenharArcoPercussao(canvas, centro, destaque, e.anguloGraus);
      }
    }
    _desenharBadgeCadencia(canvas, centro, estilo);
  }

  /// Halo de seleção do editor — círculo translúcido + anel, desenhado em
  /// espaço de TELA (não rotaciona com o facing, como o anel de destaque
  /// de batida do playback). Mesmo raio de referência do anel de passo
  /// (`_escalar(17)`, dentro da janela segura documentada em
  /// [_desenharAnelDestaque]) para não competir com o quadrado de
  /// continuação/marca de percussão nos cantos inferiores.
  void _desenharDestaqueSelecaoEditor(Canvas canvas, Offset centro) {
    final double raio = _escalar(17);
    canvas.drawCircle(centro, raio, Paint()..color = _corDestaque.withValues(alpha: 0.22));
    canvas.drawCircle(
      centro,
      raio,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _escalar(1.5)
        ..color = _corDestaque,
    );
  }

  /// Quadrado ciano — canto inferior ESQUERDO, mesma geometria e mesmo
  /// motivo de `pintura_slot_editor.dart` (removido nesta correção):
  /// "recebeu instrução nesta parte" precisa de forma e posição própria
  /// (nunca uma variação de cor) para se distinguir do badge de cadência
  /// mesmo quando todo mundo está na mesma cadência.
  void _desenharQuadradoContinuacaoEditor(Canvas canvas, Offset centro) {
    final Offset centroMarca = centro + Offset(_escalar(-6), _escalar(8));
    final double lado = _escalar(7);
    canvas.drawRect(
      Rect.fromCenter(center: centroMarca, width: lado, height: lado),
      Paint()..color = _corDestaque,
    );
  }

  /// Pontinho — canto inferior DIREITO, mesma posição/motivo de
  /// `pintura_slot_editor.dart`: só "tem ou não tem" percussão nesta
  /// atribuição; qual membro é texto no painel, não geometria aqui.
  void _desenharMarcaPercussaoEditor(Canvas canvas, Offset centro) {
    final Offset p = centro + Offset(_escalar(6), _escalar(8));
    canvas.drawCircle(p, _escalar(2.5), Paint()..color = _corDestaque);
  }

  /// Contorno fino, decorativo e CONSTANTE — nunca varia por estado
  /// (cadência, seleção, destaque de batida). Até 2026-09-14 a borda
  /// carregava três canais (cor do destaque de batida + estilo
  /// sólido/tracejado/pontilhado da cadência); os dois foram cortados:
  /// o destaque de batida virou o anel externo em [_desenharAnelDestaque]
  /// (uma borda colorida soldada ao contorno de um preenchimento claro não
  /// passava de 2,6:1 em nenhum matiz testado), e o estilo tracejado/
  /// pontilhado virou ruído indistinguível no tamanho real de um
  /// indivíduo — o badge em [_desenharBadgeCadencia] já carrega essa
  /// distinção sozinho, sem redundância.
  void _desenharContorno(Canvas canvas, Path silhueta) {
    final Paint contorno = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _escalar(1)
      ..color = Colors.black.withValues(alpha: 0.45);
    canvas.drawPath(silhueta, contorno);
  }

  /// Destaque de batida: um anel fino desenhado no vão até a célula
  /// vizinha, nunca recolorindo o contorno do corpo (essa era a causa do
  /// destaque antigo falhar: 1,23:1 de contraste, borda colorida soldada
  /// num preenchimento claro).
  ///
  /// Raio ajustado de ~16px (número da spec) pra 18px na célula de
  /// referência de 36px: 16 cai DENTRO dos cantos inferiores da silhueta
  /// (o ponto mais distante do centro na silhueta é ~17,03px, nos dois
  /// cantos inferiores) — um anel de 16 cortaria a própria silhueta em vez
  /// de circundá-la. 18 (exatamente meia célula) limpa esses cantos com
  /// ~1px de folga e ainda fica sob o pior caso de vizinho ortogonal
  /// colado (célula adjacente a 36px de distância, virado de forma que um
  /// canto dela aponte de volta: folga até ~18,97px) — a janela seguro
  /// entre "fora da própria silhueta" e "não toca o vizinho mais hostil"
  /// é (17,03, 18,97), e 18 fica bem no meio dela.
  void _desenharAnelDestaque(Canvas canvas, Offset centro) {
    final Paint anel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _escalar(2)
      ..color = _corDestaque;
    canvas.drawCircle(centro, _escalar(18), anel);
  }

  /// Destaque de PERCUSSÃO: arco de 120°, mesmo raio do anel de passo
  /// (`_escalar(18)`), mas no referencial do CORPO — gira com o facing,
  /// ao contrário do badge de cadência (fixo em tela). "Perna esquerda" é
  /// egocêntrico: um arco fixo mostraria a batida do lado errado assim
  /// que a pessoa virasse.
  ///
  /// Diferenciação por GEOMETRIA (posição do arco ao redor do corpo),
  /// nunca por cor nem por glifo — a paleta acabou de ser fechada (ver
  /// `tema/paleta.dart`) e introduzir um matiz novo por membro duplicaria
  /// canal de codificação sem necessidade:
  /// - `mao` → centrado à frente do corpo.
  /// - `pernaDireita` → centrado no lado direito.
  /// - `pernaEsquerda` → centrado no lado esquerdo.
  ///
  /// As três posições (e os dois pisos de stroke/raio) são calibradas
  /// contra a mesma janela seguro documentada em [_desenharAnelDestaque]
  /// (17,03..18,97px na célula de referência de 36px): o arco nunca
  /// ultrapassa `_escalar(18)` de raio, e o stroke nunca cai abaixo de
  /// 1,5px (piso absoluto — `_escalar(2)` puro vira <1px no piso da
  /// escala e some).
  void _desenharArcoPercussao(
    Canvas canvas,
    Offset centro,
    TipoBatida tipo,
    double anguloGraus,
  ) {
    // `anguloGraus` é o facing no referencial "compasso" do app (0 =
    // Norte, horário) — o MESMO usado por `canvas.rotate` na silhueta.
    // `Canvas.drawArc`, por outro lado, mede a partir do eixo +X (Leste)
    // — daí o "-90" embutido no caso `mao` (que fica alinhada com o
    // próprio facing): os três casos abaixo já estão no referencial que
    // `drawArc` espera, não precisam de conversão extra aqui.
    final double centroGraus = switch (tipo) {
      TipoBatida.mao => anguloGraus - 90,
      TipoBatida.pernaDireita => anguloGraus,
      TipoBatida.pernaEsquerda => anguloGraus + 180,
      TipoBatida.passo => anguloGraus, // nunca chamado com passo.
    };
    final double startGraus = centroGraus - 60;
    const double sweepGraus = 120;

    final Paint arco = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(_escalar(2), 1.5)
      ..strokeCap = StrokeCap.round
      ..color = _corDestaque;
    canvas.drawArc(
      Rect.fromCircle(center: centro, radius: _escalar(18)),
      grausParaRadianos(startGraus),
      grausParaRadianos(sweepGraus),
      false,
      arco,
    );
  }

  /// Badge de cadência: círculo escuro fixo (nunca muda de cor com a
  /// cadência) com um glifo vetorial dentro — ver [_GlifoCadencia]. Fixo
  /// no canto superior direito da célula, em espaço de tela (não gira com
  /// o facing): um rótulo de estado tem que continuar legível não importa
  /// o ângulo, e um badge de canto que girasse junto sairia da posição
  /// esperada ("canto") a cada facing diferente.
  void _desenharBadgeCadencia(Canvas canvas, Offset centro, _EstiloCadencia estilo) {
    final Offset centroBadge = centro + Offset(_escalar(6), _escalar(-8));
    final double raioBadge = _escalar(6);
    canvas.drawCircle(
      centroBadge,
      raioBadge,
      Paint()..color = const Color(0xF21C1C1E), // rgba(28,28,30,0.95)
    );
    _desenharGlifoBadge(canvas, centroBadge, raioBadge, estilo.glifo);
  }

  /// Desenha o glifo com [Path]/linhas — nunca com `ui.ParagraphBuilder`
  /// (texto de fonte). Cor própria e constante (não deriva de
  /// [_EstiloCadencia.cor]): um cinza escuro de cadência como o de
  /// `descansar` renderizado sobre o badge daria ~3,3:1, bem abaixo do
  /// alvo — como o badge tem fundo próprio e fixo, o glifo também precisa
  /// de uma cor própria e fixa pra manter o contraste constante entre os
  /// 4 estados, em vez de herdar a variação do preenchimento do corpo.
  void _desenharGlifoBadge(
    Canvas canvas,
    Offset centro,
    double raioBadge,
    _GlifoCadencia glifo,
  ) {
    final double r = raioBadge * 0.55;
    final Paint traco = Paint()
      ..color = Paleta.claro
      ..style = PaintingStyle.stroke
      ..strokeWidth = raioBadge * 0.22
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (glifo) {
      case _GlifoCadencia.quadrado:
        canvas.drawRect(
          Rect.fromCenter(center: centro, width: r * 1.3, height: r * 1.3),
          Paint()..color = Paleta.claro,
        );
      case _GlifoCadencia.chevron:
        final Path chevron = Path()
          ..moveTo(centro.dx - r * 0.8, centro.dy - r * 0.35)
          ..lineTo(centro.dx, centro.dy + r * 0.65)
          ..lineTo(centro.dx + r * 0.8, centro.dy - r * 0.35);
        canvas.drawPath(chevron, traco);
      case _GlifoCadencia.x:
        canvas.drawLine(
          Offset(centro.dx - r * 0.75, centro.dy - r * 0.75),
          Offset(centro.dx + r * 0.75, centro.dy + r * 0.75),
          traco,
        );
        canvas.drawLine(
          Offset(centro.dx + r * 0.75, centro.dy - r * 0.75),
          Offset(centro.dx - r * 0.75, centro.dy + r * 0.75),
          traco,
        );
      case _GlifoCadencia.anelVazado:
        canvas.drawCircle(centro, r * 0.8, traco);
    }
  }

  /// Quando a posição repousa numa fronteira de meia-célula (resultado de
  /// um número ímpar de tempos diagonais), desenha a "linha imaginária"
  /// entre os dois pontos de grade mais próximos — vocabulário do próprio
  /// domínio pra essa posição intermediária.
  ///
  /// Simplificação de v1: quando os dois eixos estão em meia-célula ao
  /// mesmo tempo (o caso comum, chegando por um facing diagonal), a linha
  /// é desenhada ao longo da diagonal correspondente ao facing ATUAL,
  /// quando o facing também é diagonal; se a pessoa já girou parada nesse
  /// meio-ponto (facing ortogonal), cai no par NE-SO por padrão — um
  /// detalhe puramente visual, sem efeito na simulação.
  void _desenharLinhaImaginariaSeNecessario(
    Canvas canvas,
    Size size,
    EstadoRenderizado e,
  ) {
    final bool meioColuna = _ehMeioInteiro(e.coluna);
    final bool meioLinha = _ehMeioInteiro(e.linha);
    if (!meioColuna && !meioLinha) return;

    final double l0 = e.linha.floorToDouble();
    final double c0 = e.coluna.floorToDouble();
    final double l1 = meioLinha ? l0 + 1 : l0;
    final double c1 = meioColuna ? c0 + 1 : c0;

    late Offset p1;
    late Offset p2;
    if (meioLinha && meioColuna) {
      final int setorArredondado = ((e.anguloGraus / 45.0).round()) % 8;
      final bool diagonalNeSo = setorArredondado.isOdd
          ? (setorArredondado == 1 || setorArredondado == 5)
          : true; // ortogonal: cai no default NE-SO.
      if (diagonalNeSo) {
        p1 = _paraTela(size, l0, c0);
        p2 = _paraTela(size, l1, c1);
      } else {
        p1 = _paraTela(size, l0, c1);
        p2 = _paraTela(size, l1, c0);
      }
    } else if (meioLinha) {
      p1 = _paraTela(size, l0, c0);
      p2 = _paraTela(size, l1, c0);
    } else {
      p1 = _paraTela(size, l0, c0);
      p2 = _paraTela(size, l0, c1);
    }

    final Paint tracejado = Paint()
      ..color = Paleta.cinzaMedio.withValues(alpha: 0.5)
      ..strokeWidth = _escalar(1);
    _desenharLinhaTracejada(canvas, p1, p2, tracejado, _escalar(3), _escalar(3));
  }

  void _desenharLinhaTracejada(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint,
    double traco,
    double vao,
  ) {
    final double distancia = (b - a).distance;
    final Offset direcao = (b - a) / distancia;
    double percorrido = 0;
    bool desenhando = true;
    while (percorrido < distancia) {
      final double passo = math.min(
        desenhando ? traco : vao,
        distancia - percorrido,
      );
      if (desenhando) {
        canvas.drawLine(
          a + direcao * percorrido,
          a + direcao * (percorrido + passo),
          paint,
        );
      }
      percorrido += passo;
      desenhando = !desenhando;
    }
  }

  bool _ehMeioInteiro(double v) => (v - v.floorToDouble() - 0.5).abs() < 1e-6;

  /// Converte um valor calibrado pra uma célula de referência de 36px (o
  /// tamanho fixo antigo, antes da correção de enquadramento) pra px reais
  /// na escala corrente — é assim que "tudo que é desenhado escala junto"
  /// (silhueta, badge, glifo, anel de destaque, espessura de traço, raio
  /// do ponto de grade): se a célula dobra, o indivíduo dobra.
  double _escalar(double valorEmCelulaDe36px) =>
      _tamanhoCelulaPx * valorEmCelulaDe36px / 36;

  @override
  bool shouldRepaint(covariant FormacaoPainter oldDelegate) =>
      true; // Sempre `true`: os pontos flutuantes de EstadoRenderizado (posições
  // interpoladas do playback) mudam a cada frame; comparar campo a campo
  // custaria mais do que simplesmente repintar.
}

/// Escala (px por célula) e centro (em células) usados por [FormacaoPainter]
/// pra converter linha/coluna em pixels de tela — extraído em função pura
/// para poder ser testado sem montar um `Canvas` de verdade, E (desde a
/// correção do editor de partes de 2026-09-15) para ser reaproveitado por
/// código de produção fora do painter: `_GradeFormacaoEditor` precisa da
/// MESMA transformação para converter um toque na tela em (linha, coluna) —
/// hit-testing por proximidade, já que com gente fora dos cruzamentos do
/// grid original "que slot está aqui" deixa de ser divisão inteira. Por
/// isso não é mais `@visibleForTesting`: tem um consumidor de produção
/// legítimo, não só os testes deste arquivo.
class TransformacaoEnquadramento {
  const TransformacaoEnquadramento({
    required this.tamanhoCelulaPx,
    required this.centroLinha,
    required this.centroColuna,
  });

  final double tamanhoCelulaPx;
  final double centroLinha;
  final double centroColuna;

  /// Calcula a escala que faz o retângulo [enquadramento] (+ [margemCelulas]
  /// de cada lado) caber inteiro em [tela], respeitando [escalaMinimaPx] e
  /// [escalaMaximaPx]. O centro retornado é sempre o centro do retângulo
  /// COM margem — mas como [Rect.inflate] expande simetricamente, é o mesmo
  /// centro do retângulo original.
  factory TransformacaoEnquadramento.calcular({
    required Rect enquadramento,
    required Size tela,
    required double margemCelulas,
    required double escalaMinimaPx,
    required double escalaMaximaPx,
  }) {
    final Rect caixa = enquadramento.inflate(margemCelulas);
    final double larguraCelulas = math.max(caixa.width, 1e-6);
    final double alturaCelulas = math.max(caixa.height, 1e-6);
    final double escalaBruta = math.min(
      tela.width / larguraCelulas,
      tela.height / alturaCelulas,
    );
    return TransformacaoEnquadramento(
      tamanhoCelulaPx: escalaBruta.clamp(escalaMinimaPx, escalaMaximaPx),
      centroLinha: caixa.center.dy,
      centroColuna: caixa.center.dx,
    );
  }
}
