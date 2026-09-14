import 'package:flutter/material.dart';

import 'tema/paleta.dart';
import 'telas/tela_playback.dart';

void main() {
  runApp(const EvoApp());
}

class EvoApp extends StatelessWidget {
  const EvoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Evo Lab',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: Paleta.fundo,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Paleta.cinzaMedio,
          brightness: Brightness.dark,
          primary: Paleta.claro,
          secondary: Paleta.acento,
          surface: Paleta.superficie,
          error: Paleta.erro,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Paleta.superficie,
          foregroundColor: Paleta.claro,
        ),
      ),
      home: const TelaPlayback(caminhoAsset: 'assets/evolucoes/exemplo.json'),
    );
  }
}
