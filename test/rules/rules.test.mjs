// Testes das Firestore Security Rules do Evo Lab.
// Ver ../../firestore.rules e ../../docs/DADOS.md.
//
// POR QUE UM HARNESS NODE SEPARADO: Security Rules só podem ser exercitadas por
// um avaliador de regras de verdade, que é o que o emulador do Firestore
// fornece. Este harness é deliberadamente isolado do app Flutter: tem o próprio
// package.json / node_modules aqui em test/rules/, e não está ligado ao
// pubspec.yaml nem ao `flutter test`. Ele fala SÓ com o emulador local —
// nunca com produção, nunca com um projeto Firebase real.
//
// COMO RODAR (a partir da raiz do repositório):
//   firebase emulators:exec --only firestore \
//     "cd test/rules && npm install && npm test"
//
// ou, com o emulador já de pé em outro terminal:
//   firebase emulators:start --only firestore
//   cd test/rules && npm install && npm test
//
// FIXTURES 100% FICTÍCIAS. O repositório é público: nenhum apelido real, nome
// de clube real, uid ou e-mail entra aqui — nem "temporariamente". Os rótulos
// são "Alfa", "Bravo", "Charlie" e o clube é "Clube Exemplo".

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

const PROJECT_ID = 'evo-rules-test';
const RULES_PATH = new URL('../../firestore.rules', import.meta.url);

const DONO = 'dono-uid';
const ESTRANHO = 'estranho-uid';

const CLUBE_ID = 'clube1';
const OUTRO_CLUBE_ID = 'clube2';
const PELOTAO_ID = 'pelotao1';
const EVOLUCAO_ID = 'evolucao1';
const PARTE_ID = 'parte1';

// Os 14 campos proibidos de docs/DADOS.md 3.1 não são nomeados na regra: a
// allowlist os rejeita sem conhecê-los. Estes três são a amostra que prova isso.
const CAMPOS_PROIBIDOS = [
  { idade: 14 },
  { telefone: '00000-0000' },
  { nascimento: '2010-01-01' },
];

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(RULES_PATH, 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

// -- helpers -----------------------------------------------------------------

function db(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}
function anon() {
  return testEnv.unauthenticatedContext().firestore();
}

const agora = () => new Date();
const texto = (n) => 'a'.repeat(n);

function clubeDoc(extra = {}) {
  return {
    nome: 'Clube Exemplo',
    dono: DONO,
    membros: { [DONO]: { estado: 'ativo', papel: 'instrutor' } },
    membrosAtivos: { [DONO]: true },
    criadoEm: agora(),
    ...extra,
  };
}

function pelotaoDoc(extra = {}) {
  return {
    clubId: CLUBE_ID,
    nome: 'Pelotão Exemplo',
    linhas: 3,
    colunas: 3,
    rotulos: { 0: 'Alfa', 1: 'Bravo', 2: 'Charlie' },
    criadoEm: agora(),
    atualizadoEm: agora(),
    ...extra,
  };
}

function evolucaoDoc(extra = {}) {
  return {
    clubId: CLUBE_ID,
    pelotaoId: PELOTAO_ID,
    nome: 'Evolução Exemplo',
    estadoInicial: {
      slots: {
        0: { linha: 0, coluna: 0, setor: 0, cadencia: 'firme' },
        1: { linha: 0, coluna: 1, setor: 0, cadencia: 'firme' },
      },
    },
    versaoCatalogo: 2,
    criadoEm: agora(),
    atualizadoEm: agora(),
    ...extra,
  };
}

function parteDoc(extra = {}) {
  return {
    clubId: CLUBE_ID,
    evolucaoId: EVOLUCAO_ID,
    ordem: 0,
    nome: 'Marcar passo',
    atribuicoes: {
      0: { movimento: { tipo: 'marcarPasso', tempos: 4 } },
      1: { movimento: { tipo: 'marcarPasso', tempos: 4 } },
    },
    atualizadoEm: agora(),
    ...extra,
  };
}

// Mapa de rótulos com os 36 slots preenchidos com 24 caracteres cada — o pior
// caso possível para o orçamento de expressões da regra de `pelotoes`.
function rotulos36Cheios() {
  const r = {};
  for (let i = 0; i < 36; i++) r[String(i)] = texto(24);
  return r;
}

async function semear() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, 'clubes', CLUBE_ID), clubeDoc());
    await setDoc(doc(d, 'clubes', OUTRO_CLUBE_ID), clubeDoc({
      nome: 'Outro Clube Exemplo',
      dono: ESTRANHO,
      membros: { [ESTRANHO]: { estado: 'ativo', papel: 'instrutor' } },
      membrosAtivos: { [ESTRANHO]: true },
    }));
    await setDoc(doc(d, 'pelotoes', PELOTAO_ID), pelotaoDoc());
    await setDoc(doc(d, 'evolucoes', EVOLUCAO_ID), evolucaoDoc());
    await setDoc(doc(d, 'partes', PARTE_ID), parteDoc());
  });
}

