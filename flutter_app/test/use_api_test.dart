import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:dclix_app/widgets/use_api.dart';

void main() {
  test('manual resources start idle and can perform their first search', () async {
    final answer = Completer<int>();
    var calls = 0;
    final resource = ApiResource<int>(() {
      calls++;
      return answer.future;
    }, autoRun: false);

    expect(resource.loading, isFalse,
        reason: 'a manual Search button must be enabled before its first request');
    expect(calls, 0);

    final pending = resource.reload();
    expect(resource.loading, isTrue);
    expect(calls, 1);
    answer.complete(42);
    await pending;

    expect(resource.loading, isFalse);
    expect(resource.data, 42);
    expect(resource.error, isNull);
    resource.dispose();
  });
}
