# Testes das Security Rules

Suíte que exercita [`firestore.rules`](../../firestore.rules) contra o
**emulador local** do Firestore. Nenhum teste aqui toca um projeto Firebase
real, e o harness não precisa de nenhum: não há `.firebaserc` no repositório e o
project id é um valor qualquer passado na linha de comando.

Harness Node isolado, deliberadamente **fora** do `pubspec.yaml`: não entra em
`dart test` nem em `flutter test`, e nenhuma dependência de Firebase é
adicionada ao app por causa dele.

## Pré-requisitos

- Node 18+ e `firebase-tools` (`firebase --version`)
- Java 11+ (o emulador do Firestore roda na JVM)

## Como rodar

Em um comando só, a partir da raiz do repositório:

```bash
cd test/rules && npm install && cd ../..

NODE_BIN="$(dirname "$(command -v node)")"
firebase emulators:exec --only firestore --project evo-rules-test \
  "PATH=$NODE_BIN:\$PATH npm --prefix test/rules test"
```

O `PATH=$NODE_BIN:...` não é frescura: o `firebase` distribuído como binário
standalone injeta um `node` próprio (empacotado com `pkg`) no início do `PATH`
do script filho, e esse `node` não aceita `--test`. Prefixar o Node real
resolve. Quem usa o `firebase-tools` instalado via npm pode omitir o prefixo.

Ou, com o emulador de pé em outro terminal:

```bash
# terminal 1
firebase emulators:start --only firestore --project evo-rules-test

# terminal 2
cd test/rules && npm install && npm test
```

## O que a suíte cobre

99 testes. Além do caminho feliz (sem ele, uma regra que negasse tudo passaria
em todos os testes negativos):

- **o caminho de escrita REAL do cliente** — a transação `get` + `set` que
  `RepositorioEvoFirestore.gravarPelotao`/`gravarEvolucao` executa, replicada
  passo a passo, em vez de um documento montado pronto. Ver o bloco "caminho de
  escrita real do cliente" e o porquê logo abaixo;

- não autenticado bloqueado em leitura, consulta, criação, update e delete das
  quatro coleções;
- usuário de outro clube bloqueado, inclusive contra enumerar por consulta e
  contra criar documento carimbado com o `clubId` alheio;
- clube inexistente falha fechado (não libera o filho);
- rótulo de 25 caracteres rejeitado — no create **e** no update, no primeiro
  slot e no último;
- rótulo como mapa, lista, número ou nulo rejeitado (é o buraco que o
  `is string` fecha: um mapa de até 24 chaves passaria só no `size()`);
- chave de slot fora de `0..35` rejeitada em `rotulos`,
  `estadoInicial.slots` e `atribuicoes`, inclusive rótulo usado como chave;
- campo desconhecido (`idade`, `telefone`, `nascimento`) rejeitado no create e
  no update das quatro coleções;
- `photoURL` rejeitado em todas as coleções;
- `nomeExibicao` dentro de `membros` rejeitado, no create e no update;
- nome de 61 caracteres rejeitado (81 em `evolucoes`), com o limite inclusivo
  testado do lado que passa;
- `campo` como texto livre rejeitado;
- **`membrosAtivos` com duas chaves rejeitado no create** — o teste que prova a
  trava de single-user;
- `ordem` NaN, Infinity, string e fora de faixa rejeitadas;
- `clubId` e `evolucaoId` imutáveis no update;
- catch-all nega coleção não modelada, `usuarios/{uid}`, subcoleção e coleção
  de eventos/analytics;
- **runbook de exclusão** (`docs/DADOS.md` 4.1): a ordem `partes → evolucoes →
  pelotoes → clube` é permitida do início ao fim; a variante de emergência
  (pelotões primeiro) não trava o resto; e apagar o clube primeiro deixa os
  filhos permanentemente inalcançáveis — o incidente que o Domo já teve, aqui
  congelado como teste em vez de como recomendação;
- as quatro consultas de que o export client-side depende.

### Por que existe um bloco que replica a sequência do cliente

