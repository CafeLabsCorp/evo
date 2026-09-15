# Dados pessoais no Evo Lab

**Criado em 14/09/2026.** Este arquivo é o inventário de *todo* dado pessoal
que o Evo Lab grava, em qualquer lugar, e o registro de **por que** cada campo
existe, com que base legal pretendida, por quanto tempo e como se apaga.

Ele existe antes do primeiro documento ser gravado, e não depois, por um motivo
prático: o código pode ser lido em qualquer mês para descobrir *o que* o produto
guarda — mas nenhuma leitura de código em outubro revela *por que* um campo
entrou em setembro. Termos de Uso e Política de Privacidade são reconstituíveis;
a intenção por trás do schema, não.

Este repositório é **público**. Portanto este arquivo descreve **estrutura**,
nunca **conteúdo**: não há aqui nenhum apelido real, nome de clube real, uid ou
e-mail. Nesta janela o produto roda com apelidos fictícios (`Clube Exemplo`,
`Alfa`, `Bravo`); dado real só entra depois que o export existir e a direção do
clube for avisada.

Complementa a seção **Privacidade** do [`README.md`](../README.md), que continua
valendo na íntegra e não é contradita em nenhum ponto deste documento.

---

## 1. Enquadramento

| Papel | Quem | Por quê |
|---|---|---|
| **Controlador** | O clube / o instrutor que usa o app | É quem decide quais pessoas entram no pelotão, com que rótulo, e para qual finalidade |
| **Operadora** | Café Labs | Fornece a ferramenta e trata os dados por conta do controlador, nos limites desta tabela |
| **Titulares** | Os membros do pelotão (frequentemente menores de idade) e os instrutores que fazem login | — |

A finalidade é **uma só**: planejar e conferir evoluções de ordem unida. Não
existe finalidade secundária declarada, e não deve passar a existir sem entrar
nesta tabela primeiro.

Três declarações que sustentam esse enquadramento — se qualquer uma deixar de
ser verdadeira, o enquadramento cai junto:

1. A Café Labs **não usa o rótulo de um membro para finalidade própria** —
   nem para produto, nem para métrica, nem para analytics. Não há GA4 no
   projeto e não há evento de telemetria que carregue rótulo.
2. A Café Labs **não retém rótulo fora do alcance do instrutor**: tudo que o
   app grava está dentro do clube do instrutor e é apagável por ele
   (seção 4), sem intermediação da Café Labs.
3. A Café Labs **não expõe rótulo fora do clube sem ação do instrutor**. Não
   existe evolução pública, link compartilhável nem diretório de clubes.

### Nesta janela, essa estrutura colapsa — e isso está registrado de propósito

Enquanto o produto for single-user, **a mesma pessoa é sócio da operadora e
instrutor do clube**. Controlador e operadora são o mesmo indivíduo, e a
separação de papéis acima não protege ninguém de nada: não há contraparte para
cobrar a outra.

Registrar isso importa porque a estrutura **passa a ter função de verdade no
instante em que existir um instrutor que não seja sócio da Café Labs** — aí ela
deixa de ser desenho e vira a divisão real de responsabilidade entre quem
decide (o clube) e quem opera (a Café Labs). Esse instante é um dos quatro
gatilhos da seção 8.

---

## 2. Inventário

Legenda de "dado pessoal?": **sim (direto)** = identifica a pessoa por si;
**sim (pseudônimo)** = identifica indiretamente ou mediante informação
adicional — pseudonimização **não** tira o dado do alcance da LGPD; **não** =
não se refere a pessoa natural identificada ou identificável.

### 2.1 Firebase Auth — fora do Firestore, fora do Brasil

Esta é a linha que a antecipação do login criou, e ela merece destaque:
**o e-mail e o nome do instrutor no Firebase Auth são o primeiro dado pessoal
real do produto — eles chegam antes dos apelidos.** Os apelidos ainda são
fictícios nesta janela; o e-mail do primeiro login, não.

