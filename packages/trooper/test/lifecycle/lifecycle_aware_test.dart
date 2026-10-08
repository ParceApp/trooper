import 'package:test/test.dart';
import 'package:trooper/src/lifecycle/lifecycle_aware.dart';

class _TestLifecycleComponent with LifecycleAware {}

void main() {
  group('LifecycleAware', () {
    test('default no-op hooks can be executed safely', () async {
      final component = _TestLifecycleComponent();

      await component.initialize();
      await component.didChangeDependencies();
      await component.recover();
      await component.pause();
      await component.resume();
      await component.dispose();
    });
  });
}