const clubeRef = (d, id = CLUBE_ID) => doc(d, 'clubes', id);
const pelotaoRef = (d, id = PELOTAO_ID) => doc(d, 'pelotoes', id);
const evolucaoRef = (d, id = EVOLUCAO_ID) => doc(d, 'evolucoes', id);
const parteRef = (d, id = PARTE_ID) => doc(d, 'partes', id);

// Fábricas por coleção, para os testes que precisam varrer as quatro.
const COLECOES = [
  { nome: 'clubes', path: 'clubes', novo: 'clube-novo', fabrica: clubeDoc },
  { nome: 'pelotoes', path: 'pelotoes', novo: 'pelotao-novo', fabrica: pelotaoDoc },
  { nome: 'evolucoes', path: 'evolucoes', novo: 'evolucao-novo', fabrica: evolucaoDoc },
  { nome: 'partes', path: 'partes', novo: 'parte-novo', fabrica: parteDoc },
];

// -- caminho feliz -----------------------------------------------------------
// Sem isto, uma regra que negasse TUDO passaria em todos os testes negativos.

describe('caminho feliz', () => {
  test('dono cria o clube com ele mesmo como único membro ativo', async () => {
    await assertSucceeds(setDoc(clubeRef(db(DONO), 'novo'), clubeDoc()));
  });

  test('membro ativo cria, lê, atualiza e apaga um pelotão', async () => {
    await semear();
    const d = db(DONO);
    await assertSucceeds(setDoc(pelotaoRef(d, 'p2'), pelotaoDoc()));
    await assertSucceeds(getDoc(pelotaoRef(d, 'p2')));
    await assertSucceeds(
      updateDoc(pelotaoRef(d, 'p2'), { nome: 'Pelotão B', atualizadoEm: agora() }),
    );
    await assertSucceeds(deleteDoc(pelotaoRef(d, 'p2')));
  });

  test('membro ativo consulta pelotoes do próprio clube', async () => {
    await semear();
    const q = query(
      collection(db(DONO), 'pelotoes'),
      where('clubId', '==', CLUBE_ID),
    );
    await assertSucceeds(getDocs(q));
  });

  test('os 36 slots cheios com 24 caracteres cabem no orçamento de expressões', async () => {
    // Pior caso da regra de `pelotoes`: nenhuma verificação de slot
    // curto-circuita por ausência. Se esta escrita passar, o teto de 36 slots
    // cabe no limite de 1.000 expressões por request do Firestore.
    await semear();
    await assertSucceeds(
      setDoc(pelotaoRef(db(DONO), 'p36'), pelotaoDoc({
        linhas: 6,
        colunas: 6,
        rotulos: rotulos36Cheios(),
      })),
    );
  });

  test('evolução com campo (mapa de dois inteiros) é aceita', async () => {
    await semear();
    await assertSucceeds(
      setDoc(evolucaoRef(db(DONO), 'e2'), evolucaoDoc({
        campo: { larguraCelulas: 20, alturaCelulas: 12 },
      })),
    );
  });

  test('ordem fracionária é aceita (reordenação por inserção)', async () => {
    await semear();
    await assertSucceeds(
      setDoc(parteRef(db(DONO), 'pt2'), parteDoc({ ordem: 1.5 })),
    );
  });
});

