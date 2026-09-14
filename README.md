# Evo Lab

Editor de **evoluções de ordem unida** para clubes de Desbravadores — com motor
de simulação determinístico e playback em vista de cima.

Uma *evolução* é uma sequência coreografada de movimentos de ordem unida
executada por um pelotão. O Evo Lab resolve dois problemas que hoje vivem no
papel quadriculado e na cabeça do instrutor:

1. Registrar quem faz o quê em cada momento, de forma que dê para conferir.
2. Descobrir **antes do ensaio** que a posição final de uma evolução não bate
   com a posição inicial exigida pela próxima — e criar a transição que
   corrige isso.

## Estado

Em desenvolvimento. O motor e o playback estão de pé; o editor, a persistência
e a colaboração ainda não.

## Estrutura

```
packages/evo_motor/   motor de simulação — Dart puro, sem Flutter, sem Firebase
app/                  aplicação Flutter Web (playback)
```

O motor é deliberadamente isolado: nenhuma dependência de UI ou de rede, todas
as funções puras e determinísticas. Ele roda em `dart test` em milissegundos, e
é onde mora praticamente todo o risco técnico do produto.

## Como rodar

```bash
# testes do motor
cd packages/evo_motor && dart test

# aplicação
cd app && flutter run -d chrome
```

## Modelo

- **Tempo discreto, renderização contínua.** O motor calcula estados inteiros
  por tique; o playback interpola entre eles a 60fps. Isso permite responder
  "onde todos estão no passo 37" como função pura e exata — que é o que torna
  a checagem de encadeamento entre evoluções possível.
- **1 passo = 2 tiques. 1 célula = 1 passo = 4 unidades** (quarto-de-célula).
  Quatro é o mínimo que mantém coordenadas inteiras tanto no passo ortogonal
  quanto no diagonal.
- **Direção em 8 setores de 45°.** Movimento egocêntrico: "à frente" é relativo
  ao facing da pessoa, e a vista de cima mostra o resultado absoluto.
- **Cada pessoa tem três estados**, não dois: posição, direção e *cadência*
  (`firme`, `descansar`, `marcandoPasso`, `marchando`). Todo giro em marcha
  termina em firme — a marcha precisa ser recomeçada por comando.
- **Nenhuma posição calculada é persistida**, só comandos. Corrigir o catálogo
  de movimentos re-renderiza todas as evoluções existentes, sem migração.

## Privacidade

Os membros do pelotão **não têm conta** e são representados apenas por um
rótulo curto (apelido ou primeiro nome) numa posição do grid. O produto não
modela idade, foto, contato, dado de saúde ou qualquer informação além desse
rótulo — vários membros são menores de idade, e essa minimização é uma
restrição de arquitetura, não uma preferência.

Todos os dados de exemplo neste repositório são fictícios.

---

Um produto [Café Labs](https://github.com/CafeLabsCorp).
