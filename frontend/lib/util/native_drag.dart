// Cross-platform entry point for preventNativeDrag(). Resolves to a web-only
// implementation when compiled for the browser, and a no-op elsewhere.
export 'native_drag_noop.dart' if (dart.library.js_interop) 'native_drag_web.dart';
