/// Backend base URL. Override at build/run time with:
///   flutter run --dart-define=API_BASE=http://10.0.2.2:8080   (Android emulator)
class Config {
  static const apiBase =
      String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8080');
}
