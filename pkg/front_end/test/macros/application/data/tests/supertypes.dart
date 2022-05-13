// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/*library: 
Definitions:
import 'dart:core' as i0;


augment class A {
augment i0.String getSuperClass() {
    return "Object";
  }
}
augment class B {
augment i0.String getSuperClass() {
    return "A";
  }
}
augment class M {
augment i0.String getSuperClass() {
    return "Object";
  }
}
augment class C {
augment i0.String getSuperClass() {
    return "A";
  }
}
*/

import 'package:macro/macro.dart';

/*class: A:
augment class A {
augment String getSuperClass() {
    return "Object";
  }
}*/
@SupertypesMacro()
class A {
  external String getSuperClass();
}

/*class: B:
augment class B {
augment String getSuperClass() {
    return "A";
  }
}*/
@SupertypesMacro()
class B extends A {
  external String getSuperClass();
}

/*class: M:
augment class M {
augment String getSuperClass() {
    return "Object";
  }
}*/
@SupertypesMacro()
mixin M {
  external String getSuperClass();
}

/*class: C:
augment class C {
augment String getSuperClass() {
    return "A";
  }
}*/
@SupertypesMacro()
class C extends A with M {
  external String getSuperClass();
}
