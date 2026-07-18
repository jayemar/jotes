import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jotes/models/note.dart';

Future<Color> _resolvedColor(
  WidgetTester tester, {
  required Brightness brightness,
  required int colorIndex,
}) async {
  late Color resolved;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Builder(
        builder: (context) {
          resolved = noteColorFor(context, colorIndex);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return resolved;
}

void main() {
  testWidgets('resolves to the light palette in a light theme',
      (tester) async {
    for (var i = 0; i < kNoteColors.length; i++) {
      final color =
          await _resolvedColor(tester, brightness: Brightness.light, colorIndex: i);
      expect(color, kNoteColors[i]);
    }
  });

  testWidgets('resolves to the dark palette in a dark theme, not the same '
      'light colors regardless of theme', (tester) async {
    for (var i = 0; i < kNoteColorsDark.length; i++) {
      final color =
          await _resolvedColor(tester, brightness: Brightness.dark, colorIndex: i);
      expect(color, kNoteColorsDark[i]);
      expect(color, isNot(kNoteColors[i]));
    }
  });

  test('the light and dark palettes are the same length', () {
    expect(kNoteColorsDark.length, kNoteColors.length);
  });
}
