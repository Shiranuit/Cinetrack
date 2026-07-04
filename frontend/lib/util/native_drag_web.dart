import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Stop the browser from starting a native drag-and-drop (or text selection) when
/// the user presses on an element and drags with the mouse.
///
/// Without this, some browsers enter DnD mode on the first move and withhold every
/// `pointermove` for the duration of the drag, so Flutter never sees it and
/// horizontal rails can't be drag-scrolled. Flutter's own drags (ReorderableListView,
/// Dismissible, …) don't use native DnD, so suppressing it here is safe. Called once
/// at startup (web only).
void preventNativeDrag() {
  final prevent = ((web.Event e) => e.preventDefault()).toJS;
  // Capture phase so it fires before any default action, even from platform views.
  web.document.addEventListener('dragstart', prevent, true.toJS);
  web.document.addEventListener('selectstart', prevent, true.toJS);
}