// -- não autenticado ---------------------------------------------------------

describe('não autenticado', () => {
  test('não lê nenhuma das quatro coleções', async () => {
    await semear();
    const d = anon();
    await assertFails(getDoc(clubeRef(d)));
    await assertFails(getDoc(pelotaoRef(d)));
    await assertFails(getDoc(evolucaoRef(d)));
    await assertFails(getDoc(parteRef(d)));
  });

  test('não consulta nenhuma das quatro coleções', async () => {
    await semear();
    const d = anon();
    for (const c of ['clubes', 'pelotoes', 'evolucoes', 'partes']) {
      await assertFails(getDocs(collection(d, c)));
    }
  });

  test('não cria em nenhuma das quatro coleções', async () => {
    await semear();
    const d = anon();
    for (const c of COLECOES) {
      await assertFails(setDoc(doc(d, c.path, c.novo), c.fabrica()));
    }
  });

  test('não atualiza nem apaga nada', async () => {
    await semear();
    const d = anon();
    await assertFails(updateDoc(pelotaoRef(d), { nome: 'invadido' }));
    await assertFails(deleteDoc(pelotaoRef(d)));
    await assertFails(updateDoc(clubeRef(d), { nome: 'invadido' }));
    await assertFails(deleteDoc(clubeRef(d)));
  });
});

// -- usuário de outro clube --------------------------------------------------

describe('usuário de outro clube', () => {
  test('não lê documentos de um clube de que não participa', async () => {
    await semear();
    const d = db(ESTRANHO);
    await assertFails(getDoc(clubeRef(d)));
    await assertFails(getDoc(pelotaoRef(d)));
    await assertFails(getDoc(evolucaoRef(d)));
    await assertFails(getDoc(parteRef(d)));
  });

  test('não enumera pelotoes de outro clube por consulta', async () => {
    await semear();
    const q = query(
      collection(db(ESTRANHO), 'pelotoes'),
      where('clubId', '==', CLUBE_ID),
    );
    await assertFails(getDocs(q));
  });

  test('não escreve em documentos de outro clube', async () => {
    await semear();
    const d = db(ESTRANHO);
    await assertFails(updateDoc(pelotaoRef(d), { nome: 'invadido' }));
    await assertFails(deleteDoc(pelotaoRef(d)));
    await assertFails(updateDoc(evolucaoRef(d), { nome: 'invadido' }));
    await assertFails(deleteDoc(parteRef(d)));
  });

  test('não cria documento carimbado com o clubId alheio', async () => {
    await semear();
    const d = db(ESTRANHO);
    await assertFails(setDoc(pelotaoRef(d, 'intruso'), pelotaoDoc()));
    await assertFails(setDoc(evolucaoRef(d, 'intruso'), evolucaoDoc()));
    await assertFails(setDoc(parteRef(d, 'intruso'), parteDoc()));
  });

  test('não cria clube tendo outra pessoa como dono', async () => {
    await assertFails(
      setDoc(clubeRef(db(ESTRANHO), 'novo'), clubeDoc()), // dono = DONO
    );
  });

  test('não apaga nem renomeia o clube alheio', async () => {
    await semear();
    const d = db(ESTRANHO);
    await assertFails(deleteDoc(clubeRef(d)));
    await assertFails(updateDoc(clubeRef(d), { nome: 'Invadido' }));
  });

  test('clube inexistente falha fechado (não libera o filho)', async () => {
    // Nenhum clube semeado: a autorização do filho depende de um get() que não
    // resolve. Erro de avaliação nega — não existe caminho em que "clube
    // ausente" vire acesso liberado.
    await assertFails(
      setDoc(pelotaoRef(db(DONO), 'orfao'), pelotaoDoc({ clubId: 'nao-existe' })),
    );
  });
});

