import 'package:flutter/material.dart';

import 'telas/tela_playback.dart';

const Color _corNavy = Color(0xFF1E3A5F);
const Color _corAmbar = Color(0xFFFFB300);

void main() {
  runApp(const EvoApp());
}

class EvoApp extends StatelessWidget {
  const EvoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Evo Lab',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: _corNavy,
          primary: _corNavy,
          secondary: _corAmbar,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: _corNavy,
          foregroundColor: Colors.white,
        ),
      ),
      home: const TelaPlayback(caminhoAsset: 'assets/evolucoes/exemplo.json'),
    );
  }
}