Todo o resto da suíte chama `setDoc`/`updateDoc` com um documento montado à mão.
Isso exercita a regra de **escrita**, e é a razão de 90 testes verdes terem
convivido com um bug que impedia criar qualquer pelotão: a regra que estava
errada era a de **leitura**, e nenhum teste lia um documento **inexistente**.

O app decide create vs update fazendo `tx.get(ref)` dentro de uma transação
(para nunca reenviar `criadoEm`, que é imutável). No create esse `get` cai num
documento que ainda não existe, onde `resource` é null do lado da regra — e
`allow read: if membroAtivo(resource.data.clubId)` dava erro de avaliação ali,
negando. A transação abortava antes de a regra de create rodar, com qualquer
grid e qualquer rótulo.

Moral para quem for acrescentar teste aqui: **um documento montado pelo teste
não é o que o app envia, e a sequência importa tanto quanto o conteúdo.** Quando
o caminho do cliente mudar, este bloco muda junto.

As fixtures são **100% fictícias** ("Clube Exemplo", "Alfa", "Bravo",
"Charlie"). O repositório é público: nenhum apelido real, nome de clube real,
uid ou e-mail entra aqui, nem temporariamente — o git não esquece um arquivo
removido depois.

## Orçamento de expressões

O Firestore corta a avaliação de uma regra em **1.000 expressões por request**.
Como Security Rules não têm laço, os 36 slots de `rotulos` são 36 verificações
desenroladas, e esse número disputa o mesmo orçamento com todo o resto da regra
(autorização por `get()` no clube, allowlist de campos, validação de grid e
timestamps).

Isto **não é estimativa**. Foi medido no emulador, gerando variantes da regra
real com N verificações de slot e escrevendo o pior caso possível — os 36 slots
preenchidos com 24 caracteres cada, nenhum curto-circuito por ausência — até o
emulador responder `maximum of 1000 expressions to evaluate has been reached`:

| Medida | Valor |
|---|---|
| Capacidade máxima da regra atual | **44 slots** |
| Em uso hoje (6×6) | **36 slots** |
| Folga | **8 slots (~14% do orçamento)** |
| Custo por slot (derivado) | ~17 expressões |
| Custo do resto da regra de `pelotoes` (derivado) | ~240 expressões |
| Consumo no pior caso de 36 slots | **~855 de 1.000** |

As duas primeiras linhas são medidas diretas (o ponto exato em que a escrita
passa a ser recusada pelo limite). As demais são derivadas do modelo linear
`custo = base + 17 × slots`, calibrado com uma regra mínima que isola as
verificações de slot — trate-as como ±20 expressões, não como exatas.

Três consequências que valem mais que os números:

1. **Um grid 7×7 (49 slots) não cabe.** Aumentar o grid não é mexer em dois
   números de `linhas`/`colunas`: exige reformular a validação.
2. **A formulação importa mais que o teto.** A primeira versão desta regra
   usava `!(slot in r) || (r[slot] is string && r[slot].size() <= 24)` e
   estourava o limite **com os 36 slots em uso** — capacidade medida de 35.
   Trocar para `r.get(slot, '') is string && r.get(slot, '').size() <= 24`
   subiu a capacidade para 44 sem enfraquecer a validação. Uma variante que
   troca o `is string` por um guard de concatenação chega a 67, ao custo de
   divergir do texto de [`docs/DADOS.md`](../../docs/DADOS.md) 3.2.
3. **A folga encolhe sozinha.** Todo campo novo em `pelotoes` e toda validação
   nova consomem do mesmo orçamento. O teste *"os 36 slots cheios com 24
   caracteres cabem no orçamento de expressões"* existe para que isso apareça
   como teste vermelho aqui, e não como escrita negada em produção com 36
   crianças já cadastradas.

Para repetir a medição, o caminho é o mesmo: gerar variantes da regra com N
verificações, subir o emulador e procurar por busca binária o maior N que ainda
aceita a escrita de pior caso. Cuidado com um detalhe que confunde a leitura:
acima de ~45 verificações encadeadas o compilador de regras passa a recusar por
*"expression is too complex to evaluate safely"*, que é um limite **estático** e
diferente do de 1.000 — quebrar as verificações em funções de 9 contorna o
limite estático e deixa o limite de execução aparecer sozinho.
