import 'modelos/campo_doc.dart';
import 'modelos/evolucao_doc.dart';
import 'modelos/parte_doc.dart';
import 'modelos/pelotao_doc.dart';

// =============================================================================
// VALIDADOR-ESPELHO — a contraparte de cliente de `firestore.rules`
// =============================================================================
// POR QUE ISTO EXISTE (e não é conforto de UX):
//
// O Firestore devolve `permission-denied` de forma IDÊNTICA para "você não tem
// autorização" e para "seu documento não passou na validação". O cliente não
// consegue distinguir os dois olhando o erro — então, sem este arquivo, toda
// mensagem de falha de escrita é um chute, e às vezes um chute errado. Foi
// exatamente o que aconteceu no bug de criação de pelotão: o app dizia "o dado
// não passou na validação do servidor" para o que era, na verdade, uma leitura
// negada dentro da transação.
//
// COMO ISSO RESOLVE: toda escrita valida AQUI antes de ir para a rede. Se
// falhar aqui, o app diz exatamente qual verificação falhou. Se passar aqui e o
// servidor ainda negar, a dedução passa a ser sólida — sobrou autorização
// (sessão expirada, clube errado, uid fora de `membrosAtivos`), e é isso que a
// mensagem diz. Ver `RepositorioEvoFirestore`.
//
// -----------------------------------------------------------------------------
// CONTRATO DE ESPELHAMENTO 1:1 — leia antes de editar qualquer coisa aqui
// -----------------------------------------------------------------------------
// Cada função abaixo espelha uma função nomeada de `firestore.rules`, na MESMA
// ORDEM de asserções, e o nome da função do servidor está citado no comentário
// de cada bloco. `firestore.rules` tem a citação recíproca apontando para cá.
//
//   pelotaoValido()   / rotulosValidos()   -> validarPelotao
//   evolucaoValida()  / campoValido()      -> validarEvolucao
//   parteValida()     / atribuicoesValidas -> validarParte
//
// REGRA DE MANUTENÇÃO: mexeu numa, mexe na outra NO MESMO COMMIT. Um espelho
// que diverge é pior que espelho nenhum — ele passa a AFIRMAR com confiança
// que o dado está bom enquanto o servidor recusa, e aí a mensagem volta a
// mentir, só que agora com um ar de autoridade.
//
// O QUE NÃO É ESPELHADO, e por quê:
//
//   - `membroAtivo(clubId)`: depende de `get()` no documento do clube. O
//     cliente não tem como responder isso sem uma ida à rede que a própria
//     regra faria de novo. É DE PROPÓSITO que fica só no servidor: é o caso
//     que sobra quando tudo aqui passa, e é por isso que "passou aqui e o
//     servidor negou" pode ser reportado como autorização com segurança.
//   - `criadoEm`/`atualizadoEm is timestamp`: o adaptador sempre os envia como
//     `FieldValue.serverTimestamp()`, nunca a partir do modelo. Não há entrada
//     do usuário para validar (ver o comentário longo em
//     `repositorio_evo_firestore.dart`).
//   - `camposPermitidos*()`: o conjunto de chaves é fechado pelo tipo — quem
//     monta o mapa é `paraFirestoreSem*()`, não a tela. Um campo a mais só
//     entraria por uma mudança de código nesses métodos, que é onde a lista do
//     servidor deve ser conferida.
//   - O INTERIOR de `estadoInicial.slots` e de `atribuicoes`: o servidor também
//     não valida (ver LIMITAÇÃO CONHECIDA no topo de `firestore.rules`).
//     Espelhar mais do que o servidor exige criaria o erro simétrico — o app
//     recusaria um documento que o servidor aceitaria.
//
// -----------------------------------------------------------------------------
// `size()` DAS RULES CONTA UNIDADES UTF-16 — medido, não suposto
// -----------------------------------------------------------------------------
// `String.length` do Dart conta unidades UTF-16. Se `size()` das Security Rules
// contasse bytes UTF-8 ou pontos de código, o espelho divergiria justamente nos
// nomes acentuados que este produto tem de sobra. Medido no emulador contra a
// regra real:
//
//   'a' x24  (24 UTF-16, 24 bytes) .... ACEITO
//   'a' x25  ............................ NEGADO
//   'é' x24  (24 UTF-16, 48 bytes) .... ACEITO   -> não são bytes
//   'é' x25  ............................ NEGADO
//   emoji x12 (12 pontos, 24 UTF-16) .. ACEITO
//   emoji x13 (13 pontos, 26 UTF-16) .. NEGADO   -> não são pontos de código
//
// Ou seja: `s.length` do Dart é o espelho exato de `s.size()` da regra. Não
// trocar por `characters.length` / `runes.length` "para ficar mais correto" —
// ficaria mais correto para um humano e errado para o servidor.
// =============================================================================