// -- rótulos (a coleção sensível) -------------------------------------------

describe('rotulos', () => {
  test('rótulo de 25 caracteres é rejeitado no create', async () => {
    await semear();
    await assertFails(
      setDoc(pelotaoRef(db(DONO), 'p25'), pelotaoDoc({
        rotulos: { 0: texto(25) },
      })),
    );
  });

  test('rótulo de 24 caracteres é aceito (limite inclusivo)', async () => {
    await semear();
    await assertSucceeds(
      setDoc(pelotaoRef(db(DONO), 'p24'), pelotaoDoc({
        rotulos: { 0: texto(24) },
      })),
    );
  });

  test('rótulo de 25 caracteres é rejeitado no UPDATE também', async () => {
    // O teto seria contornável se só valesse no create.
    await semear();
    await assertFails(
      updateDoc(pelotaoRef(db(DONO)), {
        'rotulos.0': texto(25),
        atualizadoEm: agora(),
      }),
    );
  });

  test('rótulo no último slot (35) também é validado no update', async () => {
    await semear();
    await assertFails(
      updateDoc(pelotaoRef(db(DONO)), {
        'rotulos.35': texto(25),
        atualizadoEm: agora(),
      }),
    );
  });

  test('rótulo não-string é rejeitado', async () => {
    await semear();
    await assertFails(
      setDoc(pelotaoRef(db(DONO), 'pnum'), pelotaoDoc({ rotulos: { 0: 42 } })),
    );
  });

  test('rótulo como mapa aninhado é rejeitado', async () => {
    // Sem o `is string` da regra, um mapa de até 24 chaves passaria no
    // size() e viraria porta para dado arbitrário dentro do rótulo — telefone,
    // idade, observação. É o buraco que o `is string` fecha.
    await semear();
    await assertFails(
      setDoc(pelotaoRef(db(DONO), 'pmapa'), pelotaoDoc({
        rotulos: { 0: { apelido: 'Alfa', telefone: '00000-0000' } },
      })),
    );
  });

  test('rótulo como lista é rejeitado', async () => {
    await semear();
    await assertFails(
      setDoc(pelotaoRef(db(DONO), 'plista'), pelotaoDoc({
        rotulos: { 0: ['Alfa', 'Bravo'] },
      })),
    );
  });

  test('rótulo nulo é rejeitado', async () => {
    await semear();
    await assertFails(
      setDoc(pelotaoRef(db(DONO), 'pnulo'), pelotaoDoc({ rotulos: { 0: null } })),
    );
  });

  test('chave de slot fora de 0..35 é rejeitada', async () => {
    await semear();
    const d = db(DONO);
    await assertFails(
      setDoc(pelotaoRef(d, 'p36k'), pelotaoDoc({ rotulos: { 36: 'Alfa' } })),
    );
    await assertFails(
      setDoc(pelotaoRef(d, 'pneg'), pelotaoDoc({ rotulos: { '-1': 'Alfa' } })),
    );
  });

  test('rótulo como CHAVE do mapa é rejeitado', async () => {
    // A chave precisa ser índice de slot. Rótulo como chave apareceria em
    // índice, em export e em qualquer log de query.
    await semear();
    await assertFails(
      setDoc(pelotaoRef(db(DONO), 'pchave'), pelotaoDoc({
        rotulos: { Alfa: 'Alfa' },
      })),
    );
  });

  test('grid fora de 1..6 é rejeitado', async () => {
    await semear();
    const d = db(DONO);
    await assertFails(setDoc(pelotaoRef(d, 'g1'), pelotaoDoc({ linhas: 7 })));
    await assertFails(setDoc(pelotaoRef(d, 'g2'), pelotaoDoc({ colunas: 0 })));
  });
});

// -- chaves de slot em evolucoes e partes ------------------------------------

