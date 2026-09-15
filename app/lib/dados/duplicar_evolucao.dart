import 'repositorio_evo.dart';

/// "Duplicar evolução para outro pelotão" — a saída aprovada para o beco
/// criado por `pelotaoId` ser imutável por regra (as chaves de slot só têm
/// significado dentro de UM grid): na virada de temporada, um pelotão novo
/// não pode simplesmente "herdar" as evoluções do antigo por update, porque
/// isso reinterpretaria silenciosamente os mesmos índices de slot para
/// pessoas diferentes.
///
/// A saída NÃO exige mudar regra nenhuma: não é update, é CREATE. Copia
/// `estadoInicial` e todas as partes para uma evolução nova com o
/// `pelotaoId` novo — a reinterpretação dos índices deixa de ser silenciosa
/// e vira uma ação explícita e visível (o usuário abre a evolução nova,
/// confere, e só então decide o que fazer da antiga). O original nunca é
/// tocado — sobra como fallback caso a duplicata precise de ajustes.
///
/// Função livre (não método do controlador) de propósito: só depende da
/// interface pública de [RepositorioEvo] (leitura pontual via `.first` +
/// as mesmas escritas granulares de sempre), então é testável sem nenhuma
/// tela em volta.
Future<String> duplicarEvolucaoParaPelotao({
  required RepositorioEvo repo,
  required String evolucaoId,
  required String pelotaoIdDestino,
  String? novoNome,
}) async {
  final EvolucaoDoc? origem = await repo.evolucao(evolucaoId).first;
  if (origem == null) {
    throw StateError('Evolução "$evolucaoId" não existe mais — nada para duplicar.');
  }
  final List<ParteDoc> partesOrigem = await repo.partes(evolucaoId).first;

  final String novoId = repo.novoId();
  final DateTime agora = DateTime.now();
  final EvolucaoDoc copia = EvolucaoDoc(
    id: novoId,
    nome: novoNome ?? '${origem.nome} (cópia)',
    pelotaoId: pelotaoIdDestino,
    estadoInicial: Map<String, dynamic>.of(origem.estadoInicial),
    versaoCatalogo: origem.versaoCatalogo,
    criadoEm: agora,
    atualizadoEm: agora,
    campo: origem.campo,
  );
  await repo.gravarEvolucao(copia);

  for (final ParteDoc parte in partesOrigem) {
    await repo.gravarParte(
      ParteDoc(
        id: repo.novoId(),
        evolucaoId: novoId,
        ordem: parte.ordem,
        nome: parte.nome,
        atribuicoes: Map<String, dynamic>.of(parte.atribuicoes),
        atualizadoEm: agora,
      ),
    );
  }

  return novoId;
}