O Firebase Authentication **não é regionalizável**. A documentação do Google é
explícita: *"The Firebase Authentication service is run only from US data
centers. As a result, Firebase Authentication processes data exclusively in the
United States."* Não existe seletor de região, diferentemente do Firestore (que
está em `southamerica-east1`, São Paulo). Ou seja: **o Firestore do Evo Lab está
no Brasil; a autenticação dele não está, e não tem como estar.**

| Campo | Titular | Dado pessoal? | Finalidade | Base legal pretendida | Retenção | Gatilho de exclusão |
|---|---|---|---|---|---|---|
| `uid` | Instrutor (adulto) | sim (pseudônimo) | Vincular a conta ao clube e autorizar leitura/escrita | **a definir em 28/09** — candidata: execução de contrato (art. 7º V) | Enquanto a conta existir | Exclusão da conta de Auth (último passo do runbook, seção 4) |
| `email` | Instrutor | **sim (direto)** | Identificar a conta Google que faz login | **a definir em 28/09** | Até a exclusão do usuário; o Google remove de sistemas vivos e de backup em até **180 dias** depois | Exclusão da conta de Auth |
| `displayName` | Instrutor | **sim (direto)** — na prática costuma ser o nome civil | Identificar o dono do clube | **a definir em 28/09** | Idem | Idem |
| `photoURL` | Instrutor | sim (direto) | **Nenhuma** — o app não deve ler nem persistir | — | — | — |
| IP e user-agent de login (logs do provedor) | Instrutor | sim (direto) | Segurança e antiabuso do provedor | Legítimo interesse do provedor | "Algumas semanas", segundo o Google | Fora do controle da Café Labs |

Transferência internacional: os mecanismos que o Google oferece são o **DPA do
Firebase** e as **Standard Contractual Clauses** publicadas em
`firebase.google.com/terms/firebase-sccs` (a certificação de Data Privacy
Framework cobre EU/UK/Suíça, não o Brasil). A base específica da LGPD para essa
transferência — cláusulas contratuais (art. 33, II) ou consentimento específico
e em destaque (art. 33, VIII) — **fica a definir em 28/09**, junto com a
Política. O que não fica em aberto é o fato: **este dado sai do Brasil, e isso
precisa ser dito com o nome do provedor e do país na Política, não diluído em
"compartilhamos com terceiros".**

### 2.2 `clubes/{clubId}`

O documento de autorização. É ele que as regras dos filhos consultam para
decidir se alguém pode ler ou escrever — por isso é o **último** a ser apagado.

| Campo | Titular | Dado pessoal? | Finalidade | Base legal pretendida | Retenção | Gatilho de exclusão |
|---|---|---|---|---|---|---|
| `nome` | O clube (entidade) | não, isoladamente | Identificar o clube na interface | — | Enquanto o clube existir | Exclusão do clube |
| `dono` (uid) | Instrutor | sim (pseudônimo) | Definir quem pode apagar o clube | Execução de contrato | Idem | Idem |
| `membros{uid: {estado, papel, nomeExibicao}}` | Instrutor | **sim (direto)** — `nomeExibicao` vem do perfil Google | Exibir e aprovar quem participa da diretoria | **a definir em 28/09** | Idem | Idem |
| `membrosAtivos{uid: true}` | Instrutor | sim (pseudônimo) | Índice consultado pelas Security Rules (evita ler o mapa aninhado) | Execução de contrato | Idem | Idem |
| `criadoEm` | — | não | Auditoria | — | Idem | Idem |

Nesta versão os dois mapas existem com **uma entrada só**. Isso é decisão de
arquitetura, não acidente: manter a forma desde já é o que torna a migração para
clubes multiusuário gratuita. Do ponto de vista de dados, um mapa de um elemento
com o uid do próprio dono não acrescenta exposição nenhuma.

