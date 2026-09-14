import 'cadencia.dart';
import 'estado.dart';
import 'eventos.dart';
import 'geometria.dart';

/// Bloco atômico de construção de um [Movimento]. Regra uniforme do
/// catálogo: [Giro] nunca consome tempo — todo tempo vem de [Avanco]
/// (diretamente) ou de [Pausa]/[Juncao] (que marcam tempo sem deslocar).
sealed class Segmento {
  const Segmento();

  /// Duração em tiques (1 tempo = 2 tiques).
  int get duracaoTiques;
}

/// Avança `tempos` tempos no facing corrente. Para setor ortogonal (par),
/// 1 tempo desloca exatamente 1 célula; para setor diagonal (ímpar), 1
/// tempo desloca ~0,71 célula (fiel à geometria, ver `deltaPorTiquePorSetor`).
///
/// O nome do parâmetro é `tempos`, não `celulas`: o catálogo descreve
/// `A(n)` como "avança n células" só para o caso ortogonal (o comum);
/// fisicamente é sempre "n tempos no facing corrente", e é assim que os
/// testes de simetria diagonal (oitava) fazem sentido.
class Avanco extends Segmento {
  const Avanco(this.tempos) : assert(tempos >= 0);

  final int tempos;

  @override
  int get duracaoTiques => tempos * 2;
}

/// Marca `tempos` tempos sem deslocar. `bateRitmo` é inerte no estado — só
/// emite [EventoBatida]; alternar a flag não pode mudar um único tique de
/// posição/direção/cadência.
class Pausa extends Segmento {
  const Pausa(this.tempos, {this.bateRitmo = false}) : assert(tempos >= 0);

  final int tempos;
  final bool bateRitmo;

  @override
  int get duracaoTiques => tempos * 2;
}

/// Junção: 1 tempo, não desloca. `bateRitmoAoJuntar` é a mesma flag inerte
/// de [Pausa], só que amarrada à junção (movimentos 6-16 podem carregá-la).
class Juncao extends Segmento {
  const Juncao({this.bateRitmoAoJuntar = false});

  final bool bateRitmoAoJuntar;

  @override
  int get duracaoTiques => 2;
}

/// Giro instantâneo de `deltaSetor` setores (positivo = horário/direita).
/// Consome 0 tempo — aplicado numa fronteira de tique, entre o último tique
/// do segmento anterior e o primeiro tique do próximo.
class Giro extends Segmento {
  const Giro(this.deltaSetor);

  final int deltaSetor;

  @override
  int get duracaoTiques => 0;
}

/// Resultado de executar uma lista de [Segmento]s a partir de um estado
/// inicial: os estados por tique produzidos (um por tique, na ordem) e as
/// janelas de rotação para render (ver [JanelaRotacao]).
class ResultadoSegmentos {
  const ResultadoSegmentos({
    required this.tiques,
    required this.estadoFinal,
    required this.janelasRotacao,
    required this.batidas,
  });

  /// Um [EstadoPessoa] por tique consumido pelos segmentos, em ordem.
  final List<EstadoPessoa> tiques;

  /// Estado ao final de todos os segmentos (== `tiques.last` quando
  /// `tiques` não está vazio; carrega giros finais sem tique subsequente
  /// quando está).
  final EstadoPessoa estadoFinal;

  /// Janelas de rotação relativas ao início da execução (índice 0 =
  /// primeiro tique desta execução), para o renderer interpolar o ângulo.
  final List<JanelaRotacao> janelasRotacao;

  /// Índices de tique (relativos) em que uma batida de ritmo foi marcada.
  final List<int> batidas;
}

