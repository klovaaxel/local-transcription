import 'dart:typed_data';

import 'package:crypto/crypto.dart';

void main() {
  final block = Uint8List(64 * 1024);
  for (var i = 0; i < block.length; i++) {
    block[i] = i & 0xff;
  }
  var sink = 0;
  var bytes = 0;
  final started = DateTime.now();
  final deadline = started.add(const Duration(milliseconds: 800));
  while (DateTime.now().isBefore(deadline)) {
    sink += sha256.convert(block).bytes[0];
    bytes += block.length;
  }
  final seconds = DateTime.now().difference(started).inMicroseconds / 1e6;
  if (sink < 0) {
    throw StateError('unreachable');
  }
  // ignore: avoid_print
  print('sha256 ${bytes / 1e6 / seconds} MB/s over $seconds s');
}
