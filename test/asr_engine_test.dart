import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_local/asr/asr_engine.dart';
import 'package:lecture_local/asr/wav_windows.dart';

const _sampleRate = 16000;

/// `record` hands the isolate PCM about every 128 ms, so 2048 samples is one
/// callback and the traces below run at the rate the isolate sees.
const _callback = _sampleRate * 128 ~/ 1000;

/// What the live path keeps: one decode window plus the hop of history it reads
/// back into. Spelled from the shared geometry so the two paths cannot drift.
const _keep = windowSamples + hopSamples;

/// The synthetic lecture. Distinct often enough that the first value of a
/// window says where in the stream that window was taken from.
double _sample(int i) => ((i % 30011) - 15011) / 32768.0;

Float32List _chunk(int at, int count) {
  final out = Float32List(count);
  for (var i = 0; i < count; i++) {
    out[i] = _sample(at + i);
  }
  return out;
}

/// The buffer the isolate kept before this change, and the window it read from
/// it, transcribed from `pushFloats` and `_concat` as they were. Every case
/// below drives both and compares what came out, so "the samples handed to the
/// recognizer are the same" is checked rather than argued.
class _LegacyRun {
  _LegacyRun(this.buffer, this.window, this.sinceWindow);

  final Float32List buffer;
  final Float32List? window;
  final int sinceWindow;
}

class _LegacyTrace {
  _LegacyTrace(this.live, this.legacy, this.liveFlush, this.legacyFlush);

  final List<_LiveRun> live;
  final List<_LegacyRun> legacy;
  final Float32List liveFlush;
  final Float32List legacyFlush;

  Iterable<Float32List> get liveWindows =>
      live.map((p) => p.window).whereType<Float32List>();

  Iterable<Float32List> get legacyWindows =>
      legacy.map((p) => p.window).whereType<Float32List>();
}

class _LiveRun {
  _LiveRun(this.length, this.window, this.sinceWindow);

  final int length;
  final Float32List? window;
  final int sinceWindow;
}

_LegacyTrace _trace(List<Float32List> chunks) {
  final buffer = RollingBuffer();
  final live = <_LiveRun>[];
  final legacy = <_LegacyRun>[];

  var rolling = Float32List(0);
  var liveSince = 0;
  var legacySince = 0;
  for (final chunk in chunks) {
    buffer.add(chunk);
    buffer.trim();
    liveSince += chunk.length;
    Float32List? liveWindow;
    if (liveSince >= hopSamples && buffer.length >= windowSamples) {
      liveWindow = buffer.window(windowSamples);
      liveSince = 0;
    }
    live.add(_LiveRun(buffer.length, liveWindow, liveSince));

    rolling = _legacyConcat(rolling, chunk);
    legacySince += chunk.length;
    Float32List? legacyWindow;
    if (legacySince >= hopSamples && rolling.length >= windowSamples) {
      legacyWindow = rolling.sublist(rolling.length - windowSamples);
      legacySince = 0;
    }
    legacy.add(_LegacyRun(rolling, legacyWindow, legacySince));
  }
  return _LegacyTrace(live, legacy, buffer.toSamples(), rolling);
}

Float32List _legacyConcat(Float32List a, Float32List b) {
  if (a.isEmpty) {
    return b;
  }
  final out = Float32List(a.length + b.length);
  out.setAll(0, a);
  out.setAll(a.length, b);
  const keep = windowSamples + hopSamples;
  if (out.length <= keep) {
    return out;
  }
  return Float32List.fromList(out.sublist(out.length - keep));
}

/// Bit pattern, not value: `window` hands the recognizer a copy, and a copy
/// that went through a `double` would compare equal while not being the same
/// bytes. -2 is "different lengths", -1 is "identical".
int _firstBitDifference(Float32List a, Float32List b) {
  if (a.length != b.length) {
    return -2;
  }
  final left = Uint32List.view(a.buffer, a.offsetInBytes, a.length);
  final right = Uint32List.view(b.buffer, b.offsetInBytes, b.length);
  for (var i = 0; i < a.length; i++) {
    if (left[i] != right[i]) {
      return i;
    }
  }
  return -1;
}

void _expectSameSamples(Float32List actual, Float32List expected, String what) {
  final diff = _firstBitDifference(actual, expected);
  expect(
    diff,
    -1,
    reason:
        '$what (a -2 means different lengths, '
        '${actual.length} against ${expected.length})',
  );
}

void _expectSameStream(_LegacyTrace trace, String what) {
  expect(
    trace.live.map((p) => p.length).toList(),
    trace.legacy.map((p) => p.buffer.length).toList(),
    reason: '$what: a push left the two runs at different lengths',
  );
  expect(
    trace.live.map((p) => p.sinceWindow).toList(),
    trace.legacy.map((p) => p.sinceWindow).toList(),
    reason: '$what: the two runs disagreed about the next hop',
  );
  final live = trace.liveWindows.toList();
  final legacy = trace.legacyWindows.toList();
  expect(live, hasLength(legacy.length), reason: '$what: window count');
  for (var i = 0; i < live.length; i++) {
    _expectSameSamples(live[i], legacy[i], '$what, window $i');
  }
  _expectSameSamples(
    trace.liveFlush,
    trace.legacyFlush,
    '$what, what flush hands the window walk',
  );
}

