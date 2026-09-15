import 'package:evo_app/util/carimbo_de_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formata AAAA-MM-DD-HHmm com zero à esquerda', () {
    expect(carimboDeData(DateTime(2026, 9, 4, 8, 5)), '2026-09-04-0805');
  });

  test('hora local: meia-noite e mês/dia de dois dígitos', () {
    expect(carimboDeData(DateTime(2027, 1, 1, 0, 0)), '2027-01-01-0000');
  });
}