Uma ressalva honesta sobre `nomeExibicao`: ele existe para a tela de aprovação
de convite — que **não existe nesta versão**. Enquanto for single-user, ele é o
nome civil de um adulto guardado para uma funcionalidade ainda inexistente.
Manter a chave do mapa é o que importa para a migração; o valor
`nomeExibicao` pode ficar de fora até o convite existir, sem custo nenhum de
migração depois (é valor de mapa, não campo de documento). Decisão do `backend`
de mantê-lo é legítima e está registrada; a alternativa minimizadora fica aqui
anotada para quem revisar.

### 2.3 `pelotoes/{id}` — a coleção sensível

| Campo | Titular | Dado pessoal? | Finalidade | Base legal pretendida | Retenção | Gatilho de exclusão |
|---|---|---|---|---|---|---|
| `rotulos{"<slot>": string ≤24}` | **Membro do pelotão — frequentemente menor de idade** | **sim (pseudônimo)** | Saber quem ocupa cada posição do grid ao planejar a evolução | **LGPD art. 14 — a definir em 28/09.** Nesta janela não existe rótulo real, só fictício | Enquanto o pelotão existir | Exclusão do pelotão, ou o instrutor limpar/trocar o rótulo a qualquer momento |
| `nome` | — | não *(campo livre — ver 3.3)* | Identificar o pelotão | — | Idem | Idem |
| `clubId`, `linhas`, `colunas`, `criadoEm`, `atualizadoEm` | — | não | Estrutura do grid e vínculo ao clube | — | Idem | Idem |

Duas coisas precisam ficar explícitas aqui, porque é fácil se enganar sozinho:

- **Apelido é pseudonimização, não anonimização.** Um rótulo curto que o
  instrutor consegue associar a uma pessoa é dado pessoal, e o art. 14 continua
  se aplicando. O que a minimização faz é reduzir drasticamente o dano de um
  vazamento — não tirar o produto do regime.
- **Lista de apelidos + nome de clube de Desbravadores permite inferir
  convicção religiosa**, que é dado sensível (art. 5º, II). É por isso que a
  lista de campos proibidos da seção 3 é mais rígida do que pareceria
  necessário para um app de coreografia, e é por isso que não existe evolução
  pública nem seed com dado real neste repositório.

Teto de **36 slots** (6×6). O rótulo vive **só** aqui — nunca como ID de
documento, nunca em path, nunca em subcoleção por pessoa.

### 2.4 `evolucoes/{id}` e `partes/{id}`

| Path | Campo | Dado pessoal? | Observação |
|---|---|---|---|
| `evolucoes` | `nome` | não *(campo livre — ver 3.3)* | — |
| `evolucoes` | `campo?` | não *(campo livre — ver 3.3)* | Maior risco de dado pessoal acidental do schema inteiro |
| `evolucoes` | `estadoInicial{slots{...}}` | **não, por construção** | Referencia **índice de slot**, nunca rótulo |
| `evolucoes` | `clubId`, `pelotaoId`, `versaoCatalogo`, `criadoEm`, `atualizadoEm` | não | — |
| `partes` | `atribuicoes{...}` | **não, por construção** | Chaveado por **índice de slot**, nunca por rótulo. A regra **não** valida o interior (seção 7) |
| `partes` | `ordem`, `nome?` | não *(campo livre — ver 3.3)* | `ordem` é numérico, para reordenação fracionária |
| `partes` | `clubId`, `evolucaoId`, `atualizadoEm` | não | — |

A propriedade que faz essas duas coleções não conterem dado pessoal é única e
vale a pena nomear: **posições são referenciadas por índice de slot, nunca pelo
rótulo.** Se um dia uma atribuição passar a guardar o texto do rótulo, essas
duas linhas da tabela mudam de classificação e o runbook de exclusão muda junto.

### 2.5 Fora do Firestore

