import 'package:evo_motor/evo_motor.dart';
import 'package:test/test.dart';

void main() {
  group('Modos declarado vs encadeado', () {
    test(
      '1. Sequência sem erro de planejamento: os dois modos dão trajetória '
      'tique-a-tique idêntica',
      () {
        final Evolucao a = Evolucao(
          nome: 'A',
          estadoInicial: EstadoFormacao(<int, EstadoPessoa>{
            0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.firme),
          }),
          partes: <Parte>[
            Parte(
              ordem: 0,
              atribuicoes: <int, Atribuicao>{
                0: Atribuicao(
                  movimento: Catalogo.emFrenteMarche(
                    2,
                    aoTerminar: AoTerminarMarche.firme,
                  ),
                ),
              },
            ),
          ],
        );
        // B declara início EXATAMENTE onde A termina de verdade — sem
        // erro de planejamento.
        final Evolucao b = Evolucao(
          nome: 'B',
          estadoInicial: EstadoFormacao(<int, EstadoPessoa>{
            0: const EstadoPessoa(x: 0, y: -8, dir: 0, cad: Cadencia.firme),
          }),
          partes: <Parte>[
            Parte(
              ordem: 0,
              atribuicoes: <int, Atribuicao>{
                0: Atribuicao(movimento: Catalogo.direitaVolverParado()),
              },
            ),
          ],
        );

        final ResultadoSequencia declarado = simularSequencia(<Evolucao>[
          a,
          b,
        ], ModoSequencia.declarado);
        final ResultadoSequencia encadeado = simularSequencia(<Evolucao>[
          a,
          b,
        ], ModoSequencia.encadeado);

        expect(declarado.diagnosticosEncadeamento, isEmpty);
        expect(encadeado.diagnosticosEncadeamento, isEmpty);

        for (int i = 0; i < 2; i++) {
          expect(
            declarado.porEvolucao[i].porTique,
            encadeado.porEvolucao[i].porTique,
            reason: 'evolução $i deveria ser idêntica nos dois modos',
          );
        }
      },
    );

    test(
      '2. Com erro proposital (A termina em (0,-4), B declara início em '
      '(8,0)): os dois modos divergem a partir do início de B — o bug mais '
      'fácil de introduzir aqui é reaproveitar o resultado de um modo pro '
      'outro, e este teste pega isso',
      () {
        final Evolucao a = Evolucao(
          nome: 'A',
          estadoInicial: EstadoFormacao(<int, EstadoPessoa>{
            0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.firme),
          }),
          partes: <Parte>[
            Parte(
              ordem: 0,
              atribuicoes: <int, Atribuicao>{
                0: Atribuicao(
                  movimento: Catalogo.emFrenteMarche(
                    1,
                    aoTerminar: AoTerminarMarche.firme,
                  ),
                ),
              },
            ),
          ],
        );
        // B declara um início ERRADO de propósito — não bate com onde A
        // realmente termina ((0,-4), firme).
        final Evolucao b = Evolucao(
          nome: 'B',
          estadoInicial: EstadoFormacao(<int, EstadoPessoa>{
            0: const EstadoPessoa(x: 8, y: 0, dir: 0, cad: Cadencia.firme),
          }),
          partes: <Parte>[
            Parte(
              ordem: 0,
              atribuicoes: <int, Atribuicao>{
                0: Atribuicao(
                  movimento: Catalogo.emFrenteMarche(
                    1,
                    aoTerminar: AoTerminarMarche.marchando,
                  ),
                ),
              },
            ),
          ],
        );

        final ResultadoSequencia declarado = simularSequencia(<Evolucao>[
          a,
          b,
        ], ModoSequencia.declarado);
        final ResultadoSequencia encadeado = simularSequencia(<Evolucao>[
          a,
          b,
        ], ModoSequencia.encadeado);

        // O erro de planejamento é detectado nos dois modos (a checagem
        // de encadeamento roda sempre, independente do modo de playback).
        expect(declarado.diagnosticosEncadeamento, isNotEmpty);
        expect(encadeado.diagnosticosEncadeamento, isNotEmpty);

        // A evolução A é idêntica nos dois modos (nada a montante dela).
        expect(
          declarado.porEvolucao[0].porTique,
          encadeado.porEvolucao[0].porTique,
        );

        // B diverge a partir do seu PRIMEIRO tique: em declarado, parte
        // do (8,0) gravado; em encadeado, parte do (0,-4) real de A.
        final EstadoPessoa primeiroTiqueDeclarado =
            declarado.porEvolucao[1].porTique.first[0];
        final EstadoPessoa primeiroTiqueEncadeado =
            encadeado.porEvolucao[1].porTique.first[0];
        expect(
          (primeiroTiqueDeclarado.x, primeiroTiqueDeclarado.y),
          isNot((primeiroTiqueEncadeado.x, primeiroTiqueEncadeado.y)),
        );
        // 1º tique = meio tempo de deslocamento (2 quartos) a partir de
        // cada início: declarado parte do (8,0) gravado; encadeado parte
        // do (0,-4) real de A.
        expect((primeiroTiqueDeclarado.x, primeiroTiqueDeclarado.y), (8, -2));
        expect((primeiroTiqueEncadeado.x, primeiroTiqueEncadeado.y), (0, -6));

        // E o fim de B (1 tempo inteiro = 4 quartos) também diverge,
        // deslocado pela mesma diferença de origem.
        final EstadoPessoa fimDeclarado = declarado.porEvolucao[1].porTique.last[0];
        final EstadoPessoa fimEncadeado = encadeado.porEvolucao[1].porTique.last[0];
        expect((fimDeclarado.x, fimDeclarado.y), (8, -4));
        expect((fimEncadeado.x, fimEncadeado.y), (0, -8));
      },
    );

    test(
      '3. Não-vazamento: B isolado vs. B dentro de A+B em modo declarado '
      'é bit-idêntico',
      () {
        final Evolucao a = Evolucao(
          nome: 'A',
          estadoInicial: EstadoFormacao(<int, EstadoPessoa>{
            0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.firme),
          }),
          partes: <Parte>[
            Parte(
              ordem: 0,
              atribuicoes: <int, Atribuicao>{
                0: Atribuicao(
                  movimento: Catalogo.emFrenteMarche(
                    5,
                    aoTerminar: AoTerminarMarche.marchando,
                  ),
                ),
              },
            ),
          ],
        );
        final Evolucao b = Evolucao(
          nome: 'B',
          estadoInicial: EstadoFormacao(<int, EstadoPessoa>{
            0: const EstadoPessoa(x: 3, y: -2, dir: 4, cad: Cadencia.descansar),
          }),
          partes: <Parte>[
            Parte(
              ordem: 0,
              atribuicoes: <int, Atribuicao>{
                0: Atribuicao(movimento: Catalogo.sentido(tempos: 2)),
              },
            ),
            Parte(
              ordem: 1,
              atribuicoes: <int, Atribuicao>{
                0: Atribuicao(
                  movimento: Catalogo.emFrenteMarche(
                    2,
                    aoTerminar: AoTerminarMarche.firme,
                  ),
                ),
              },
            ),
          ],
        );

        final ResultadoSimulacao bIsolado = simular(b.estadoInicial, b.partes);
        final ResultadoSequencia sequencia = simularSequencia(<Evolucao>[
          a,
          b,
        ], ModoSequencia.declarado);
        final ResultadoSimulacao bDentroDaSequencia = sequencia.porEvolucao[1];

        expect(bDentroDaSequencia.porTique, bIsolado.porTique);
        expect(
          bDentroDaSequencia.diagnosticos.length,
          bIsolado.diagnosticos.length,
        );
      },
    );
  });
}
