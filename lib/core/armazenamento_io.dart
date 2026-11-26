import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<File?> _arquivo(String nome) async {
  try {
    // Arquivos internos (.json) ficam na pasta de suporte, como nas versões anteriores.
    final dir = nome.endsWith('.json') ? await getApplicationSupportDirectory() : await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, nome));
  } catch (_) {
    return null; // ambiente sem plugin (testes)
  }
}

Future<Uint8List?> ler(String nome) async {
  final f = await _arquivo(nome);
  if (f == null || !await f.exists()) return null;
  return f.readAsBytes();
}

Future<void> gravar(String nome, Uint8List? bytes) async {
  final f = await _arquivo(nome);
  if (f == null) return;
  if (bytes == null) {
    if (await f.exists()) await f.delete();
  } else {
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
  }
}
