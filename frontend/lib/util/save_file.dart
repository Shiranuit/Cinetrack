// Cross-platform "save bytes as a file". On the web this triggers a browser
// download; on mobile/desktop it writes the bytes to a file and opens it in the
// system viewer (from where the user can save/share). Resolves to the matching
// implementation at compile time.
export 'save_file_io.dart' if (dart.library.js_interop) 'save_file_web.dart';