describe('chaves de slot em evolucoes e partes', () => {
  test('estadoInicial.slots com chave fora de 0..35 é rejeitado', async () => {
    await semear();
    await assertFails(
      setDoc(evolucaoRef(db(DONO), 'e36'), evolucaoDoc({
        estadoInicial: { slots: { 36: { linha: 0, coluna: 0 } } },
      })),
    );
  });

  test('estadoInicial com rótulo como chave de slot é rejeitado', async () => {
    await semear();
    await assertFails(
      setDoc(evolucaoRef(db(DONO), 'enome'), evolucaoDoc({
        estadoInicial: { slots: { Alfa: { linha: 0, coluna: 0 } } },
      })),
    );
  });

  test('estadoInicial com chave extra além de slots é rejeitado', async () => {
    await semear();
    await assertFails(
      setDoc(evolucaoRef(db(DONO), 'eextra'), evolucaoDoc({
        estadoInicial: { slots: {}, observacoes: 'texto livre' },
      })),
    );
  });

  test('atribuicoes com chave fora de 0..35 é rejeitado', async () => {
    await semear();
    await assertFails(
      setDoc(parteRef(db(DONO), 'pt36'), parteDoc({
        atribuicoes: { 99: { movimento: { tipo: 'marcarPasso' } } },
      })),
    );
  });

  test('atribuicoes com rótulo como chave é rejeitado', async () => {
    await semear();
    await assertFails(
      setDoc(parteRef(db(DONO), 'ptnome'), parteDoc({
        atribuicoes: { Bravo: { movimento: { tipo: 'marcarPasso' } } },
      })),
    );
  });
});

// -- allowlist de campos -----------------------------------------------------

describe('allowlist de campos', () => {
  for (const c of COLECOES) {
    for (const proibido of CAMPOS_PROIBIDOS) {
      const campo = Object.keys(proibido)[0];
      test(`campo desconhecido "${campo}" é rejeitado no create de ${c.nome}`, async () => {
        await semear();
        await assertFails(
          setDoc(doc(db(DONO), c.path, c.novo), c.fabrica(proibido)),
        );
      });
    }

    test(`campo desconhecido é rejeitado no update de ${c.nome}`, async () => {
      await semear();
      const alvo = c.path === 'clubes' ? CLUBE_ID
        : c.path === 'pelotoes' ? PELOTAO_ID
        : c.path === 'evolucoes' ? EVOLUCAO_ID
        : PARTE_ID;
      await assertFails(updateDoc(doc(db(DONO), c.path, alvo), { idade: 14 }));
    });
  }

  test('photoURL é rejeitado em toda coleção', async () => {
    // O app não lê nem persiste photoURL em lugar nenhum (docs/DADOS.md 2.1).
    await semear();
    for (const c of COLECOES) {
      await assertFails(
        setDoc(doc(db(DONO), c.path, c.novo), c.fabrica({
          photoURL: 'https://exemplo.invalid/foto.png',
        })),
      );
    }
  });

  test('nomeExibicao dentro de membros é rejeitado', async () => {
    // Decisão minimizadora: a CHAVE do mapa é o que torna a migração para
    // clubes gratuita, não o VALOR. Enquanto a tela de aprovação de convite não
    // existir, `nomeExibicao` seria nome civil de adulto guardado para
    // funcionalidade inexistente.
    await assertFails(
      setDoc(clubeRef(db(DONO), 'novo'), clubeDoc({
        membros: {
          [DONO]: { estado: 'ativo', papel: 'instrutor', nomeExibicao: 'Fulano' },
        },
      })),
    );
  });

  test('nomeExibicao também é rejeitado num update posterior', async () => {
    await semear();
    await assertFails(
      updateDoc(clubeRef(db(DONO)), { [`membros.${DONO}.nomeExibicao`]: 'Fulano' }),
    );
  });

  test('membro extra dentro do mapa membros é rejeitado', async () => {
    await semear();
    await assertFails(
      updateDoc(clubeRef(db(DONO)), {
        [`membros.${ESTRANHO}`]: { estado: 'ativo', papel: 'instrutor' },
      }),
    );
  });
});

