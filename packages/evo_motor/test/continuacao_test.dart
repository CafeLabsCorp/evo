import 'package:evo_motor/evo_motor.dart';
import 'package:test/test.dart';

void main() {
  group('Continuação implícita e barreira de parte', () {
    test(
      '1. Slot A = A(2) (4 tiques), slot B sem comando (entrada firme): '
      'parte dura 4, B fica parado/firme nos 4 tiques, nenhum tique nulo',
      () {
        final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
          0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.marchando),
          1: const EstadoPessoa(x: 8, y: 0, dir: 3, cad: Cadencia.firme),
        });
        final Parte parte = Parte(
          ordem: 0,
          atribuicoes: <int, Atribuicao>{
            0: Atribuicao(
              movimento: Catalogo.emFrenteMarche(
                2,
                aoTerminar: AoTerminarMarche.marchando,
              ),
            ),
          },
        );
        final ResultadoSimulacao r = simular(inicial, <Parte>[parte]);
        expect(r.porTique, hasLength(4));
        for (final EstadoFormacao f in r.porTique) {
          // Nenhum tique com estado nulo para o slot B (o operator[] de
          // EstadoFormacao lançaria StateError se fosse nulo).
          final EstadoPessoa b = f[1];
          expect((b.x, b.y), (8, 0));
          expect(b.dir, 3);
          expect(b.cad, Cadencia.firme);
        }
      },
    );

    test(
      '2. Slot com offsetInicialTiques=2 fazendo P(1); parte dura 6 (outro '
      'slot define isso): tiques 0-1 continuação implícita antes, 2-3 o '
      'comando, 4-5 continuação depois — 6 tiques sem buraco',
      () {
        final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
          0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.firme),
          // Slot 1 define a duração da parte em 6 tiques (3 tempos).
          1: const EstadoPessoa(x: 8, y: 0, dir: 0, cad: Cadencia.marchando),
        });
        final Parte parte = Parte(
          ordem: 0,
          atribuicoes: <int, Atribuicao>{
            0: Atribuicao(
              movimento: Catalogo.marcarPasso(tempos: 1),
              offsetInicialTiques: 2,
            ),
            1: Atribuicao(
              movimento: Catalogo.emFrenteMarche(
                3,
                aoTerminar: AoTerminarMarche.marchando,
              ),
            ),
          },
        );
        final ResultadoSimulacao r = simular(inicial, <Parte>[parte]);
        expect(r.porTique, hasLength(6));

        // Tiques 0-1: espera pela deixa. `executarSegmentos` só troca a
        // cadência exibida no ÚLTIMO tique de uma execução (é o instante
        // em que o preenchimento "termina") — então o tique 0 ainda
        // mostra a cadência real de entrada (firme) e só o tique 1 (o
        // último da espera) já mostra a cadência de CHEGADA do
        // preenchimento default (a final do movimento — marcandoPasso,
        // documentado em compilador.dart). x/y não mudam em nenhum tique
        // desta parte (o slot nunca sai de (0,0)).
        expect((r.porTique[0][0].x, r.porTique[0][0].y), (0, 0));
        expect(r.porTique[0][0].cad, Cadencia.firme);
        expect((r.porTique[1][0].x, r.porTique[1][0].y), (0, 0));
        expect(r.porTique[1][0].cad, Cadencia.marcandoPasso);
        // Tiques 2-3: o comando em si — "marcar passo" a partir de firme
        // (a cadência de ENTRADA na parte, `inicial.cad` do slot) não
        // tem transição nem deslocamento.
        for (int i = 2; i < 4; i++) {
          expect((r.porTique[i][0].x, r.porTique[i][0].y), (0, 0));
          expect(r.porTique[i][0].cad, Cadencia.marcandoPasso);
        }
        // Tiques 4-5: continuação pós-movimento, ainda parado.
        for (int i = 4; i < 6; i++) {
          expect((r.porTique[i][0].x, r.porTique[i][0].y), (0, 0));
          expect(r.porTique[i][0].cad, Cadencia.marcandoPasso);
        }
        // Nenhum buraco: os 6 tiques têm estado definido pros dois slots.
        for (final EstadoFormacao f in r.porTique) {
          expect(f.slots.toSet(), <int>{0, 1});
        }
      },
    );

    test(
      '3. offsetInicialTiques ÍMPAR é rejeitado cedo, com diagnóstico claro '
      '— NÃO "arredonda pra 6 e duplica o último tique" (ver ressalva)',
      () {
        // O caso pedido pela spec ("offsetInicialTiques=1 com Alto (4
        // tiques): total teórico 5, ímpar, arredonda pra 6, tique 5 repete
        // o tique 4") não é alcançável na API atual sem crashar antes de
        // chegar nesse resultado — e a causa é estrutural, não um bug
        // pontual: TODA duração de segmento no motor (Avanco/Pausa/Juncao)
        // é sempre PAR (múltiplo de 1 tempo = 2 tiques); a única forma de
        // `duracaoBruta` (offset + duração) dar ÍMPAR é o próprio
        // `offsetInicialTiques` já vir ímpar. E um offset > 0 sempre passa
        // por `Preenchimento.segmentosPara(offset)` pra montar o trecho de
        // espera — que rejeita tiques ímpares por design ("T de uma parte
        // já vem arredondado pra par exatamente para evitar isso").
        // Ou seja: o ramo de arredondamento ímpar→par de `compilarParte`
        // (`duracaoBruta.isOdd ? duracaoBruta + 1 : duracaoBruta`) é hoje
        // código morto sob uso válido — não existe um jeito de alimentá-lo
        // com um `duracaoBruta` ímpar sem já ter crashado antes.
        //
        // Decisão: em vez de deixar isso estourar tarde, fundo em
        // `Preenchimento` (uma classe que não devia precisar saber por que
        // foi chamada), `Atribuicao` agora rejeita offset ímpar na hora da
        // CONSTRUÇÃO, com uma mensagem que aponta a causa raiz. Ver
        // discussão no relatório final desta tarefa — a spec deste caso
        // precisa ser revista com o qa: ou offsets ímpares nunca deveriam
        // ser um input válido (e este teste documenta a rejeição), ou a
        // spec quer uma semântica de "meio tempo" que o motor ainda não
        // tem (e isso é trabalho novo, não uma correção de teste).
        expect(
          () => Atribuicao(movimento: Catalogo.alto(), offsetInicialTiques: 1),
          throwsArgumentError,
        );
      },
    );

    test(
      '4. Invariante geral: numa parte com mistura de atribuídos/não-'
      'atribuídos/offsets, todo slot tem estado não-nulo em todo tique',
      () {
        final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
          0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.marchando),
          1: const EstadoPessoa(x: 4, y: 0, dir: 0, cad: Cadencia.firme),
          2: const EstadoPessoa(x: 8, y: 0, dir: 0, cad: Cadencia.descansar),
          3: const EstadoPessoa(x: 12, y: 0, dir: 0, cad: Cadencia.marchando),
        });
        final Parte parte = Parte(
          ordem: 0,
          atribuicoes: <int, Atribuicao>{
            0: Atribuicao(
              movimento: Catalogo.emFrenteMarche(
                4,
                aoTerminar: AoTerminarMarche.firme,
              ),
            ),
            // slot 1: sem atribuição.
            2: Atribuicao(
              movimento: Catalogo.sentido(tempos: 1),
              offsetInicialTiques: 2,
            ),
            // slot 3: sem atribuição.
          },
        );
        final ResultadoSimulacao r = simular(inicial, <Parte>[parte]);
        expect(r.porTique, isNotEmpty);
        for (final EstadoFormacao f in r.porTique) {
          for (final int slot in <int>[0, 1, 2, 3]) {
            // Lança StateError se o slot não tiver estado neste tique —
            // é exatamente essa a garantia que queremos exercitar.
            expect(() => f[slot], returnsNormally);
          }
        }
      },
    );
  });
}
