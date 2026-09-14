import 'package:evo_motor/evo_motor.dart';
import 'package:test/test.dart';

EstadoFormacao _f(Map<int, EstadoPessoa> slots) => EstadoFormacao(slots);

const EstadoPessoa _base = EstadoPessoa(
  x: 0,
  y: 0,
  dir: 0,
  cad: Cadencia.firme,
);

void main() {
  group('Checagem 2 — Encadeamento: 7 casos', () {
    test('1. Baseline sem divergência: nenhum diagnóstico', () {
      final EstadoFormacao fim = _f(<int, EstadoPessoa>{0: _base, 1: _base});
      final EstadoFormacao proximo = _f(<int, EstadoPessoa>{0: _base, 1: _base});
      expect(verificarEncadeamento(fim, proximo), isEmpty);
    });

    test('2. Divergência só de posição', () {
      final EstadoFormacao fim = _f(<int, EstadoPessoa>{0: _base});
      final EstadoFormacao proximo = _f(<int, EstadoPessoa>{
        0: const EstadoPessoa(x: 4, y: 0, dir: 0, cad: Cadencia.firme),
      });
      final diags = verificarEncadeamento(fim, proximo);
      expect(diags, hasLength(1));
      final DiagnosticoEncadeamento d = diags.single as DiagnosticoEncadeamento;
      expect(d.motivo, contains('posição diverge'));
      expect(d.motivo, isNot(contains('direção diverge')));
      expect(d.motivo, isNot(contains('cadência diverge')));
    });

    test('3. Divergência só de direção', () {
      final EstadoFormacao fim = _f(<int, EstadoPessoa>{0: _base});
      final EstadoFormacao proximo = _f(<int, EstadoPessoa>{
        0: const EstadoPessoa(x: 0, y: 0, dir: 2, cad: Cadencia.firme),
      });
      final diags = verificarEncadeamento(fim, proximo);
      expect(diags, hasLength(1));
      final DiagnosticoEncadeamento d = diags.single as DiagnosticoEncadeamento;
      expect(d.motivo, contains('direção diverge'));
      expect(d.motivo, isNot(contains('posição diverge')));
      expect(d.motivo, isNot(contains('cadência diverge')));
    });

    test(
      '4. Divergência só de cadência (A termina marchando, B exige firme) — '
      'diagnóstico DISTINTO dos outros três, é o diferencial do produto',
      () {
        final EstadoFormacao fim = _f(<int, EstadoPessoa>{
          0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.marchando),
        });
        final EstadoFormacao proximo = _f(<int, EstadoPessoa>{0: _base});
        final diags = verificarEncadeamento(fim, proximo);
        expect(diags, hasLength(1));
        final DiagnosticoEncadeamento d =
            diags.single as DiagnosticoEncadeamento;
        expect(d.motivo, contains('cadência diverge'));
        expect(d.motivo, isNot(contains('posição diverge')));
        expect(d.motivo, isNot(contains('direção diverge')));
        // O diferencial: a mensagem nomeia as DUAS cadências envolvidas,
        // não um "estado diverge" genérico que esconderia qual é o
        // problema.
        expect(d.motivo, contains('marchando'));
        expect(d.motivo, contains('firme'));
      },
    );

    test('5. Slot desaparecendo (presente em A, ausente no início exigido de B)', () {
      final EstadoFormacao fim = _f(<int, EstadoPessoa>{0: _base, 1: _base});
      final EstadoFormacao proximo = _f(<int, EstadoPessoa>{0: _base});
      final diags = verificarEncadeamento(fim, proximo);
      expect(diags, hasLength(1));
      final DiagnosticoEncadeamento d = diags.single as DiagnosticoEncadeamento;
      expect(d.slot, 1);
      expect(d.motivo, contains('ausente no início exigido'));
    });

    test(
      '6. Slot novo aparecendo (ausente em A, exigido no início de B) — '
      'decisão do produto: AVISO, não erro (pode ser entrada legítima de '
      'membro novo)',
      () {
        final EstadoFormacao fim = _f(<int, EstadoPessoa>{0: _base});
        final EstadoFormacao proximo = _f(<int, EstadoPessoa>{0: _base, 1: _base});
        final diags = verificarEncadeamento(fim, proximo);
        expect(diags, hasLength(1));
        final DiagnosticoEncadeamento d =
            diags.single as DiagnosticoEncadeamento;
        expect(d.slot, 1);
        expect(d.motivo, contains('ausente no fim'));
        expect(d.severidade, SeveridadeDiagnostico.aviso);
      },
    );

    test(
      '7. Divergências independentes simultâneas em slots diferentes: '
      'diagnósticos separados e atribuíveis, nunca um agregado',
      () {
        final EstadoFormacao fim = _f(<int, EstadoPessoa>{
          0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.marchando),
          1: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.firme),
        });
        final EstadoFormacao proximo = _f(<int, EstadoPessoa>{
          0: const EstadoPessoa(x: 0, y: 0, dir: 0, cad: Cadencia.firme),
          1: const EstadoPessoa(x: 8, y: 0, dir: 0, cad: Cadencia.firme),
        });
        final diags = verificarEncadeamento(fim, proximo)
            .cast<DiagnosticoEncadeamento>();
        expect(diags, hasLength(2));
        final DiagnosticoEncadeamento doSlot0 = diags.firstWhere(
          (d) => d.slot == 0,
        );
        final DiagnosticoEncadeamento doSlot1 = diags.firstWhere(
          (d) => d.slot == 1,
        );
        expect(doSlot0.motivo, contains('cadência diverge'));
        expect(doSlot0.motivo, isNot(contains('posição diverge')));
        expect(doSlot1.motivo, contains('posição diverge'));
        expect(doSlot1.motivo, isNot(contains('cadência diverge')));
      },
    );
  });
}