/// Slots válidos como chave de mapa: `'0'`..`'35'`. Espelha as três listas
/// desenroladas de `firestore.rules` (`rotulosDoMapaValidos`,
/// `estadoInicialValido`, `atribuicoesValidas`) — as três usam a MESMA lista,
/// e o teto de 36 vem do orçamento de expressões da regra, não do produto (ver
/// o bloco ORÇAMENTO DE EXPRESSÕES lá).
const int maxSlots = maxLinhasOuColunas * maxLinhasOuColunas;

/// Teto de `nome` em `pelotoes` — espelha `textoAte(next().nome, 60)`.
const int maxCaracteresNomePelotao = 60;

/// Teto de `nome` em `evolucoes` — espelha `textoAte(next().nome, 80)`.
const int maxCaracteresNomeEvolucao = 80;

/// Teto de `nome` em `partes` — espelha `textoAte(next().nome, 60)`.
const int maxCaracteresNomeParte = 60;

/// Faixa de `campo.larguraCelulas`/`alturaCelulas` — espelha `campoValido()`.
const int minCelulasCampo = 1;
const int maxCelulasCampo = 200;

/// Faixa de `ordem` em `partes` — espelha `parteValida()`.
const double minOrdemParte = -1000000000;
const double maxOrdemParte = 1000000000;

/// Espelha `pelotaoValido()` + `rotulosValidos()` de `firestore.rules`.
///
/// Devolve `null` quando o documento passaria na regra, ou uma frase pronta
/// dizendo QUAL verificação falhou — nunca "dado inválido" genérico.
String? validarPelotao(PelotaoDoc doc, {required String clubId}) {
  // EXTRA (não está na regra): a regra só exige `clubId is string`, e string
  // vazia passaria nela — mas aí `membroAtivo('')` negaria adiante, sem dizer
  // por quê. Um clubId vazio aqui significa que o bootstrap do clube não rodou
  // ou rodou e não devolveu id; nomear isso é mais útil que deixar o servidor
  // responder com um `permission-denied` mudo.
  final String? falhaClube = _validarClubId(clubId);
  if (falhaClube != null) return falhaClube;

  // `textoAte(next().nome, 60)`
  if (doc.nome.length > maxCaracteresNomePelotao) {
    return 'O nome do pelotão tem ${doc.nome.length} caracteres; '
        'o máximo é $maxCaracteresNomePelotao.';
  }

  // `next().linhas is int && >= 1 && <= 6`
  if (doc.linhas < 1 || doc.linhas > maxLinhasOuColunas) {
    return 'linhas=${doc.linhas} está fora da faixa permitida '
        '(1 a $maxLinhasOuColunas).';
  }

  // `next().colunas is int && >= 1 && <= 6`
  if (doc.colunas < 1 || doc.colunas > maxLinhasOuColunas) {
    return 'colunas=${doc.colunas} está fora da faixa permitida '
        '(1 a $maxLinhasOuColunas).';
  }

  // `rotulosValidos()` -> `rotulosDoMapaValidos(r)`:
  // primeiro o `hasOnly` das chaves, depois o teto de tamanho de cada valor —
  // mesma ordem da regra.
  for (final String chave in doc.rotulos.keys) {
    final String? falhaChave = _validarChaveDeSlot(chave, 'rotulos');
    if (falhaChave != null) return falhaChave;
  }
  for (final MapEntry<String, String> e in doc.rotulos.entries) {
    if (e.value.length > maxCaracteresRotulo) {
      return 'O rótulo do slot ${e.key} tem ${e.value.length} caracteres; '
          'o máximo é $maxCaracteresRotulo.';
    }
  }

  return null;
}

/// Espelha `evolucaoValida()` + `estadoInicialValido()` + `campoValido()`.
String? validarEvolucao(EvolucaoDoc doc, {required String clubId}) {
  final String? falhaClube = _validarClubId(clubId);
  if (falhaClube != null) return falhaClube;

  // `next().pelotaoId is string` — vazio passaria na regra, mas uma evolução
  // sem pelotão não tem como reinterpretar índice de slot nenhum, e
  // `pelotaoId` é IMUTÁVEL depois do create (ver o comentário da regra de
  // update de `evolucoes`): gravar vazio é um erro que não dá para desfazer
  // sem apagar a evolução e as partes junto.
  if (doc.pelotaoId.isEmpty) {
    return 'Esta evolução não está ligada a nenhum pelotão '
        '(pelotaoId vazio), e isso não pode ser corrigido depois.';
  }

  // `textoAte(next().nome, 80)`
  if (doc.nome.length > maxCaracteresNomeEvolucao) {
    return 'O nome da evolução tem ${doc.nome.length} caracteres; '
        'o máximo é $maxCaracteresNomeEvolucao.';
  }

  // `next().versaoCatalogo is int && >= 1`
  if (doc.versaoCatalogo < 1) {
    return 'versaoCatalogo=${doc.versaoCatalogo} é inválida (mínimo 1).';
  }

  // `estadoInicialValido()`
  final String? falhaEstado = _validarEstadoInicial(doc.estadoInicial);
  if (falhaEstado != null) return falhaEstado;

  // `campoValido()`
  final CampoDoc? campo = doc.campo;
  if (campo != null) {
    if (campo.larguraCelulas < minCelulasCampo ||
        campo.larguraCelulas > maxCelulasCampo) {
      return 'A largura do campo (${campo.larguraCelulas} células) está fora '
          'da faixa permitida ($minCelulasCampo a $maxCelulasCampo).';
    }
    if (campo.alturaCelulas < minCelulasCampo ||
        campo.alturaCelulas > maxCelulasCampo) {
      return 'A altura do campo (${campo.alturaCelulas} células) está fora '
          'da faixa permitida ($minCelulasCampo a $maxCelulasCampo).';
    }
  }

  return null;
}

