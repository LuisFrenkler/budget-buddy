import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:budget_buddy/services/avatar_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _photo(int w, int h) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFF336699));
  final img = await rec.endRecording().toImage(w, h);
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

Future<Size> _size(Uint8List data) async {
  final codec = await ui.instantiateImageCodec(data);
  final img = (await codec.getNextFrame()).image;
  return Size(img.width.toDouble(), img.height.toDouble());
}

void main() {
  testWidgets('a big photo shrinks to 256 px on its short edge', (tester) async {
    await tester.runAsync(() async {
      final out = await AvatarService.shrink(await _photo(3000, 2000));
      expect(await _size(out), const Size(384, 256));
    });
  });

  testWidgets('a small photo is kept as it is', (tester) async {
    await tester.runAsync(() async {
      final small = await _photo(120, 120);
      expect(await AvatarService.shrink(small), same(small));
    });
  });

  testWidgets('something that is not an image is refused', (tester) async {
    await tester.runAsync(() async {
      expect(() => AvatarService.shrink(Uint8List.fromList(List.filled(64, 7))), throwsA(isA<String>()));
    });
  });
}