// -- tetos de texto livre ----------------------------------------------------

describe('tetos de texto livre', () => {
  test('nome de clube com 61 caracteres é rejeitado', async () => {
    await assertFails(
      setDoc(clubeRef(db(DONO), 'novo'), clubeDoc({ nome: texto(61) })),
    );
  });

  test('nome de clube com 60 caracteres é aceito', async () => {
    await assertSucceeds(
      setDoc(clubeRef(db(DONO), 'novo'), clubeDoc({ nome: texto(60) })),
    );
  });

  test('nome de pelotão com 61 caracteres é rejeitado', async () => {
    await semear();
    await assertFails(
      setDoc(pelotaoRef(db(DONO), 'p61'), pelotaoDoc({ nome: texto(61) })),
    );
  });

  test('nome de evolução com 81 caracteres é rejeitado', async () => {
    await semear();
    await assertFails(
      setDoc(evolucaoRef(db(DONO), 'e81'), evolucaoDoc({ nome: texto(81) })),
    );
  });

  test('nome de evolução com 80 caracteres é aceito', async () => {
    await semear();
    await assertSucceeds(
      setDoc(evolucaoRef(db(DONO), 'e80'), evolucaoDoc({ nome: texto(80) })),
    );
  });

  test('nome de parte com 61 caracteres é rejeitado', async () => {
    await semear();
    await assertFails(
      setDoc(parteRef(db(DONO), 'pt61'), parteDoc({ nome: texto(61) })),
    );
  });

  test('nome de parte é opcional', async () => {
    await semear();
    const semNome = parteDoc();
    delete semNome.nome;
    await assertSucceeds(setDoc(parteRef(db(DONO), 'ptsn'), semNome));
  });

  test('nome não-string é rejeitado', async () => {
    await semear();
    await assertFails(
      setDoc(pelotaoRef(db(DONO), 'pnn'), pelotaoDoc({ nome: 42 })),
    );
  });

  test('renomear para 61 caracteres num update é rejeitado', async () => {
    await semear();
    await assertFails(
      updateDoc(pelotaoRef(db(DONO)), { nome: texto(61), atualizadoEm: agora() }),
    );
  });
});

// -- campo (evolucoes) -------------------------------------------------------

describe('campo da evolução', () => {
  test('campo como texto livre é rejeitado', async () => {
    // O maior risco de dado pessoal acidental do schema inteiro: "pátio da casa
    // do sicrano". Mapa de dois inteiros, nunca string.
    await semear();
    await assertFails(
      setDoc(evolucaoRef(db(DONO), 'ec'), evolucaoDoc({
        campo: 'pátio da escola',
      })),
    );
  });

  test('campo com chave extra é rejeitado', async () => {
    await semear();
    await assertFails(
      setDoc(evolucaoRef(db(DONO), 'ec2'), evolucaoDoc({
        campo: { larguraCelulas: 20, alturaCelulas: 12, observacao: 'atrás da igreja' },
      })),
    );
  });

  test('campo com dimensão não-inteira é rejeitado', async () => {
    await semear();
    await assertFails(
      setDoc(evolucaoRef(db(DONO), 'ec3'), evolucaoDoc({
        campo: { larguraCelulas: '20', alturaCelulas: 12 },
      })),
    );
  });

  test('campo é opcional', async () => {
    await semear();
    await assertSucceeds(setDoc(evolucaoRef(db(DONO), 'ec4'), evolucaoDoc()));
  });
});

// -- trava de single-user ----------------------------------------------------

