import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'telas/portao_app.dart';
import 'tema/paleta.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Cache local persistente — sobrevive a fechar a aba/navegador, não só à
  // sessão em memória. É o que faz o app continuar MOSTRANDO dado já visto
  // (somente leitura) num túnel/elevador/wifi ruim, em vez de uma tela em
  // branco só porque a rede caiu (ver `dados/falha_persistencia.dart`,
  // `ForaDoAr`, e `*Doc.pendente`/`hasPendingWrites` para o outro lado
  // disto — escrita feita offline que ainda não confirmou).
  //
  // Nota de nomenclatura: o handoff pede "persistentLocalCache", que é o
  // nome da API do SDK JS/nativo do Firestore (`persistentLocalCache()`).
  // O plugin Flutter (`cloud_firestore`) não expõe essa função — o
  // equivalente aqui é `Settings(persistenceEnabled: true)`, mesma
  // funcionalidade (cache local persistente em IndexedDB, no caso Web),
  // API com outro nome.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

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
      home: const PortaoApp(),
    );
  }
}