| Onde | O quê | Titular | Dado pessoal? | Observação |
|---|---|---|---|---|
| Navegador do instrutor | Token de sessão do Firebase Auth (IndexedDB/localStorage) | Instrutor | sim (pseudônimo) | **Estritamente necessário** para manter o login. Não é cookie de rastreio |
| Hospedagem estática do preview | Logs de acesso (IP, user-agent) | Visitante | sim (direto) | Do provedor de hospedagem, não da Café Labs. Fora do nosso controle |
| Firebase Analytics / GA4 | — | — | — | **Desligado por decisão de compliance.** Não existe no projeto |
| Cloud Storage | — | — | — | **O bucket nunca foi criado.** Upload de arquivo é tecnicamente impossível, não apenas proibido por política |

Consequência direta e útil: **esta versão não precisa de banner de cookies.** O
único armazenamento no navegador é o token de sessão, estritamente necessário
para a funcionalidade, e não há nenhum tracker de terceiro rodando antes de o
usuário agir. Isso deixa de valer no instante em que qualquer analytics,
pixel ou embed de terceiro entrar na página — o que é caso do gatilho 4.

---

## 3. Campos proibidos, e o mecanismo que impõe cada um

### 3.1 A lista integral

Nenhum destes pode existir em nenhuma coleção, em nenhuma versão, sem passar
antes por esta tabela e por uma base legal escrita:

1. Data de nascimento, idade ou faixa etária de membro
2. Foto, imagem, avatar ou qualquer arquivo binário
3. Nome civil completo de membro do pelotão
4. Documento de identificação (CPF, RG, matrícula, número de carteirinha)
5. Contato de membro (telefone, e-mail, endereço, rede social)
6. Dado de saúde: restrição alimentar, alergia, medicação, laudo, limitação física
7. Dado religioso explícito: batismo, classe, cargo eclesiástico, situação de membresia
8. Dado biométrico
9. Geolocalização (do dispositivo ou da pessoa)
10. Frequência, presença ou pontualidade por pessoa
11. Avaliação, nota ou desempenho por pessoa
12. Campo de texto livre por pessoa (observação, anotação, comentário)
13. Parentesco, responsável ou contato de emergência
14. Qualquer identificador externo que ligue o slot a um cadastro de fora do app

Os itens 6, 7 e 10 merecem nota: **frequência por pessoa e qualquer marcador de
membresia religiosa transformam um app de coreografia num registro de conduta de
menor de idade vinculado a convicção religiosa.** É a pior combinação possível
neste produto, e é exatamente a que um "só mais um campinho, é útil pro
instrutor" produz sem que ninguém perceba.

### 3.2 O mecanismo — política e enforcement lado a lado

A proibição acima não vale nada sozinha. O que a impõe é o servidor, em
`firestore.rules`, por **allowlist**: a regra não lista o que é proibido, lista
o que é permitido, e tudo que não estiver na lista é rejeitado na escrita. Um
auditor não precisa acreditar em nenhuma frase desta seção — pode abrir o
arquivo e procurar os nomes abaixo.

**Contrato de nomes** (a regra deve usar exatamente estes; divergência entre
este documento e o arquivo é bug em um dos dois, e precisa ser resolvida no
mesmo commit):

| Mecanismo | Onde | O que impõe |
|---|---|---|
| `camposPermitidosClube()` | `firestore.rules`, match de `clubes/{clubId}` | `request.resource.data.keys().hasOnly([...])` — qualquer campo fora da lista de 2.2 é rejeitado |
| `camposPermitidosPelotao()` | match de `pelotoes/{id}` | Idem para 2.3. É a barreira contra os itens 1–14 entrarem "no pelotão, junto com o rótulo" |
| `camposPermitidosEvolucao()` | match de `evolucoes/{id}` | Idem para 2.4 |
| `camposPermitidosParte()` | match de `partes/{id}` | Idem para 2.4 |
| `rotulosValidos()` | match de `pelotoes/{id}` | `rotulos` é mapa, com `keys().hasOnly([...36 slots...])`, e cada valor validado com `is string && size() <= 24` — **36 verificações desenroladas**, porque Security Rules não têm laço |
| Ausência de bucket de Storage | Console do Firebase | Item 2 (foto/arquivo) é impossível, não só proibido |
| Ausência de `usuarios/{uid}` | Schema | Não existe documento de perfil onde dado de instrutor possa se acumular |
| `noindex` + `robots.txt` | `app/web/` | O preview não é indexável por buscador |

