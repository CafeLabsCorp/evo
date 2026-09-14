import 'package:flutter/material.dart';

import 'tema/paleta_provisoria.dart';
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
      // Tema escuro PROVISÓRIO — ver `tema/paleta_provisoria.dart`. Some
      // inteiro quando o `design` entregar a paleta definitiva.
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: PaletaProvisoria.fundo,
        colorScheme: ColorScheme.fromSeed(
          seedColor: PaletaProvisoria.cinzaMedio,
          brightness: Brightness.dark,
          primary: PaletaProvisoria.claro,
          secondary: PaletaProvisoria.acento,
          surface: PaletaProvisoria.superficie,
          error: PaletaProvisoria.erro,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: PaletaProvisoria.superficie,
          foregroundColor: PaletaProvisoria.claro,
        ),
      ),
      home: const TelaPlayback(caminhoAsset: 'assets/evolucoes/exemplo.json'),
    );
  }
}
