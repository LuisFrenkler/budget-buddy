// The language of the legal texts, without Flutter: the server imports the
// legal texts to serve them as web pages and must compile as plain Dart. The
// app sets [isDe] to its own language at start (see main.dart); the server
// keeps the default (German, the binding version).
class LegalLang {
  static bool Function() isDe = () => true;
}