describe('trava de single-user (gatilho 1 de DADOS.md)', () => {
  test('membrosAtivos com DUAS chaves é rejeitado no create', async () => {
    // Este é o teste que prova a trava. Se ele começar a passar como sucesso,
    // alguém removeu a linha `membrosAtivos.keys().size() == 1` da regra — e
    // isso precisa ser uma decisão consciente, com Termos, Política e exclusão
    // de conta em autoserviço prontos, não um efeito colateral.
    await assertFails(
      setDoc(clubeRef(db(DONO), 'novo'), clubeDoc({
        membros: {
          [DONO]: { estado: 'ativo', papel: 'instrutor' },
          [ESTRANHO]: { estado: 'ativo', papel: 'instrutor' },
        },
        membrosAtivos: { [DONO]: true, [ESTRANHO]: true },
      })),
    );
  });

  test('membrosAtivos vazio é rejeitado no create', async () => {
    await assertFails(
      setDoc(clubeRef(db(DONO), 'novo'), clubeDoc({ membrosAtivos: {} })),
    );
  });

  test('segundo uid não pode ser acrescentado num update', async () => {
    await semear();
    await assertFails(
      updateDoc(clubeRef(db(DONO)), { [`membrosAtivos.${ESTRANHO}`]: true }),
    );
  });

  test('membrosAtivos com valor diferente de true é rejeitado', async () => {
    await assertFails(
      setDoc(clubeRef(db(DONO), 'novo'), clubeDoc({
        membrosAtivos: { [DONO]: 'sim' },
      })),
    );
  });

  test('membrosAtivos de um uid que não é o dono é rejeitado', async () => {
    await assertFails(
      setDoc(clubeRef(db(DONO), 'novo'), clubeDoc({
        membrosAtivos: { [ESTRANHO]: true },
      })),
    );
  });
});

// -- ordem (partes) ----------------------------------------------------------

describe('ordem das partes', () => {
  test('ordem NaN é rejeitada', async () => {
    // Toda comparação com NaN é falsa, então a checagem de faixa exclui NaN sem
    // precisar de uma verificação dedicada.
    await semear();
    await assertFails(
      setDoc(parteRef(db(DONO), 'ptnan'), parteDoc({ ordem: NaN })),
    );
  });

  test('ordem Infinity é rejeitada', async () => {
    await semear();
    await assertFails(
      setDoc(parteRef(db(DONO), 'ptinf'), parteDoc({ ordem: Infinity })),
    );
  });

  test('ordem como string é rejeitada', async () => {
    await semear();
    await assertFails(
      setDoc(parteRef(db(DONO), 'ptstr'), parteDoc({ ordem: '1' })),
    );
  });

  test('ordem fora da faixa é rejeitada', async () => {
    await semear();
    await assertFails(
      setDoc(parteRef(db(DONO), 'ptbig'), parteDoc({ ordem: 2e9 })),
    );
  });

  test('ordem NaN também é rejeitada num update', async () => {
    await semear();
    await assertFails(
      updateDoc(parteRef(db(DONO)), { ordem: NaN, atualizadoEm: agora() }),
    );
  });
});

// -- imutabilidade -----------------------------------------------------------

describe('imutabilidade', () => {
  test('clubId é imutável em pelotoes, evolucoes e partes', async () => {
    await semear();
    const d = db(DONO);
    // Mudar para um clube de que o usuário nem participa:
    await assertFails(updateDoc(pelotaoRef(d), { clubId: OUTRO_CLUBE_ID }));
    await assertFails(updateDoc(evolucaoRef(d), { clubId: OUTRO_CLUBE_ID }));
    await assertFails(updateDoc(parteRef(d), { clubId: OUTRO_CLUBE_ID }));
  });

  test('clubId é imutável mesmo para um clubId inexistente', async () => {
    await semear();
    await assertFails(updateDoc(pelotaoRef(db(DONO)), { clubId: 'nao-existe' }));
  });

  test('evolucaoId é imutável em partes', async () => {
    await semear();
    await assertFails(updateDoc(parteRef(db(DONO)), { evolucaoId: 'outra' }));
  });

  test('dono e criadoEm são imutáveis no clube', async () => {
    await semear();
    const d = db(DONO);
    await assertFails(updateDoc(clubeRef(d), { dono: ESTRANHO }));
    await assertFails(updateDoc(clubeRef(d), { criadoEm: agora() }));
  });
});

