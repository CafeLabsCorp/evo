import 'eventos.dart';

/// O membro que bate a percussão — mão na perna, pés se deslocando. Ver
/// `Atribuicao.percussao` e a regra de emissão em `compilador.dart`.
///
/// Deliberadamente um enum SEPARADO de [TipoBatida] (em vez de reusar
/// `TipoBatida` direto em `Percussao`): a única diferença semântica entre
/// os dois é que `TipoBatida.passo` não é um membro de percussão — dois
/// enums fazem de `Percussao(membro: passo)` algo IRREPRESENTÁVEL, em vez
/// de um valor válido que só o compilador saberia que nunca deveria
/// aparecer ali.
enum MembroPercussao { mao, pernaEsquerda, pernaDireita }

/// Percussão atribuída a um slot dentro de uma `Atribuicao`: densidade fixa
/// de uma batida por TEMPO (nunca por passo — ver a nota de densidade em
/// `compilador.dart`), indexada à grade de tempos do slot, não ao
/// movimento em si.
class Percussao {
  const Percussao({required this.membro});

  final MembroPercussao membro;

  TipoBatida get tipoBatida => switch (membro) {
    MembroPercussao.mao => TipoBatida.mao,
    MembroPercussao.pernaEsquerda => TipoBatida.pernaEsquerda,
    MembroPercussao.pernaDireita => TipoBatida.pernaDireita,
  };
}
