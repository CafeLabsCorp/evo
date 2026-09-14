import '../diagnostico.dart';
import '../estado.dart';
import '../geometria.dart';

/// Checagem 3 — Colisão: distância mínima contínua entre cada par de slots
/// durante cada tique, tudo em inteiro.
///
/// Dentro de um tique o movimento relativo entre duas pessoas é linear
/// (nosso motor já anda em incrementos constantes por tique). Com
/// `Δp` = diferença de posição no INÍCIO do tique e `Δv` = diferença de
/// deslocamento durante o tique:
///
/// `s* = clamp(−(Δp·Δv)/|Δv|², 0, 1)`, `dmin² = |Δp + s*·Δv|²`
///
/// Para não usar float, resolvemos por casos:
/// - `|Δv|² = 0` (velocidade relativa nula): `dmin² = |Δp|²`, exato.
/// - `s*` cai num extremo (0 ou 1): `dmin²` é a distância no início ou no
///   fim do tique, um inteiro exato.
/// - `s*` interior: `dmin²` vira uma fração exata `num/den` com
///   `den = |Δv|²` e `num = |Δp|²·|Δv|² − (Δp·Δv)²` — é exatamente a
///   identidade da spec (`|Δp|²|Δv|² − (Δp·Δv)² < T·|Δv|²`), usada aqui
///   por multiplicação cruzada para os dois limiares em vez de qualquer
///   divisão.
///
/// **Isso absorve travessia de célula "de graça":** duas pessoas trocando
/// de posição têm `dmin = 0` bem no meio do tique (`s* = 0.5` típico) e
/// caem no mesmo teste do caso interior — não existe um caso especial de
/// travessia em lugar nenhum deste arquivo.
///
/// Limiares em quartos², derivados de `unidadesPorCelula` (nunca
/// hardcoded): `dmin ≤ 0,5 célula` é erro, `0,5 < dmin < 1,0 célula` é
/// aviso agregável e desligável, `dmin ≥ 1,0 célula` é ok. O limiar
/// superior usa desigualdade ESTRITA de propósito — uma formação normal
/// tem espaçamento de exatamente 1 célula, e uma fileira mantém
/// `dmin² = unidadesPorCelula²` constante; com `≤` ali a checagem vira
/// ruído permanente em toda evolução comum.
///
/// Alerta de plataforma: em Flutter Web, `int` do Dart é `double` do JS,
/// seguro até 2^53. Pior caso de um campo de 20 células (80 quartos) dá
/// produtos da ordem de `80² × 80² ≈ 4×10^7` — folgado, mas só porque as
/// coordenadas são quartos-de-célula, não pixels; não hardcode uma unidade
/// menor aqui achando que "dá mais precisão".
List<Diagnostico> verificarColisoes(
  List<EstadoFormacao> comEstadoInicial, {
  bool avisosHabilitados = true,
}) {
  final int limiarErroQuartos2 =
      (unidadesPorCelula ~/ 2) * (unidadesPorCelula ~/ 2);
  final int limiarAvisoQuartos2 = unidadesPorCelula * unidadesPorCelula;

  final List<Diagnostico> diagnosticos = <Diagnostico>[];

  for (int i = 1; i < comEstadoInicial.length; i++) {
    final EstadoFormacao antes = comEstadoInicial[i - 1];
    final EstadoFormacao depois = comEstadoInicial[i];
    final int tiqueIndice = i - 1; // índice 0-based dentro de `porTique`

    final List<int> slots =
        antes.slots.toSet().intersection(depois.slots.toSet()).toList()..sort();

    for (int a = 0; a < slots.length; a++) {
      for (int b = a + 1; b < slots.length; b++) {
        final int slotA = slots[a];
        final int slotB = slots[b];

        final int axAntes = antes[slotA].x, ayAntes = antes[slotA].y;
        final int bxAntes = antes[slotB].x, byAntes = antes[slotB].y;
        final int axDepois = depois[slotA].x, ayDepois = depois[slotA].y;
        final int bxDepois = depois[slotB].x, byDepois = depois[slotB].y;

        final int dpx = axAntes - bxAntes;
        final int dpy = ayAntes - byAntes;
        final int dvx = (axDepois - axAntes) - (bxDepois - bxAntes);
        final int dvy = (ayDepois - ayAntes) - (byDepois - byAntes);

        final int dpSq = dpx * dpx + dpy * dpy;
        final int dvSq = dvx * dvx + dvy * dvy;

        int num;
        int den;
        if (dvSq == 0) {
          num = dpSq;
          den = 1;
        } else {
          final int dot = dpx * dvx + dpy * dvy;
          if (-dot <= 0) {
            // s* <= 0: mínimo já está no início do tique.
            num = dpSq;
            den = 1;
          } else if (-dot >= dvSq) {
            // s* >= 1: mínimo está no fim do tique.
            final int ex = dpx + dvx;
            final int ey = dpy + dvy;
            num = ex * ex + ey * ey;
            den = 1;
          } else {
            // s* interior: dmin² = (|Δp|²|Δv|² − (Δp·Δv)²) / |Δv|².
            num = dpSq * dvSq - dot * dot;
            den = dvSq;
          }
        }

        final bool ehErro = num <= limiarErroQuartos2 * den;
        final bool ehAviso = !ehErro && num < limiarAvisoQuartos2 * den;

        if (ehErro) {
          diagnosticos.add(
            DiagnosticoColisao(
              tique: tiqueIndice,
              slotA: slotA,
              slotB: slotB,
              distanciaMinimaQuadradoQuartos: num ~/ den,
              severidade: SeveridadeDiagnostico.erro,
            ),
          );
        } else if (ehAviso && avisosHabilitados) {
          diagnosticos.add(
            DiagnosticoColisao(
              tique: tiqueIndice,
              slotA: slotA,
              slotB: slotB,
              distanciaMinimaQuadradoQuartos: num ~/ den,
              severidade: SeveridadeDiagnostico.aviso,
            ),
          );
        }
      }
    }
  }

  return diagnosticos;
}
