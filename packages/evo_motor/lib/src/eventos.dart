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

/// Uma batida de ritmo (`bateRitmoAoJuntar` ou `bateRitmo` de `Pausa`) foi
/// marcada por um slot num tique global. Inerte no estado: alternar a flag
/// que gera este evento nunca muda um tique de posição/direção/cadência.
class EventoBatida extends Evento {
  const EventoBatida({required this.slot, required this.tiqueGlobal});

  final int slot;
  final int tiqueGlobal;
}

/// Uma rotação visual (ver [JanelaRotacao]) num intervalo de tiques
/// globais, para um slot.
class EventoRotacao extends Evento {
  const EventoRotacao({required this.slot, required this.janela});

  final int slot;
  final JanelaRotacao janela;
}
