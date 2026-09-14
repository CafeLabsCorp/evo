import 'package:evo_motor/evo_motor.dart';
import 'package:test/test.dart';

/// Propriedade 11 — ancoragem absoluta.
///
/// As outras 10 propriedades do motor (fechamento de quadrado, paridade,
/// integralidade, determinismo, soma de deltas...) são todas RELATIVAS:
/// comparam o motor consigo mesmo. Isso as torna invariantes sob
/// REFLEXÃO — trocar direita↔esquerda em todo o catálogo (espelhar a
/// convenção horária de `deltaSetor`) passaria incólume por todas elas.
/// Uma implementação internamente consistente mas "canhota" fecharia
/// quadrados e octógonos do mesmo jeito, só giraria pro lado errado na
/// tela.
///
/// Este arquivo fixa a quiralidade certa contra a realidade física, com
/// os valores esperados ESCRITOS COMO LITERAIS aqui — nunca lidos de
/// `Catalogo` (ex. o campo `deltaSetor` interno de `_volverParado`) nem
/// de `deltaPorTiquePorSetor`. Se o teste recalculasse a partir da mesma
/// tabela que o motor usa pra processar, ficaria cego ao mesmo
/// espelhamento que existe pra detectar.
void main() {
  group('Propriedade 11 — ancoragem absoluta (referência: setor 0 = Norte)', () {
    test('G(+1) a partir do setor 0 termina no setor 1', () {
      const EstadoPessoa inicial = EstadoPessoa(
        x: 0,
        y: 0,
        dir: 0,
        cad: Cadencia.firme,
      );
      final EstadoPessoa fim = executarSegmentos(
        inicial,
        const <Segmento>[Giro(1)],
        cadenciaFinal: Cadencia.firme,
      ).estadoFinal;
      expect(fim.dir, 1); // literal — não lido de nenhuma tabela do motor.
    });

    test('"Direita volver" a partir do Norte termina no setor 2 (Leste)', () {
      const EstadoPessoa inicial = EstadoPessoa(
        x: 0,
        y: 0,
        dir: 0,
        cad: Cadencia.firme,
      );
      final EstadoPessoa fim = executarSegmentos(
        inicial,
        Catalogo.direitaVolverParado().segmentosPara(Cadencia.firme),
        cadenciaFinal: Cadencia.firme,
      ).estadoFinal;
      expect(fim.dir, 2); // literal.
    });

    test('"Esquerda volver" a partir do Norte termina no setor 6 (Oeste)', () {
      const EstadoPessoa inicial = EstadoPessoa(
        x: 0,
        y: 0,
        dir: 0,
        cad: Cadencia.firme,
      );
      final EstadoPessoa fim = executarSegmentos(
        inicial,
        Catalogo.esquerdaVolverParado().segmentosPara(Cadencia.firme),
        cadenciaFinal: Cadencia.firme,
      ).estadoFinal;
      expect(fim.dir, 6); // literal.
    });
  });
}
