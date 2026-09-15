import 'package:evo_app/auth/servico_autenticacao.dart';
import 'package:evo_app/telas/portao_app.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PortaoApp — auth gate → bootstrap de clube → navegação real', () {
    testWidgets('deslogado mostra a tela de entrar (Google)', (
      WidgetTester tester,
    ) async {
      final MockFirebaseAuth mockAuth = MockFirebaseAuth();
      await tester.pumpWidget(
        MaterialApp(
          home: PortaoApp(
            servicoAutenticacao: ServicoAutenticacao(auth: mockAuth),
            firestore: FakeFirebaseFirestore(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Entrar com Google'), findsOneWidget);
      expect(find.text('Pelotões'), findsNothing);
    });

    testWidgets(
      'logado: bootstrap cria o clube sozinho e chega na lista de '
      'pelotões (vazia) sem nenhuma ação extra do usuário',
      (WidgetTester tester) async {
        final MockUser usuario = MockUser(uid: 'uid-teste', email: 'teste@example.com');
        final MockFirebaseAuth mockAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: usuario,
        );
        final FakeFirebaseFirestore db = FakeFirebaseFirestore();

        await tester.pumpWidget(
          MaterialApp(
            home: PortaoApp(
              servicoAutenticacao: ServicoAutenticacao(auth: mockAuth),
              firestore: db,
            ),
          ),
        );

        // Carregando (auth) → carregando (bootstrap) → tela real.
        await tester.pump();
        await tester.pump();
        await tester.pump();

        expect(find.text('Pelotões'), findsOneWidget);
        expect(find.text('Nenhum pelotão ainda'), findsOneWidget);

        // O bootstrap de fato criou o clube (idempotência já é coberta em
        // `servico_clube_test.dart`; aqui o que importa é que a NAVEGAÇÃO
        // reage a ele sem pedir nada ao usuário).
        expect((await db.collection('clubes').get()).docs, hasLength(1));
        final Map<String, dynamic> clube = (await db.collection('clubes').get()).docs.single.data();
        expect(clube['dono'], 'uid-teste');
      },
    );

    testWidgets('botão "Sair" desloga e volta para a tela de entrar', (
      WidgetTester tester,
    ) async {
      final MockUser usuario = MockUser(uid: 'uid-2');
      final MockFirebaseAuth mockAuth = MockFirebaseAuth(signedIn: true, mockUser: usuario);
      await tester.pumpWidget(
        MaterialApp(
          home: PortaoApp(
            servicoAutenticacao: ServicoAutenticacao(auth: mockAuth),
            firestore: FakeFirebaseFirestore(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Pelotões'), findsOneWidget);

      await tester.tap(find.byTooltip('Sair'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Entrar com Google'), findsOneWidget);
    });
  });
}