// -- runbook de exclusão -----------------------------------------------------

describe('runbook de exclusão (docs/DADOS.md 4.1)', () => {
  test('a ordem partes → evolucoes → pelotoes → clube é permitida do início ao fim', async () => {
    await semear();
    const d = db(DONO);
    await assertSucceeds(deleteDoc(parteRef(d)));
    await assertSucceeds(deleteDoc(evolucaoRef(d)));
    await assertSucceeds(deleteDoc(pelotaoRef(d))); // os rótulos saem aqui
    await assertSucceeds(deleteDoc(clubeRef(d)));   // autorização por último
  });

  test('apagar o clube primeiro torna os filhos inalcançáveis', async () => {
    // Este é o incidente que o Domo já teve, e o motivo de a ordem do runbook
    // ser inegociável: sem o documento de autorização, a regra que autorizaria
    // a exclusão do filho consulta um documento que não existe mais. Ninguém
    // mais lê nem apaga — só intervenção manual no console.
    await semear();
    const d = db(DONO);
    await assertSucceeds(deleteDoc(clubeRef(d)));
    await assertFails(deleteDoc(pelotaoRef(d)));
    await assertFails(getDoc(pelotaoRef(d)));
  });

  test('variante de emergência (pelotoes primeiro) não trava o resto', async () => {
    // Tirar rótulo do ar o mais rápido possível deixa evolucoes/partes
    // apontando para um pelotão inexistente, mas não trava nada: a regra desses
    // filhos consulta `clubes`, não `pelotoes`.
    await semear();
    const d = db(DONO);
    await assertSucceeds(deleteDoc(pelotaoRef(d)));
    await assertSucceeds(deleteDoc(parteRef(d)));
    await assertSucceeds(deleteDoc(evolucaoRef(d)));
    await assertSucceeds(deleteDoc(clubeRef(d)));
  });

  test('o export lê as quatro coleções por clubId', async () => {
    // O export client-side (única recuperação de desastre que existe no plano
    // Spark) precisa dessas quatro consultas liberadas.
    await semear();
    const d = db(DONO);
    await assertSucceeds(getDoc(clubeRef(d)));
    for (const c of ['pelotoes', 'evolucoes', 'partes']) {
      await assertSucceeds(
        getDocs(query(collection(d, c), where('clubId', '==', CLUBE_ID))),
      );
    }
  });
});

// -- catch-all ---------------------------------------------------------------

describe('catch-all', () => {
  test('coleção não modelada nega leitura e escrita', async () => {
    const d = db(DONO);
    await assertFails(setDoc(doc(d, 'qualquer', 'x'), { a: 1 }));
    await assertFails(getDoc(doc(d, 'qualquer', 'x')));
  });

  test('usuarios/{uid} não existe e não pode ser criado', async () => {
    // Não há documento de perfil onde dado de instrutor possa se acumular
    // (docs/DADOS.md 3.2). Nem o próprio usuário cria o dele.
    const d = db(DONO);
    await assertFails(setDoc(doc(d, 'usuarios', DONO), { nome: 'Fulano' }));
    await assertFails(getDoc(doc(d, 'usuarios', DONO)));
  });

  test('subcoleção sob um clube é negada', async () => {
    await semear();
    const d = db(DONO);
    await assertFails(
      setDoc(doc(d, 'clubes', CLUBE_ID, 'itens', 'x'), { a: 1 }),
    );
    await assertFails(getDoc(doc(d, 'clubes', CLUBE_ID, 'itens', 'x')));
  });

  test('coleção de eventos/analytics é negada', async () => {
    // Gatilho 4 de docs/DADOS.md: coleta nova exige entrar na tabela primeiro.
    const d = db(DONO);
    await assertFails(setDoc(doc(d, 'eventos', 'x'), { tipo: 'abriu_app' }));
  });
});
