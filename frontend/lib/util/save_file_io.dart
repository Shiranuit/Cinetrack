import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Write [bytes] to a temp file named [filename] and open it in the system viewer,
/// from where the user can save it to their photos / files or share it.
Future<void> saveBytes(List<int> bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes);
  await OpenFilex.open(file.path);
}
