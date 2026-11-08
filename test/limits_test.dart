import 'package:flutter_test/flutter_test.dart';
import 'package:wallet/limits.dart';

void main() {
  test('amounts under the 330 sat leaf floor are refused, 330 is accepted', () {
    expect(satsError(329), isNotNull);
    expect(satsError(1), isNotNull);
    expect(satsError(330), isNull);
    expect(satsError(null), isNotNull);
    expect(satsError(0), isNotNull);
  });

  test('there is no upper limit, only the floor', () {
    expect(satsError(5001), isNull);
    expect(satsError(100000000), isNull);
  });
}
