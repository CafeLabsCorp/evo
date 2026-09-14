import 'movimento.dart';
import 'preenchimento.dart';

/// O que um slot faz dentro de uma [Parte].
///
/// `preenchimento` cobre tanto os tiques antes do `offsetInicialTiques`
/// (esperando a deixa) quanto os de depois do movimento (até a parte
/// fechar em `T`). Se `null`, o default materializado é "continuação da
/// cadência final" do movimento (nunca `firme` hardcoded) — ver
/// [Preenchimento.paraCadencia]. A spec pede que esse default seja
/// materializado "na gravação, não resolvido na leitura"; a v1 não tem
/// editor, então materializamos no momento em que a [Atribuicao] é
/// construída/compilada — mesmo efeito prático (determinístico, nunca
/// recalculado de formas diferentes em execuções diferentes), documentado
/// aqui como simplificação de v1.
class Atribuicao {
  Atribuicao({
    required this.movimento,
    this.offsetInicialTiques = 0,
    this.preenchimento,
  }) : assert(offsetInicialTiques >= 0) {
    if (offsetInicialTiques.isOdd) {
      throw ArgumentError.value(
        offsetInicialTiques,
        'offsetInicialTiques',
        'precisa ser um número PAR de tiques — 1 tempo = 2 tiques sempre, '
        'e o motor não tem noção de "meio tempo" pra esperar antes de um '
        'comando. Um offset ímpar quebraria mais adiante, dentro do '
        'preenchimento de espera, com um erro bem menos claro do que este.',
      );
    }
  }

  final Movimento movimento;
  final int offsetInicialTiques;
  final Preenchimento? preenchimento;
}

/// Um frame de instruções simultâneas: subgrupos diferentes fazendo
/// movimentos diferentes ao mesmo tempo. `ordem` é a posição da parte
/// dentro da evolução (permite reordenar sem renumerar).
class Parte {
  const Parte({required this.ordem, required this.atribuicoes, this.nome});

  final double ordem;
  final Map<int, Atribuicao> atribuicoes;
  final String? nome;
}
