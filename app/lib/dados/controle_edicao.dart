/// Quem está autorizado a editar agora — separado do `RepositorioEvo` de
/// propósito: hoje é sempre "eu" ([TravaSempreMinha]), porque não existe
/// segundo usuário (docs/DADOS.md, seção 6, "Trava (lease) de edição por
/// parte" está deliberadamente fora do escopo desta versão). Quando a trava
/// real entrar, ela implementa esta MESMA interface — nenhuma linha da tela
/// que consulta [ControleDeEdicao] precisa mudar, só a implementação
/// injetada muda.
enum DonoDaTrava {
  /// Esta sessão pode editar.
  minha,

  /// Outra pessoa está editando agora — a tela deve ficar somente-leitura.
  /// Nunca produzido por [TravaSempreMinha]; existe para quando a trava
  /// real chegar.
  deOutraPessoa,
}

abstract interface class ControleDeEdicao {
  /// A quem pertence a trava de edição agora — a tela decide o modo
  /// somente-leitura a partir disto. É O MESMO RAMO usado pelo modo
  /// ensaio/visualização (abrir uma evolução só para tocar o playback, sem
  /// intenção de editar): "não posso escrever agora" tem uma única
  /// representação na UI, venha de onde vier.
  Stream<DonoDaTrava> dono();

  /// Pede a trava para esta sessão. [TravaSempreMinha] sempre concede
  /// (`true`) — não existe hoje um motivo para negar, porque não existe
  /// concorrência. A assinatura já é `Future<bool>` (pode falhar/ser
  /// negada) para que a implementação real não exija mudar quem chama.
  Future<bool> pedir();
}

/// Implementação atual — ver o dartdoc de [ControleDeEdicao]. Deliberadamente
/// sem estado e sem I/O.
class TravaSempreMinha implements ControleDeEdicao {
  const TravaSempreMinha();

  @override
  Stream<DonoDaTrava> dono() => Stream<DonoDaTrava>.value(DonoDaTrava.minha);

  @override
  Future<bool> pedir() async => true;
}
