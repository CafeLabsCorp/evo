/// Tamanho do salão de uma evolução, em células — espelha `campo?` do
/// schema de `evolucoes/{id}` (ver `firestore.rules`, `campoValido()`).
/// Opcional: ausente significa "usa o [Campo] default do motor" (20×20).
class CampoDoc {
  const CampoDoc({required this.larguraCelulas, required this.alturaCelulas});

  final int larguraCelulas;
  final int alturaCelulas;

  factory CampoDoc.doMapa(Map<String, dynamic> mapa) => CampoDoc(
    larguraCelulas: mapa['larguraCelulas'] as int,
    alturaCelulas: mapa['alturaCelulas'] as int,
  );

  Map<String, dynamic> paraMapa() => <String, dynamic>{
    'larguraCelulas': larguraCelulas,
    'alturaCelulas': alturaCelulas,
  };
}
