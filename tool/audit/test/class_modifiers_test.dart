import 'package:test/test.dart';
import 'package:trooper_audit_tool/class_modifiers.dart';

void main() {
  test('finds public classes without API modifier, ignores private and doc comments', () {
    const src = 'class A {}\nfinal class B {}\nabstract class C {}\n'
        'abstract interface class D {}\nsealed class E {}\nbase class F {}\n'
        'class _G {}\n/// class H {}\nmixin class I {}\n';
    final missing = findClassDeclarations(src)
        .where((d) => !d.name.startsWith('_') && !hasApiModifier(d));
    expect(missing.map((d) => d.name), ['A', 'C', 'I']);
  });

  test('records line numbers and modifiers', () {
    final decls = findClassDeclarations('\n  abstract base class X<T> extends Y {}\n');
    expect(decls.single.line, 2);
    expect(decls.single.modifiers, {'abstract', 'base'});
    expect(decls.single.name, 'X');
  });
}