Por que allowlist e não blocklist: uma blocklist protege contra os 14 nomes que
alguém lembrou de escrever; a allowlist protege contra o campo que ninguém
imaginou. O custo é o mesmo, o alcance não.

### 3.3 Duas lacunas de enforcement, declaradas e não disfarçadas

**(a) `maxLength ≤ 24` limita tamanho, não semântica.** `"Maria Eduarda Santos"`
tem 20 caracteres e passa na regra. A validação impede um rótulo virar um campo
de texto livre disfarçado — ela **não** garante que o texto seja um apelido e
não um nome civil. Isso importa na hora de escrever a Política: **não se pode
afirmar que a regra impõe pseudonimização.** O que impõe é a instrução ao
instrutor e o texto da interface. A regra impõe o teto de 24, que é uma barreira
real e verificável — e é só isso que ela impõe.

**(b) Os campos livres não têm teto declarado.** `clubes.nome`,
`pelotoes.nome`, `evolucoes.nome`, `evolucoes.campo` e `partes.nome` são strings
sem limite de tamanho no schema descrito. São exatamente os lugares onde dado
pessoal não planejado chega ("Evolução da turma da fulana", "pátio da casa do
sicrano"). **Recomendação com custo de poucas linhas, enquanto o `mobile` ainda
está implementando:** aplicar às cinco o mesmo mecanismo que `rotulos` já usa —
`is string && size() <= 60` — e, se `campo` tiver um conjunto fechado de valores
possíveis, torná-lo enum em vez de texto. Depois que houver documento gravado,
isso vira migração; agora é uma linha por campo.

---

## 4. Runbook de exclusão

Hard delete, sem soft-delete: o plano Spark não tem Cloud Functions, logo não
existe job de purga que faça um "excluído" virar excluído de verdade depois.
Tudo é apagado pelo cliente, e a ordem importa.

### 4.1 A ordem, e por quê

```
1. partes      where clubId == "<CLUBID>"     → delete cada doc
2. evolucoes   where clubId == "<CLUBID>"     → delete cada doc
3. pelotoes    where clubId == "<CLUBID>"     → delete cada doc   ← os rótulos saem aqui
4. clubes/<CLUBID>                            → delete            ← documento de autorização, por último
5. Conta no Firebase Auth (e-mail e nome)     → delete            ← só depois de 1–4
```

Dois princípios, e eles só se cruzam num ponto:

- **Sensibilidade primeiro:** o dado de menor (`pelotoes.rotulos`) sai antes do
  documento que apenas autoriza (`clubes`). Numa exclusão interrompida no meio,
  o que sobra é vínculo administrativo, não apelido de criança.
- **Autorização por último:** `clubes/{clubId}` é o documento que as regras dos
  filhos consultam para decidir se a exclusão é permitida. **Apagar `clubes`
  antes dos filhos torna `partes`, `evolucoes` e `pelotoes` permanentemente
  inalcançáveis** — ninguém mais consegue nem ler nem apagar, porque a regra
  que autorizaria a operação consulta um documento que não existe mais. Esse não
  é um risco teórico: **é o incidente que o Domo já teve.**

Entre os filhos, a ordem é do mais profundo para o mais raso (`partes` antes de
`evolucoes` antes de `pelotoes`) para que nenhum estado intermediário deixe um
documento apontando para um pai que já sumiu — o que torna uma exclusão
interrompida auditável e retomável.

**Variante de emergência:** se a prioridade for tirar rótulo do ar o mais rápido
possível, `pelotoes` pode ser apagado primeiro. Isso deixa `evolucoes` e
`partes` apontando para um pelotão inexistente, mas **não trava nada**, porque a
regra desses filhos consulta `clubes`, não `pelotoes`. A única restrição
inegociável da ordem é: **`clubes` por último, e a conta de Auth depois dele.**

### 4.2 Por que a conta de Auth é o passo 5, e não o passo 0

As regras exigem `request.auth.uid` correspondendo ao dono do clube. **Excluir a
conta de Auth antes de limpar o Firestore é a mesma classe de incidente que
excluir `clubes` primeiro**, só que pior: o clube inteiro fica órfão, com os
rótulos dentro, e não existe mais nenhuma credencial no mundo capaz de apagá-lo
pelo app — só intervenção manual no console do Firebase.

E o passo 5 não é opcional: **limpar o Firestore não remove o e-mail nem o nome
do instrutor**, que vivem no Auth, nos Estados Unidos. Sem o passo 5, a exclusão
está incompleta, e a resposta a um pedido de eliminação (art. 18, VI) seria
falsa. Depois da exclusão do usuário, o Google remove os dados de sistemas vivos
e de backup em até 180 dias.

### 4.3 Verificação

A exclusão só está concluída quando as quatro consultas por `clubId` voltam
vazias e `clubes/<CLUBID>` não existe mais. Uma exclusão interrompida deve ser
retomada do passo em que parou, nunca reiniciada fora de ordem.

---

## 5. Export — e o fato de que ele é o único backup

O export (JSON, client-side) cumpre **duas funções que normalmente seriam de dois
sistemas diferentes**:

1. **Portabilidade e acesso** (LGPD art. 18, incisos II e V): é como o
   controlador obtém uma cópia legível de tudo que o app guarda dele.
2. **A única recuperação de desastre que existe.** O plano Spark **não tem
   backup gerenciado de Firestore.** Não há point-in-time recovery, não há
   snapshot, não há rollback. Se uma exclusão em cascata rodar errado, ou uma
   escrita corromper dados, **o único caminho de volta é um export que alguém
   baixou antes.**

Consequências que precisam estar escritas em algum lugar, e este é o lugar:

- **Exportar antes de qualquer exclusão em cascata** (seção 4) não é zelo, é o
  procedimento. A exclusão é irreversível por construção.
- **O arquivo exportado sai deste perímetro.** A partir do download, ele está
  no dispositivo do instrutor e a responsabilidade por onde ele é guardado e
  quem o acessa passa a ser dele. Se ele contiver rótulo real, é um arquivo com
  dado de menor num diretório de downloads.
- **Nenhum export com dado real entra neste repositório**, nem como fixture,
  nem como exemplo, nem "temporariamente". O repositório é público e o git não
  esquece um arquivo que foi removido depois.

Import ainda não existe (seção 6) — o que significa que hoje o export permite
*inspecionar* e *guardar*, mas a restauração seria manual.

---

## 6. O que esta versão *não* tem — registrado em 14/09/2026

Esta lista existe para que a ausência seja legível como **escopo decidido**, e
não como esquecimento. Cada item abaixo foi considerado e deixado de fora
conscientemente, nesta data.

| Não tem | Por quê |
|---|---|
| **Convite / `codigos/{CODE}`** | Não há segundo usuário. A superfície de brute-force simplesmente não existe |
| **Aprovação `pendente` → `ativo`** | Sem convite, não há o que aprovar. O mapa `membros` já tem o campo `estado`, com uma entrada só, `ativo` |
| **Trava (lease) de edição por parte** | Sem concorrência não há atropelo. A decisão de manter ou cortar tem checkpoint em 28/09 |
| **Multiusuário de fato** | Single-user por construção. `membros`/`membrosAtivos` existem com uma entrada para tornar a migração gratuita, não porque já funcionem |
| **Exclusão de conta em autoserviço** | O runbook da seção 4 é manual. Isso é aceitável enquanto o único usuário é quem escreveu o runbook — e deixa de ser no gatilho 1 |
| **Termos de Uso** | A redigir em 28/09 |
| **Política de Privacidade** | A redigir em 28/09 |
| **Import** | Só export. Restauração a partir do arquivo é manual hoje |
| **Analytics / medição** | GA4 desligado; a medição via documentos no Firestore ainda **não foi implementada** — não existe nenhuma coleção de eventos. Se vier a existir, entra nesta tabela no mesmo commit, e nunca carrega rótulo |
| **Banner de consentimento de cookies** | Desnecessário nesta versão (ver 2.5), não esquecido |

---

## 7. Riscos residuais declarados

Riscos aceitos conscientemente. Estar nesta lista significa "sabemos, e
decidimos conviver **nesta janela**" — não "está resolvido".

1. **Firebase Auth fora do Brasil.** E-mail e nome do instrutor ficam nos EUA,
   sem opção de região, cobertos pelo DPA e pelas SCCs do Google. O Firestore
   (onde ficam os rótulos) está em `southamerica-east1`. A base LGPD da
   transferência fica a definir em 28/09, mas **a transferência já acontece no
   primeiro login.**

2. **Sem backup no plano Spark.** Nenhuma recuperação gerenciada. O único
   backup é o export que alguém lembrou de baixar (seção 5). Um bug de cascata
   a uma semana do campeonato é uma perda total.

3. **Sem Cloud Functions, logo cascata sem garantia de servidor.** A exclusão
   roda no cliente. Uma aba fechada no meio, uma conexão que cai, ou um erro não
   tratado deixam a exclusão parcial — e nada no servidor termina o serviço.
   Por isso a ordem da seção 4 foi escolhida para que *qualquer* estado parcial
   seja retomável, e por isso a verificação de 4.3 existe.

4. **A regra não valida o interior de `atribuicoes`.** Security Rules não têm
   laço; validar um mapa de tamanho variável exigiria desenrolar tudo, como foi
   feito com os 36 slots de `rotulos`. Hoje o servidor aceita qualquer estrutura
   dentro de `atribuicoes`. **Em single-user isso é aceitável** — o único
   escritor é o dono do app, e um dado malformado só prejudica ele mesmo.
   **Quando clubes multiusuário entrarem, isso vira uma fronteira de confiança
   real:** qualquer membro poderá escrever qualquer coisa ali, inclusive texto
   livre com dado pessoal, e o servidor não vai impedir. A regra que hoje é
   "validação ausente" passa a ser "campo livre não auditado dentro de um
   documento que a Política diz não conter dado pessoal". Isso precisa ser
   resolvido **antes** do gatilho 1, não depois.

5. **Repositório público.** Schema, regras e este inventário são visíveis. É
   risco assumido e também é a contrapartida: uma validação de `maxLength ≤ 24`
   commitada em setembro vale mais, se alguém questionar a minimização, do que
   uma Política escrita em outubro afirmando a mesma coisa. A contrapartida só
   funciona enquanto **nenhum dado real** entrar no repositório.

---

## 8. Os quatro gatilhos que fecham a janela sem Termos e Política

Rodar sem Termos de Uso e sem Política de Privacidade é defensável hoje por uma
razão estreita: **o único titular de dado real é a própria pessoa que construiu
o produto.** Não há a quem informar que já não saiba, nem a quem prestar contas
que não seja ele mesmo.

Qualquer um dos quatro eventos abaixo **acaba com essa razão**. Eles moram aqui,
num arquivo versionado, e não numa conversa, justamente porque a memória de
qual era a condição de validade é a primeira coisa que se perde.

### Gatilho 1 — um segundo uid

Qualquer conta que não a do dono entrar em `membros`. Nesse instante existe dado
de terceiro sob operação da Café Labs, o enquadramento da seção 1 deixa de
colapsar, e passam a ser exigíveis: Termos, Política, e caminho de exclusão de
conta em autoserviço.

**Como vigiar:** a versão não tem convite, então um segundo uid só aparece por
ação manual no console. Melhor que vigiar é travar — **sugestão ao `backend`/`mobile`:
enquanto for single-user, a regra pode exigir `membrosAtivos.keys().size() == 1`.**
Assim o gatilho não pode ser disparado por acidente, só por alguém remover a
linha da regra de propósito, o que é um commit visível.

### Gatilho 2 — o primeiro rótulo real

O primeiro apelido que representa uma pessoa de verdade, quase sempre menor de
idade. Fecha a janela do art. 14: a partir daí é preciso base legal explícita e
destacada e, para menores de 12 anos, consentimento específico de pai ou
responsável — que **não** é suprido por aceite de Termos por parte do instrutor.

**Como vigiar:** o commit que remove os seeds fictícios (`Clube Exemplo`,
`Alfa`, `Bravo`) é o carimbo de data. Enquanto os seeds estiverem no repositório
e nenhum dado real tiver sido digitado, a janela está aberta. O aviso à direção
do clube acontece **antes** desse commit, não depois.

### Gatilho 3 — o link sair do preview

Remover o `noindex`/`robots.txt`, publicar em domínio próprio, ou entregar a URL
a qualquer pessoa de fora. Uma página alcançável por quem não construiu o
produto precisa de Política de Privacidade acessível a partir dela.

**Como vigiar:** `app/web/robots.txt` e a meta `noindex` são artefatos
versionados — vale checá-los na revisão de qualquer PR que mexa em deploy,
domínio ou hospedagem. Sumiço de qualquer um dos dois é o gatilho, e é visível
no diff.

### Gatilho 4 — qualquer coleta além desta tabela

Analytics ou coleção de eventos, upload de arquivo, criação do bucket de
Storage, reativação do GA4, embed ou SDK de terceiro, campo livre novo,
integração externa. Cada um é finalidade nova, e finalidade nova exige base
legal nova e disclosure.

**Como vigiar:** é a regra da seção 9 — path novo entra na tabela no mesmo
commit. Some-se a isso uma conferência periódica no console: **o bucket de
Storage continua inexistente? O Google Analytics continua desligado?** As duas
perguntas se respondem em trinta segundos e cobrem os dois caminhos que não
passam por diff de código.

---

## 9. Regra de manutenção

**Path novo que não entre nesta tabela no mesmo commit vira órfão futuro.**

Não é formalidade. Um campo que entra sem linha na tabela é um campo que, em
outubro, ninguém sabe por que existe, com que base legal foi coletado, por
quanto tempo pode ficar guardado nem em que ponto do runbook de exclusão precisa
ser apagado. Ele passa a ser exatamente o tipo de dado que se descobre num
incidente, e não numa revisão.

Na prática, o commit que adiciona uma coleção, um campo ou um SDK **também**:

1. Acrescenta a linha correspondente na seção 2 (com titular, finalidade, base
   legal pretendida, retenção e gatilho de exclusão — nenhuma célula vazia; "a
   definir em DD/MM" é resposta aceitável, célula em branco não é);
2. Atualiza o allowlist da regra em `firestore.rules` e, se criar nome novo de
   função, atualiza o contrato de nomes de 3.2;
3. Se o dado for pessoal, entra no runbook da seção 4, na posição certa da
   ordem;
4. Se for coleta de natureza nova, checa o gatilho 4 da seção 8.

Revisão de PR que adiciona path e não mexe neste arquivo deve ser recusada com
essa justificativa.

---

## Aviso permanente

Este documento **não é parecer jurídico.** Foi escrito por um especialista de
compliance de produto dentro de um processo de desenvolvimento, para que as
decisões de dados fiquem registradas no momento em que são tomadas — que é o
único momento em que ainda são conhecidas.

Os Termos de Uso e a Política de Privacidade previstos para 28/09 serão, do
mesmo modo, **rascunho de partida, não escudo de responsabilidade.** Texto legal
redigido com apoio de IA organiza o problema e economiza o trabalho caro de
levantamento — ele não substitui revisão por advogado, e não deve ser publicado
como se já tivesse passado por uma. Antes de qualquer uso com dado real de
terceiro, e especialmente de menor de idade, esses documentos precisam ser
revistos por um profissional habilitado.
