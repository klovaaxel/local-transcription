import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/perf/device_bench.dart';

void main() {
  test('the CPU benchmark returns a positive throughput score', () async {
    final score = await DeviceBench.cpuScoreMbs(
      duration: const Duration(milliseconds: 200),
    );
    expect(score, greaterThan(0));
  });
}
