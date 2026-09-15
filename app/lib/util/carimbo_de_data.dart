/// Carimbo `AAAA-MM-DD-HHmm` em hora LOCAL (não UTC) — nome de arquivo de
/// export, testável sem Firestore nem navegador (ver
/// `test/carimbo_de_data_test.dart`).
String carimboDeData(DateTime d) {
  String dois(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${dois(d.month)}-${dois(d.day)}-${dois(d.hour)}${dois(d.minute)}';
}
