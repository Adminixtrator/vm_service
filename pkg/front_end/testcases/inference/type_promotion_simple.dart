// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.
// @dart=2.9
/*@testedFeatures=inference*/
library test;

main() {
  num n = null;
  if (n is int) {
    var /*@ type=int* */ i = /*@ promotedType=int* */ n;
  }
}
