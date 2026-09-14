import 'cadencia.dart';
import 'geometria.dart';

/// Estado completo de uma pessoa num tique, em quartos-de-célula.
///
/// Tudo `int`, sempre — zero `double` no estado, em qualquer tique, sem
/// exceção. `double` só existe do lado de fora (render) via
/// [Posicao.emCelulas].
class EstadoPessoa {
  const EstadoPessoa({
    required this.x,
    required this.y,
    required this.dir,
    required this.cad,
  });

  /// Posição X (Leste positivo), em quartos-de-célula.
  final int x;

  /// Posição Y (Sul positivo), em quartos-de-célula.
  final int y;

  /// Facing, setor 0..7, horário, 0 = Norte.
  final int dir;

  final Cadencia cad;

  Posicao get posicao => Posicao.quartos(x, y);

  EstadoPessoa copiarCom({int? x, int? y, int? dir, Cadencia? cad}) =>
      EstadoPessoa(
        x: x ?? this.x,
        y: y ?? this.y,
        dir: dir ?? this.dir,
        cad: cad ?? this.cad,
      );

  @override
  bool operator ==(Object other) =>
      other is EstadoPessoa &&
      other.x == x &&
      other.y == y &&
      other.dir == dir &&
      other.cad == cad;

  @override
  int get hashCode => Object.hash(x, y, dir, cad);

  @override
  String toString() => 'EstadoPessoa(x: $x, y: $y, dir: $dir, cad: $cad)';
}

/// Estado de todo o pelotão num tique.
///
/// **`slot` é identidade, não localização.** Um `slot` é "quem a pessoa é
/// na formação" (a posição que ela ocupa na hierarquia/organograma do
/// pelotão — ex. "3ª fileira, 2ª coluna" como PAPEL), não "onde ela está
/// fisicamente agora". Duas pessoas podem trocar de célula no meio de uma
/// evolução (é literalmente o que a checagem de colisão/travessia lida) sem
/// trocar de `slot`. Essa é a confusão nº 1 que o próximo dev vai ter: não
/// assuma que `slot` dá para derivar de `(x, y)`, e não assuma que
/// `(x, y)` de um slot fica "perto" do slot vizinho numericamente.
class EstadoFormacao {
  const EstadoFormacao(this.porSlot);

  final Map<int, EstadoPessoa> porSlot;

  Iterable<int> get slots => porSlot.keys;

  EstadoPessoa operator [](int slot) {
    final EstadoPessoa? estado = porSlot[slot];
    if (estado == null) {
      throw StateError(
        'Slot $slot não tem estado definido neste tique — isso é bug do '
        'compilador, não existe estado "pausado" (ver Parte/Atribuicao).',
      );
    }
    return estado;
  }

  EstadoFormacao copiarComSlot(int slot, EstadoPessoa estado) =>
      EstadoFormacao(<int, EstadoPessoa>{...porSlot, slot: estado});

  @override
  bool operator ==(Object other) {
    if (other is! EstadoFormacao) return false;
    if (other.porSlot.length != porSlot.length) return false;
    for (final MapEntry<int, EstadoPessoa> entrada in porSlot.entries) {
      if (other.porSlot[entrada.key] != entrada.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
    porSlot.entries.map(
      (MapEntry<int, EstadoPessoa> e) => Object.hash(e.key, e.value),
    ),
  );
}