/// [pushes] callbacks of [_callback] samples: a stream of the synthetic lecture.
List<Float32List> _stream(int pushes) => <Float32List>[
  for (var p = 0; p < pushes; p++) _chunk(p * _callback, _callback),
];

void main() {
  group('the rolling buffer hands the recognizer what the old one did', () {
    test('a lecture that never reaches the kept length', () {
      final pushes = 250;
      final trace = _trace(_stream(pushes));

      // Below the boundary on purpose: the kept length is 35 s and this is 32,
      // so nothing is ever trimmed here and the comparison cannot hide behind
      // a trim that happened to land in the same place.
      expect(pushes * _callback, lessThan(_keep));
      _expectSameStream(trace, '32 s lecture');
      expect(
        trace.live.last.length,
        pushes * _callback,
        reason: 'nothing should be dropped before the boundary',
      );
      expect(
        trace.liveWindows,
        hasLength(1),
        reason: '32 s is one window, and the second hop has not arrived yet',
      );
    });

    test('a six minute lecture, which crosses the boundary twenty times', () {
      final pushes = 2812;
      final trace = _trace(_stream(pushes));

      expect(pushes * _callback, greaterThan(10 * _keep));
      _expectSameStream(trace, '6 min lecture');
      expect(
        trace.liveWindows,
        hasLength(23),
        reason: 'one decode per hop once the buffer holds a window',
      );
      expect(
        trace.live.last.length,
        _keep,
        reason: 'trimmed back to the window',
      );
    });

    test('a buffer held well past the kept length', () {
      // The trim is what bounds the length, not the buffer: this is the case
      // where forgetting to trim would change what the next window starts on.
      final buffer = RollingBuffer()
        ..add(_chunk(0, _keep + 40000))
        ..trim();
      expect(buffer.length, _keep);

      buffer.add(_chunk(_keep + 40000, 5000));
      expect(buffer.length, greaterThan(_keep), reason: 'not trimmed yet');
      buffer.trim();
      expect(buffer.length, _keep);
      _expectSameSamples(
        buffer.window(windowSamples),
        _chunk(_keep + 45000 - windowSamples, windowSamples),
        'window read one push after a trimmed push',
      );
    });

    test('chunks that outgrow the kept window in a single push', () {
      // A push big enough to fill the store more than once forces the copy that
      // a normal push never does. This is the shape a callback takes after the
      // UI stalls, and the shape the growth path exists for.
      final chunks = <Float32List>[
        _chunk(0, _callback),
        _chunk(_callback, _keep * 2),
        _chunk(_callback + _keep * 2, 1234),
        _chunk(_callback + _keep * 2 + 1234, _keep + 1),
        _chunk(_callback * 3 + _keep * 3, _callback),
        _chunk(_callback * 4 + _keep * 3, _callback),
      ];
      final trace = _trace(chunks);
      _expectSameStream(trace, 'oversized chunks');
      expect(trace.liveFlush.length, lessThanOrEqualTo(_keep));
    });

    test('a stream of odd-sized callbacks', () {
      // Callback sizes are whatever `record` felt like, not a round number, and
      // a trim that lands mid-callback is the case the old sublist arithmetic
      // handled by accident.
      final chunks = <Float32List>[];
      var at = 0;
      for (var i = 0; i < 900; i++) {
        final size = 1000 + (i % 7) * 613;
        chunks.add(_chunk(at, size));
        at += size;
      }
      _expectSameStream(_trace(chunks), 'ragged callbacks');
    });
  });

  group('the rolling buffer stops allocating in the steady state', () {
    test('a full lecture never grows the store again', () {
      final buffer = RollingBuffer();
      final capacities = <int>[];
      // 45 minutes, long enough that the store has to fill and grow several
      // times before it settles.
      final pushes = 45 * 60 * _sampleRate ~/ _callback;
      for (var p = 0; p < pushes; p++) {
        buffer.add(_chunk(p * _callback, _callback));
        buffer.trim();
        capacities.add(buffer.capacity);
      }

      expect(pushes * _callback, greaterThan(40 * _keep));
      // A ring is reallocated only when the live samples plus the incoming
      // chunk no longer fit, and the trim pins the live samples at one kept
      // window -- so once the store holds a window plus a callback it can never
      // be resized again, whatever the lecture does after that.
      expect(
        buffer.capacity,
        1 << 20,
        reason:
            '2^20 samples is the first doubling past a kept window plus a '
            'callback, which is the size that lets the ring stop resizing',
      );
      final settled = capacities.indexWhere((c) => c == buffer.capacity);
      expect(
        settled,
        256,
        reason:
            'reached on the 257th callback, 33 seconds into a 45 minute '
            'lecture -- 20837 of its 21093 callbacks run with no allocation at '
            'all, where the old buffer allocated on every one',
      );
      expect(capacities.sublist(settled).toSet(), {
        buffer.capacity,
      }, reason: 'no allocation once the store has reached its size');
      expect(
        capacities.toSet().length,
        lessThanOrEqualTo(12),
        reason: 'a handful of doublings, not one per callback',
      );
      expect(buffer.length, _keep);
      expect(
        buffer.length,
        lessThanOrEqualTo(_keep + _callback),
        reason: 'a callback adds its own samples and nothing else',
      );
    });

    test('the store stays at two windows however long the lecture runs', () {
      final buffer = RollingBuffer();
      for (var p = 0; p < 4000; p++) {
        buffer.add(_chunk(p * _callback, _callback));
        buffer.trim();
      }
      expect(buffer.capacity, lessThanOrEqualTo(_keep * 2));
    });
  });

  group('the rolling buffer hands out copies, not windows into itself', () {
    test('a window taken now is not changed by the pushes after it', () {
      final buffer = RollingBuffer()
        ..add(_chunk(0, _keep))
        ..trim();
      final window = buffer.window(windowSamples);
      expect(
        _firstBitDifference(
          window,
          _chunk(_keep - windowSamples, windowSamples),
        ),
        -1,
        reason: 'the window starts where the lecture is now',
      );

      for (var i = 0; i < 10; i++) {
        buffer.add(_chunk(_keep + i * _callback, _callback));
        buffer.trim();
      }
      expect(
        _firstBitDifference(
          window,
          _chunk(_keep - windowSamples, windowSamples),
        ),
        -1,
        reason:
            'the decode is synchronous, but the array it was handed is its '
            'own -- the next push overwrites the room the trim freed, which is '
            'exactly where this window sits',
      );
    });

    test('a window taken before a reset cannot be written through', () {
      final buffer = RollingBuffer()
        ..add(_chunk(0, _keep))
        ..trim();
      final window = buffer.window(windowSamples);
      final before = window.sublist(0);

      buffer.reset();
      buffer.add(_chunk(0, _keep));
      _expectSameSamples(window, before, 'window across a reset');
    });

    test('asking for more than the buffer holds gives what it holds', () {
      expect(RollingBuffer().window(windowSamples).length, 0);
      final short = RollingBuffer()..add(_chunk(0, _sampleRate));
      expect(short.window(windowSamples).length, _sampleRate);
    });
  });

  group('whisper decoder threads', () {
    // Pinned against this table rather than the formula, so a change to either
    // has to be a change here: the old constant was 2 on every device, which is
    // also what the phone column still says.
    const table = <int, ({int desktop, int phone})>{
      0: (desktop: 1, phone: 2),
      1: (desktop: 1, phone: 2),
      2: (desktop: 2, phone: 2),
      3: (desktop: 3, phone: 2),
      4: (desktop: 4, phone: 2),
      6: (desktop: 4, phone: 2),
      8: (desktop: 4, phone: 2),
      12: (desktop: 4, phone: 2),
      16: (desktop: 4, phone: 2),
      64: (desktop: 4, phone: 2),
    };

    test('the table the formula is pinned to', () {
      for (final entry in table.entries) {
        expect(
          asrThreadsFor(logicalCores: entry.key, phone: false),
          entry.value.desktop,
          reason: 'a desktop with ${entry.key} cores',
        );
        expect(
          asrThreadsFor(logicalCores: entry.key, phone: true),
          entry.value.phone,
          reason: 'a phone reporting ${entry.key} cores',
        );
      }
    });

    test('a phone stays at two threads whatever it reports', () {
      // big.LITTLE: the extra cores are the little ones, and handing the decoder
      // one thread each is the oversubscription that made the old constant the
      // right one on a phone and the wrong one everywhere else.
      for (var cores = 0; cores <= 32; cores++) {
        expect(
          asrThreadsFor(logicalCores: cores, phone: true),
          2,
          reason: 'a phone reporting $cores cores',
        );
      }
    });

    test('a hyperthreaded desktop never gets more threads than cores', () {
      // `dart:io` reports logical cores and there is no physical count to ask
      // for, so the ceiling stands in for the missing half of the topology.
      for (var cores = 8; cores <= 128; cores++) {
        expect(
          asrThreadsFor(logicalCores: cores, phone: false),
          lessThanOrEqualTo(cores ~/ 2),
          reason: '$cores logical cores is at most $cores ~/ 2 physical ones',
        );
      }
    });

    test('a desktop with the cores the large model needs is not left on two', () {
      // `autoAsrForDevice` picks kb-whisper-large precisely because it counted
      // at least four cores; feeding that model two threads is the mismatch
      // this whole function exists to remove.
      expect(asrThreadsFor(logicalCores: 8, phone: false), 4);
      expect(asrThreadsFor(logicalCores: 4, phone: false), 4);
      expect(asrThreadsFor(logicalCores: 6, phone: false), greaterThan(2));
    });

    test('the device picks the threads from what it reports', () {
      final threads = asrThreadsForDevice();
      expect(threads, inInclusiveRange(1, 4));
      expect(
        threads,
        asrThreadsFor(
          logicalCores: Platform.numberOfProcessors,
          phone: Platform.isAndroid || Platform.isIOS,
        ),
        reason: 'the wrapper must not quietly differ from the formula',
      );
    });
  });
}
