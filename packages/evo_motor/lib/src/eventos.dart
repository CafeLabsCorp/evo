/// Janela de tiques (relativa ao início de uma execução de segmentos, ou
/// global depois de `simular`) sobre a qual o renderer deve interpolar a
/// rotação de `direcaoAntes` para `direcaoDepois`. O estado em si nunca
/// tem ângulo intermediário — isso é só uma dica de render.
class JanelaRotacao {
  const JanelaRotacao({
    required this.tiqueInicio,
    required this.tiqueFim,
    required this.direcaoAntes,
    required this.direcaoDepois,
    required this.deltaSetor,
  });

  final int tiqueInicio;
  final int tiqueFim;
  final int direcaoAntes;
  final int direcaoDepois;

  /// Delta ASSINADO do giro (ex.: `-4` para meia-volta pela esquerda),
  /// antes de normalizar para 0..7. Sem isso o render não sabe pra que
  /// lado girar num caso ambíguo em módulo 8 (meia-volta: 4 passos pra
  /// qualquer um dos dois lados dão no mesmo `direcaoDepois`).
  final int deltaSetor;

  JanelaRotacao copiarComFim(int fim) => JanelaRotacao(
    tiqueInicio: tiqueInicio,
    tiqueFim: fim,
    direcaoAntes: direcaoAntes,
    direcaoDepois: direcaoDepois,
    deltaSetor: deltaSetor,
  );

  JanelaRotacao deslocarPara(int offsetGlobal) => JanelaRotacao(
    tiqueInicio: tiqueInicio + offsetGlobal,
    tiqueFim: tiqueFim + offsetGlobal,
    direcaoAntes: direcaoAntes,
    direcaoDepois: direcaoDepois,
    deltaSetor: deltaSetor,
  );
}

/// Evento produzido pela simulação — puramente informativo, não afeta
/// estado. Usado por render (batida sonora/visual) e por debug.
sealed class Evento {
  const Evento();
}

/// O que fisicamente bateu num [EventoBatida]. `passo` é a batida de
/// cadência que já existia (`bateRitmoAoJuntar`/`bateRitmo` de `Pausa`);
/// `mao`/`pernaEsquerda`/`pernaDireita` são o canal de percussão (ver
/// `Percussao`, em `percussao.dart`) — mão na perna, pés se deslocando,
/// caindo junto com a passada.
///
/// Sem default no construtor de [EventoBatida]: um default silencioso aqui
/// seria como se perder a distinção entre "passo" e "percussão" bem no
/// ponto em que ela passou a existir.
enum TipoBatida { passo, mao, pernaEsquerda, pernaDireita }

/// Uma batida foi marcada por um slot num tique global — de cadência
/// (`bateRitmoAoJuntar`/`bateRitmo` de `Pausa`, `tipo: TipoBatida.passo`)
/// ou de percussão (ver `Percussao`). Inerte no estado: alternar a flag/
/// atribuição que gera este evento nunca muda um tique de
/// posição/direção/cadência.
///
/// **A lista de eventos NÃO é globalmente ordenada por tique.** Dentro de
/// um mesmo slot, os eventos de percussão vêm sempre depois dos eventos de
/// movimento daquele slot (documentado em `compilador.dart`); entre slots
/// diferentes não há ordem garantida nenhuma. Consumidores que precisam de
/// ordem (render, por exemplo) devem indexar/ordenar eles mesmos — nunca
/// depender da ordem de iteração desta lista.
class EventoBatida extends Evento {
  const EventoBatida({
    required this.slot,
    required this.tiqueGlobal,
    required this.tipo,
  });

  final int slot;
  final int tiqueGlobal;
  final TipoBatida tipo;
}

/// Uma rotação visual (ver [JanelaRotacao]) num intervalo de tiques
/// globais, para um slot.
class EventoRotacao extends Evento {
  const EventoRotacao({required this.slot, required this.janela});

  final int slot;
  final JanelaRotacao janela;
}
