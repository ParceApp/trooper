class ClassDecl {
  ClassDecl({required this.name, required this.modifiers, required this.line});

  final String name;
  final Set<String> modifiers;
  final int line;
}

const _apiModifiers = {'final', 'base', 'interface', 'sealed'};

final _decl = RegExp(
  r'^\s*((?:(?:abstract|final|base|interface|sealed|mixin)\s+)*)class\s+([A-Za-z_]\w*)',
);

/// Line-based scan for class declarations; lines starting with `//` are skipped.
List<ClassDecl> findClassDeclarations(String source) {
  final result = <ClassDecl>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('//')) continue;
    final m = _decl.firstMatch(line);
    if (m == null) continue;
    result.add(ClassDecl(
      name: m.group(2)!,
      modifiers: m.group(1)!.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toSet(),
      line: i + 1,
    ));
  }
  return result;
}

/// True if the declaration restricts how it can be extended or implemented.
bool hasApiModifier(ClassDecl d) => d.modifiers.any(_apiModifiers.contains);
