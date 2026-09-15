import 'falha_persistencia.dart';
import 'modelos/evolucao_doc.dart';
import 'modelos/parte_doc.dart';
import 'modelos/pelotao_doc.dart';
import 'modelos/resumo_evolucao.dart';

export 'falha_persistencia.dart';
export 'modelos/campo_doc.dart';
export 'modelos/evolucao_doc.dart';
export 'modelos/parte_doc.dart';
export 'modelos/pelotao_doc.dart';
export 'modelos/resumo_evolucao.dart';

/// Exceção lançada por toda escrita/leitura deste repositório que falha —
/// carrega o [FalhaPersistencia] já traduzido (ver `falha_persistencia.dart`)
/// para a tela nunca precisar inspecionar um `FirebaseException` cru.
class ErroPersistencia implements Exception {
  const ErroPersistencia(this.falha, {this.causa});

  final FalhaPersistencia falha;
  final Object? causa;

  @override
  String toString() => 'ErroPersistencia($falha, causa: $causa)';
}

/// A peça central da persistência do Evo Lab. Seis regras de disciplina
/// (ver handoff/README) valem para toda implementação, e a 3ª não é
/// verificável pelo compilador — só por revisão:
///
/// 1. Leitura só por `Stream`, nunca `Future`.
/// 2. O stream emite o DOCUMENTO INTEIRO, nunca um patch.
/// 3. A tela nunca renderiza o valor que ela mesma escreveu — escreve e
///    espera o stream trazer de volta.
/// 4. Escrita granular por parte, id explícito, upsert (nunca
///    "salvarEvolucaoInteira").
/// 5. `meta.pendente` NÃO é campo de documento — é
///    `snapshot.metadata.hasPendingWrites` (ver `EvolucaoDoc.pendente` e
///    afins).
/// 6. Tenancy (`clubId`/`uid`) nunca aparece nos `*Doc` que a tela
///    manipula — quem injeta na escrita e filtra na leitura é o adaptador.
///
/// EXTENSÕES sobre os 11 métodos do contrato original do handoff, todas
/// necessárias para a Etapa 4/5 (navegação mínima + exclusões) e que
/// seguem as MESMAS seis regras:
///   - [pelotoes] (stream de LISTA — o contrato original só tinha
///     `pelotao(id)` singular; sem uma lista não há como desenhar
///     "Clube → pelotão" antes de já se saber o id).
///   - [apagarPelotao] (Etapa 5 pede "apagar pelotão" explicitamente; o
///     contrato original tinha `gravarPelotao` mas nenhum `apagar*`
///     correspondente).
abstract interface class RepositorioEvo {
  Stream<List<ResumoEvolucao>> evolucoes();
  Stream<EvolucaoDoc?> evolucao(String id);

  /// Já ordenado e desempatado por `(ordem, id)` — ver `emOrdem()` em
  /// `ordenacao_partes.dart`, que é quem faz esse trabalho antes de expor
  /// a lista aqui.
  Stream<List<ParteDoc>> partes(String evolucaoId);

  Stream<PelotaoDoc?> pelotao(String id);

  /// Lista de pelotões do clube — ver nota de EXTENSÕES acima.
  Stream<List<PelotaoDoc>> pelotoes();

  /// Upsert por id, NUNCA "add".
  Future<void> gravarParte(ParteDoc parte);
  Future<void> apagarParte(String parteId);

  Future<void> gravarEvolucao(EvolucaoDoc doc);

  /// Cascata: `partes` da evolução são apagadas ANTES do documento da
  /// evolução (ver docs/DADOS.md, seção 4 — inverter a ordem deixa órfãos
  /// inalcançáveis, o incidente que o Domo já teve).
  Future<void> apagarEvolucao(String id);

  Future<void> gravarPelotao(PelotaoDoc doc);

  /// Apaga só o documento do pelotão — é *a* via de eliminação de dado
  /// pessoal (todos os rótulos vivem num documento só, docs/DADOS.md 2.3).
  /// NÃO apaga evoluções/partes que referenciam este pelotão (elas não
  /// dependem dele para autorização — ver a nota "variante de emergência"
  /// em docs/DADOS.md 4.1); ficam com um `pelotaoId` que não resolve mais,
  /// o que é aceitável porque `evolucoes`/`partes` não guardam dado
  /// pessoal (docs/DADOS.md 2.4).
  Future<void> apagarPelotao(String id);

  /// Gera um id local, sem round-trip de rede (`.doc()` sem argumento).
  String novoId();

  /// Renumera as partes de uma evolução para `1.0, 2.0, 3.0, ...`, em lote.
  /// Chamado quando [ordemEsgotada] (ver `ordem_fracionaria.dart`) sinaliza
  /// que o espaço fracionário entre duas partes vizinhas se esgotou.
  Future<void> renormalizarOrdens(String evolucaoId);
}
