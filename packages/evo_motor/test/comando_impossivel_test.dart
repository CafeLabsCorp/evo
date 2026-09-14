import 'package:evo_motor/evo_motor.dart';
import 'package:test/test.dart';

void main() {
  group('Checagem 1 — Comando impossível e isolamento', () {
    test(
      'slot em firme recebendo "direita volver em marcha" (exige marchando): '
      'sem exceção, cai em continuação implícita, 1 diagnóstico completo',
      () {
        final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
          0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.firme),
        });
        final Parte parte = Parte(
          ordem: 0,
          nome: 'Parte única',
          atribuicoes: <int, Atribuicao>{
            0: Atribuicao(movimento: Catalogo.direitaVolverMarcha()),
          },
        );

        late ResultadoSimulacao r;
        expect(() => r = simular(inicial, <Parte>[parte]), returnsNormally);

        final erros = r.diagnosticos
            .whereType<DiagnosticoComandoImpossivel>()
            .toList();
        expect(erros, hasLength(1));
        final DiagnosticoComandoImpossivel d = erros.first;
        // Diagnóstico completo: slot, parte, comando e estado exigido vs
        // real.
        expect(d.slot, 0);
        expect(d.indiceParte, 0);
        expect(d.nomeMovimento, 'Direita volver (marcha)');
        expect(d.cadenciaExigida, <Cadencia>{Cadencia.marchando});
        expect(d.cadenciaAtual, Cadencia.firme);
        expect(d.severidade, SeveridadeDiagnostico.erro);

        // Continuação implícita: fica parado e firme, o giro NÃO acontece.
        for (final EstadoFormacao f in r.porTique) {
          expect(f[0].dir, 0);
          expect(f[0].cad, Cadencia.firme);
          expect((f[0].x, f[0].y), (0, 0));
        }
      },
    );

    test(
      'isolamento: outro slot com comando válido na mesma parte segue normal',
      () {
        final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
          0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.firme),
          1: const EstadoPessoa(x: 4, y: 0, dir: 0, cad: Cadencia.marchando),
        });
        final Parte parte = Parte(
          ordem: 0,
          atribuicoes: <int, Atribuicao>{
            0: Atribuicao(movimento: Catalogo.direitaVolverMarcha()),
            1: Atribuicao(movimento: Catalogo.direitaVolverMarcha()),
          },
        );
        final ResultadoSimulacao r = simular(inicial, <Parte>[parte]);

        final erros = r.diagnosticos
            .whereType<DiagnosticoComandoImpossivel>()
            .toList();
        expect(erros, hasLength(1));
        expect(erros.single.slot, 0);

        // Slot 1 (válido, marchando) girou normalmente pro setor 2.
        final EstadoPessoa fimSlot1 = r.porTique.last[1];
        expect(fimSlot1.dir, 2);
        expect(fimSlot1.cad, Cadencia.firme);

        // Slot 0 (impossível) ficou parado e firme.
        final EstadoPessoa fimSlot0 = r.porTique.last[0];
        expect(fimSlot0.dir, 0);
        expect(fimSlot0.cad, Cadencia.firme);
      },
    );

    test(
      'dois comandos impossíveis em slots diferentes → 2 diagnósticos '
      'independentes; a parte seguinte roda normalmente pros dois',
      () {
        final EstadoFormacao inicial = EstadoFormacao(<int, EstadoPessoa>{
          0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.firme),
          1: const EstadoPessoa(x: 4, y: 0, dir: 0, cad: Cadencia.descansar),
        });
        final Parte parteComErro = Parte(
          ordem: 0,
          atribuicoes: <int, Atribuicao>{
            // Slot 0: firme não é marchando — impossível.
            0: Atribuicao(movimento: Catalogo.direitaVolverMarcha()),
            // Slot 1: descansar não é firme/marcandoPasso — impossível
            // pro "bater o ritmo".
            1: Atribuicao(movimento: Catalogo.baterORitmo()),
          },
        );
        final Parte parteSeguinte = Parte(
          ordem: 1,
          atribuicoes: <int, Atribuicao>{
            0: Atribuicao(movimento: Catalogo.sentido(tempos: 1)),
            1: Atribuicao(movimento: Catalogo.sentido(tempos: 1)),
          },
        );

        final ResultadoSimulacao r = simular(inicial, <Parte>[
          parteComErro,
          parteSeguinte,
        ]);

        final erros = r.diagnosticos
            .whereType<DiagnosticoComandoImpossivel>()
            .where((d) => d.severidade == SeveridadeDiagnostico.erro)
            .toList();
        expect(erros, hasLength(2));
        expect(erros.map((d) => d.slot).toSet(), <int>{0, 1});
        // Diagnósticos atribuíveis e independentes — cada um aponta o
        // slot/comando certo, não um agregado genérico.
        final DiagnosticoComandoImpossivel doSlot0 = erros.firstWhere(
          (d) => d.slot == 0,
        );
        final DiagnosticoComandoImpossivel doSlot1 = erros.firstWhere(
          (d) => d.slot == 1,
        );
        expect(doSlot0.nomeMovimento, 'Direita volver (marcha)');
        expect(doSlot1.nomeMovimento, 'Bater o ritmo');

        // A parte seguinte roda normal pros dois — "Sentido" aceita
        // qualquer cadência de entrada.
        final EstadoFormacao ultimoTique = r.porTique.last;
        expect(ultimoTique[0].cad, Cadencia.firme);
        expect(ultimoTique[1].cad, Cadencia.firme);
      },
    );
  });
}
