// Web implementation: trigger a browser download of the file.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';

Future<void> saveTextFile(String filename, String content, {String text = ''}) async {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], 'text/plain');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

// shares a picture with the browser's share sheet (phones), else downloads it
Future<void> shareImage(String filename, Uint8List bytes, {String text = ''}) async {
  try {
    final result = await Share.shareXFiles([XFile.fromData(bytes, mimeType: 'image/png', name: filename)], text: text);
    if (result.status != ShareResultStatus.unavailable) return;
  } catch (_) {}
  await saveImage(filename, bytes);
}

// downloads a picture
Future<void> saveImage(String filename, Uint8List bytes) async {
  final blob = html.Blob([bytes], 'image/png');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
