import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Equivalente de `npm run colors` del panel: el sistema visual Brasa vive en
/// `splg_lib`; en `lib/` no se declaran colores propios ni se usa la paleta de
/// Material (rosa, azul, verde...). Blanco, negro y transparente quedan para
/// superposiciones neutras (cámara, sombras).
void main() {
  test('lib/ no tiene colores fuera de la marca', () {
    final allowed = {'white', 'black', 'transparent'};
    final hex = RegExp(r'Color\(\s*0x|Color\.from(ARGB|RGBO)\(');
    final material = RegExp(r'(?<![A-Za-z])Colors\.([a-zA-Z]+)');
    final offenders = <String>[];

    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('firebase_options.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (hex.hasMatch(line)) offenders.add('${f.path}:${i + 1}: $line');
        for (final m in material.allMatches(line)) {
          if (!allowed.contains(m.group(1))) {
            offenders.add('${f.path}:${i + 1}: $line');
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('no quedan marcas viejas en lib/ ni en los assets', () {
    final old = RegExp('y[e]nni|j[e]n+y ?gas', caseSensitive: false);
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (old.hasMatch(lines[i])) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
    expect(File('assets/logo.png').existsSync(), isFalse);
  });
}