/// Executa uma sequência de [Segmento]s a partir de `inicial`, aplicando a
/// tabela de deslocamento por tique. `cadenciaFinal` é aplicada só no
/// último tique produzido (ver `Movimento.cadenciaResultante`) — durante a
/// execução, a cadência exibida é a de entrada, porque nenhum destes
/// segmentos por si só representa uma cadência diferente da corrente; a
/// mudança de cadência é um efeito do MOVIMENTO como um todo, não de um
/// segmento isolado. Essa é uma decisão de modelagem (o catálogo não
/// especifica cadência intra-movimento); documentada aqui porque não afeta
/// nenhum teste de propriedade pedido — todos comparam estado final.
ResultadoSegmentos executarSegmentos(
  EstadoPessoa inicial,
  List<Segmento> segmentos, {
  required Cadencia cadenciaFinal,
}) {
  final List<EstadoPessoa> tiques = <EstadoPessoa>[];
  final List<JanelaRotacao> janelas = <JanelaRotacao>[];
  final List<int> batidas = <int>[];

  int x = inicial.x;
  int y = inicial.y;
  int dir = inicial.dir;
  final Cadencia cadenciaEntrada = inicial.cad;

  for (final Segmento segmento in segmentos) {
    switch (segmento) {
      case Giro(:final int deltaSetor):
        final int dirAntes = dir;
        dir = normalizarSetor(dir + deltaSetor);
        // A janela de rotação é anexada ao(s) tique(s) do segmento
        // SEGUINTE ao giro (decisão de render documentada no catálogo:
        // nos volver/oitava parados ela cobre o P(1), o pivô). Se o giro
        // for o último segmento (não deveria acontecer no catálogo
        // congelado, mas é defensivo), não há tique para anexar e a
        // rotação fica instantânea sem janela visual.
        final int inicioJanela = tiques.length;
        janelas.add(
          JanelaRotacao(
            tiqueInicio: inicioJanela,
            // Preenchido abaixo quando soubermos quantos tiques o próximo
            // segmento consome; por ora aponta pro mesmo tique (será
            // corrigido in-place logo após o próximo segmento rodar).
            tiqueFim: inicioJanela,
            direcaoAntes: dirAntes,
            direcaoDepois: dir,
            deltaSetor: deltaSetor,
          ),
        );
      case Avanco(:final int tempos):
        final (int dx, int dy) = deltaPorTiquePorSetor[dir];
        for (int i = 0; i < tempos * 2; i++) {
          x += dx;
          y += dy;
          tiques.add(EstadoPessoa(x: x, y: y, dir: dir, cad: cadenciaEntrada));
        }
        _fecharJanelaPendente(janelas, tiques.length);
      case Pausa(:final int tempos, :final bool bateRitmo):
        for (int i = 0; i < tempos * 2; i++) {
          tiques.add(EstadoPessoa(x: x, y: y, dir: dir, cad: cadenciaEntrada));
          // Uma batida por TEMPO (a cada 2 tiques), não uma só no final do
          // bloco inteiro — "marcar passo"/"bater o ritmo" são a marcação
          // do pé a cada tempo, não um único evento ao fim de N tempos.
          if (bateRitmo && i.isOdd) {
            batidas.add(tiques.length - 1);
          }
        }
        _fecharJanelaPendente(janelas, tiques.length);
      case Juncao(:final bool bateRitmoAoJuntar):
        for (int i = 0; i < 2; i++) {
          tiques.add(EstadoPessoa(x: x, y: y, dir: dir, cad: cadenciaEntrada));
        }
        if (bateRitmoAoJuntar) {
          batidas.add(tiques.length - 1);
        }
        _fecharJanelaPendente(janelas, tiques.length);
    }
  }

  // A cadência final só se aplica ao ÚLTIMO tique produzido (é o instante
  // em que o movimento "termina" e a nova cadência passa a valer).
  EstadoPessoa estadoFinal;
  if (tiques.isNotEmpty) {
    final EstadoPessoa penultimo = tiques.removeLast();
    estadoFinal = penultimo.copiarCom(cad: cadenciaFinal);
    tiques.add(estadoFinal);
  } else {
    estadoFinal = EstadoPessoa(x: x, y: y, dir: dir, cad: cadenciaFinal);
  }

  return ResultadoSegmentos(
    tiques: tiques,
    estadoFinal: estadoFinal,
    janelasRotacao: janelas,
    batidas: batidas,
  );
}

void _fecharJanelaPendente(List<JanelaRotacao> janelas, int tiqueAtual) {
  if (janelas.isEmpty) return;
  final JanelaRotacao ultima = janelas.last;
  if (ultima.tiqueFim == ultima.tiqueInicio &&
      tiqueAtual > ultima.tiqueInicio) {
    janelas[janelas.length - 1] = ultima.copiarComFim(tiqueAtual);
  }
}
