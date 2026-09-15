import 'package:firebase_auth/firebase_auth.dart';

/// Wrapper fino sobre `FirebaseAuth` — só o que o Evo Lab usa: Google
/// Sign-In via popup (é assim que `firebase_auth` faz login social em
/// Flutter Web; não precisa do pacote `google_sign_in`, que existe para
/// mobile) e logout. Nenhum dado de perfil (nome, foto) é lido daqui para
/// gravar em lugar nenhum — `photoURL` em particular NUNCA é persistido
/// (docs/DADOS.md 2.1): o único uso do perfil Google é a própria sessão do
/// Firebase Auth.
class ServicoAutenticacao {
  ServicoAutenticacao({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Stream<User?> mudancasDeUsuario() => _auth.authStateChanges();

  User? get usuarioAtual => _auth.currentUser;

  /// Login por popup do Google. Falha (usuário fechou o popup, provedor
  /// desabilitado no console, domínio não autorizado) propaga como
  /// [FirebaseAuthException] — a tela de login decide a mensagem.
  Future<UserCredential> entrarComGoogle() =>
      _auth.signInWithPopup(GoogleAuthProvider());

  Future<void> sair() => _auth.signOut();
}
