// Mobile/desktop implementation: write a temp file and open the share sheet.
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> saveTextFile(String filename, String content, {String text = ''}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsString(content);
  await Share.shareXFiles([XFile(file.path)], text: text);
}

// shares a picture, e.g. the recap story, through the share sheet
Future<void> shareImage(String filename, Uint8List bytes, {String text = ''}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes);
  await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')], text: text);
}

// phones have no download folder: saving goes through the share sheet
Future<void> saveImage(String filename, Uint8List bytes) => shareImage(filename, bytes);
