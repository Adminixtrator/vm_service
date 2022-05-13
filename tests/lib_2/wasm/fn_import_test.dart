// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

// Test that we can load a wasm module, find a function, and call it.

import "package:expect/expect.dart";
import "package:wasm/wasm.dart";
import "dart:typed_data";

void main() {
  // void reportStuff() { report(123, 456); }
  var data = Uint8List.fromList([
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, 0x01, 0x09, 0x02, 0x60,
    0x02, 0x7e, 0x7e, 0x00, 0x60, 0x00, 0x00, 0x02, 0x0e, 0x01, 0x03, 0x65,
    0x6e, 0x76, 0x06, 0x72, 0x65, 0x70, 0x6f, 0x72, 0x74, 0x00, 0x00, 0x03,
    0x02, 0x01, 0x01, 0x04, 0x05, 0x01, 0x70, 0x01, 0x01, 0x01, 0x05, 0x03,
    0x01, 0x00, 0x02, 0x06, 0x08, 0x01, 0x7f, 0x01, 0x41, 0x80, 0x88, 0x04,
    0x0b, 0x07, 0x18, 0x02, 0x06, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x02,
    0x00, 0x0b, 0x72, 0x65, 0x70, 0x6f, 0x72, 0x74, 0x53, 0x74, 0x75, 0x66,
    0x66, 0x00, 0x01, 0x0a, 0x10, 0x01, 0x0e, 0x00, 0x42, 0xfb, 0x00, 0x42,
    0xc8, 0x03, 0x10, 0x80, 0x80, 0x80, 0x80, 0x00, 0x0b,
  ]);

  int report_x = -1;
  int report_y = -1;

  var inst = WasmModule(data).instantiate()
    .addFunction("env", "report", (int x, int y) {
      report_x = x;
      report_y = y;
    }).build();
  var fn = inst.lookupFunction("reportStuff");
  fn();
  Expect.equals(report_x, 123);
  Expect.equals(report_y, 456);
}
