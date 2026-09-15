import 'package:cloud_firestore/cloud_firestore.dart';

/// Toda falha de escrita/leitura no Firestore, fechada por construção
/// (`sealed`): a tela é OBRIGADA pelo compilador a ter um ramo para cada
/// caso hoje — quando a colaboração real entrar (trava de verdade em vez
/// de [TravaSempreMinha]), não há erro novo a "descobrir" em produção, só
/// um ramo que deixa de ser hipotético.
sealed class FalhaPersistencia {
  const FalhaPersistencia();
}

/// A trava de edição pertence a outra pessoa. Não é produzida por
/// [TravaSempreMinha] hoje (ela sempre concede) — existe no tipo para que o
/// dia em que uma trava real entrar, nenhuma tela precise ser reaberta só
/// para aprender a lidar com este caso.
final class SemTrava extends FalhaPersistencia {
  const SemTrava();
}

/// `permission-denied` — a Security Rule recusou. Em single-user isso quase
/// sempre significa sessão expirada/clube errado, não "servidor com bug".
final class SemPermissao extends FalhaPersistencia {
  const SemPermissao();
}

/// Sem conectividade, ou o servidor está temporariamente inalcançável —
/// estado NORMAL em mobile/web (túnel, elevador, wifi caindo), não um erro
/// de verdade. A escrita fica pendente localmente (ver
/// `EvolucaoDoc.pendente`/`ParteDoc.pendente`/`PelotaoDoc.pendente`, vindos
/// de `snapshot.metadata.hasPendingWrites`) e será reenviada quando a
/// conexão voltar — a UI não deve tratar isto como falha definitiva.
final class ForaDoAr extends FalhaPersistencia {
  const ForaDoAr();
}

/// O documento não passou na validação do servidor (`invalid-argument`,
/// `failed-precondition`, ou qualquer erro de formatação detectado antes de
/// chegar lá). Diferente de [ForaDoAr]: repetir a mesma escrita sem mudar
/// nada não resolve.
final class DocumentoInvalido extends FalhaPersistencia {
  const DocumentoInvalido();
}

/// O documento passou de ~1 MiB (limite de tamanho de documento do
/// Firestore). Em `partes`/`pelotoes` isso só aconteceria com um volume de
/// dado muito fora do desenhado (36 slots ocupam uma fração minúscula
/// disso) — mas o tipo existe para não confundir com [DocumentoInvalido]
/// genérico se um dia acontecer.
final class LimiteDeTamanho extends FalhaPersistencia {
  const LimiteDeTamanho();
}

/// `resource-exhausted`. NO PLANO SPARK ISTO SIGNIFICA COTA DIÁRIA
/// ESTOURADA — o projeto inteiro para de aceitar leituras/escritas até por
/// volta da meia-noite (fuso Pacífico, hora do Google, não a local). A UI
/// que recebe isto TEM que dizer exatamente isso, nunca "erro desconhecido"
/// nem convidar a pessoa a "tentar de novo em alguns segundos" — tentar de
/// novo em 10 segundos não muda nada até a cota resetar.
final class CotaEstourada extends FalhaPersistencia {
  const CotaEstourada();
}

/// Traduz uma exceção capturada do SDK do Firebase para o tipo fechado
/// acima. Ponto único de mapeamento: se o SDK inventar um código novo, é
/// aqui — e só aqui — que o app aprende a lidar com ele.
FalhaPersistencia falhaPersistenciaDe(Object erro) {
  if (erro is FirebaseException) {
    switch (erro.code) {
      case 'permission-denied':
        return const SemPermissao();

      case 'unavailable':
      case 'deadline-exceeded':
      case 'cancelled':
      case 'aborted':
      case 'internal':
      case 'unknown':
        return const ForaDoAr();

      case 'resource-exhausted':
        return const CotaEstourada();

      case 'invalid-argument':
      case 'failed-precondition':
      case 'out-of-range':
      case 'not-found':
        // O SDK não distingue "documento grande demais" de outro erro de
        // validação por código — só pela MENSAGEM. `contains` em vez de
        // igualdade porque a mensagem completa varia por SDK/versão; o
        // texto abaixo é o núcleo estável observado.
        final String mensagem = erro.message?.toLowerCase() ?? '';
        if (mensagem.contains('exceeds the maximum') ||
            mensagem.contains('too large') ||
            mensagem.contains('longer than')) {
          return const LimiteDeTamanho();
        }
        return const DocumentoInvalido();

      default:
        // Código do SDK que este mapeamento ainda não conhece. Cai em
        // DocumentoInvalido (não ForaDoAr) DE PROPÓSITO: assumir "é
        // transitório, vai passar sozinho" para um erro desconhecido é o
        // tipo de otimismo que deixa a pessoa esperando pra sempre; tratar
        // como "algo está errado com isto, veja os detalhes" é mais seguro
        // por padrão, mesmo que a etiqueta não seja perfeita.
        return const DocumentoInvalido();
    }
  }
  // Erro que não veio do SDK do Firestore (ex.: falha de inicialização do
  // `firebase_core`, ou algo do app mesmo). Mesma lógica do `default`
  // acima: não presumir "é transitório".
  return const DocumentoInvalido();
}