/// Espelha `parteValida()` + `atribuicoesValidas()`.
String? validarParte(ParteDoc doc, {required String clubId}) {
  final String? falhaClube = _validarClubId(clubId);
  if (falhaClube != null) return falhaClube;

  // `next().evolucaoId is string` — mesma lógica do `pelotaoId` acima:
  // imutável depois do create.
  if (doc.evolucaoId.isEmpty) {
    return 'Esta parte não está ligada a nenhuma evolução '
        '(evolucaoId vazio), e isso não pode ser corrigido depois.';
  }

  // `next().ordem is number && >= -1e9 && <= 1e9`. A regra exclui NaN de graça
  // (toda comparação com NaN é falsa); aqui isso vira `isFinite`, que cobre
  // NaN e ±infinito — os três reprovariam lá.
  if (!doc.ordem.isFinite) {
    return 'A ordem desta parte não é um número finito (${doc.ordem}).';
  }
  if (doc.ordem < minOrdemParte || doc.ordem > maxOrdemParte) {
    return 'A ordem desta parte (${doc.ordem}) está fora da faixa permitida. '
        'Reordenar as partes normaliza os valores.';
  }

  // `(!('nome' in next()) || textoAte(next().nome, 60))`
  final String? nome = doc.nome;
  if (nome != null && nome.length > maxCaracteresNomeParte) {
    return 'O nome da parte tem ${nome.length} caracteres; '
        'o máximo é $maxCaracteresNomeParte.';
  }

  // `atribuicoesValidas()`
  for (final String chave in doc.atribuicoes.keys) {
    final String? falhaChave = _validarChaveDeSlot(chave, 'atribuicoes');
    if (falhaChave != null) return falhaChave;
  }

  return null;
}

// -- internos ----------------------------------------------------------------

String? _validarClubId(String clubId) {
  if (clubId.isEmpty) {
    return 'O app não sabe a qual clube isto pertence — entre e saia da conta '
        'para refazer a configuração do clube.';
  }
  return null;
}

/// Espelha o `keys().hasOnly(['0', ..., '35'])` das três coleções. A regra
/// aceita QUALQUER chave de 0 a 35, independente de `linhas × colunas` — um
/// grid encolhido que ainda carregue o slot 30 passa. Não apertar isto aqui:
/// seria o espelho recusando o que o servidor aceita.
String? _validarChaveDeSlot(String chave, String campo) {
  final int? indice = int.tryParse(chave);
  if (indice == null || indice < 0 || indice >= maxSlots) {
    return 'O campo `$campo` tem a chave "$chave", que não é um índice de '
        'slot válido (0 a ${maxSlots - 1}).';
  }
  // `int.tryParse` aceita '+7', ' 7' e '07', que viram 7 — mas a regra compara
  // a chave como TEXTO contra a lista, e '07' não está nela.
  if (chave != indice.toString()) {
    return 'O campo `$campo` tem a chave "$chave", que não está na forma '
        'esperada ("$indice").';
  }
  return null;
}

/// Espelha `estadoInicialValido()`: `estadoInicial` é um mapa com a chave
/// `slots` e só ela; `slots` é mapa chaveado por índice de slot.
String? _validarEstadoInicial(Map<String, dynamic> estadoInicial) {
  for (final String chave in estadoInicial.keys) {
    if (chave != 'slots') {
      return 'O estado inicial tem um campo inesperado (`$chave`); '
          'só `slots` é aceito.';
    }
  }
  final Object? slots = estadoInicial['slots'];
  if (slots is! Map) {
    return 'O estado inicial não tem o mapa `slots`.';
  }
  for (final Object? chave in slots.keys) {
    final String? falha = _validarChaveDeSlot(
      chave.toString(),
      'estadoInicial.slots',
    );
    if (falha != null) return falha;
  }
  return null;
}
