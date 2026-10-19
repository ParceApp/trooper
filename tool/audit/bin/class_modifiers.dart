import 'dart:io';

import 'package:trooper_audit_tool/class_modifiers.dart';

/// Usage: `dart run bin/class_modifiers.dart <dir>...`
/// Prints public classes without final/base/interface/sealed as `path:line Name`.
void main(List<String> dirs) {
  var total = 0;
  for (final dir in dirs) {
    final files = Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      for (final d in findClassDeclarations(f.readAsStringSync())) {
        if (d.name.startsWith('_') || hasApiModifier(d)) continue;
        total++;
        final mods = d.modifiers.isEmpty ? '' : ' (${d.modifiers.join(' ')})';
        stdout.writeln('${f.path}:${d.line} ${d.name}$mods');
      }
    }
  }
  stdout.writeln('total: $total');
}
