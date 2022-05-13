// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/src/dart/error/syntactic_errors.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'context_collection_resolution.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PrefixExpressionResolutionTest);
    defineReflectiveTests(PrefixExpressionResolutionWithoutNullSafetyTest);
  });
}

@reflectiveTest
class PrefixExpressionResolutionTest extends PubPackageResolutionTest
    with PrefixExpressionResolutionTestCases {
  test_bang_no_nullShorting() async {
    await assertErrorsInCode(r'''
class A {
  bool get foo => true;
}

void f(A? a) {
  !a?.foo;
}
''', [
      error(CompileTimeErrorCode.UNCHECKED_USE_OF_NULLABLE_VALUE_AS_CONDITION,
          55, 6),
    ]);

    assertResolvedNodeText(findNode.prefix('!a'), r'''
PrefixExpression
  operator: !
  operand: PropertyAccess
    target: SimpleIdentifier
      token: a
      staticElement: a@47
      staticType: A?
    operator: ?.
    propertyName: SimpleIdentifier
      token: foo
      staticElement: self::@class::A::@getter::foo
      staticType: bool
    staticType: bool?
  staticElement: <null>
  staticType: bool
''');
  }

  test_minus_no_nullShorting() async {
    await assertErrorsInCode(r'''
class A {
  int get foo => 0;
}

void f(A? a) {
  -a?.foo;
}
''', [
      error(CompileTimeErrorCode.UNCHECKED_METHOD_INVOCATION_OF_NULLABLE_VALUE,
          50, 1),
    ]);

    assertResolvedNodeText(findNode.prefix('-a'), r'''
PrefixExpression
  operator: -
  operand: PropertyAccess
    target: SimpleIdentifier
      token: a
      staticElement: a@43
      staticType: A?
    operator: ?.
    propertyName: SimpleIdentifier
      token: foo
      staticElement: self::@class::A::@getter::foo
      staticType: int
    staticType: int?
  staticElement: dart:core::@class::int::@method::unary-
  staticType: int
''');
  }

  test_plusPlus_depromote() async {
    await assertNoErrorsInCode(r'''
class A {
  Object operator +(int _) => this;
}

void f(Object x) {
  if (x is A) {
    ++x;
  }
}
''');

    assertResolvedNodeText(findNode.prefix('++x'), r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: x
    staticElement: x@63
    staticType: null
  readElement: x@63
  readType: A
  writeElement: x@63
  writeType: Object
  staticElement: self::@class::A::@method::+
  staticType: Object
''');
  }

  test_plusPlus_nullShorting() async {
    await assertNoErrorsInCode(r'''
class A {
  int foo = 0;
}

void f(A? a) {
  ++a?.foo;
}
''');

    assertResolvedNodeText(findNode.prefix('++a'), r'''
PrefixExpression
  operator: ++
  operand: PropertyAccess
    target: SimpleIdentifier
      token: a
      staticElement: a@38
      staticType: A?
    operator: ?.
    propertyName: SimpleIdentifier
      token: foo
      staticElement: <null>
      staticType: null
    staticType: null
  readElement: self::@class::A::@getter::foo
  readType: int
  writeElement: self::@class::A::@setter::foo
  writeType: int
  staticElement: dart:core::@class::num::@method::+
  staticType: int?
''');
  }

  test_tilde_no_nullShorting() async {
    await assertErrorsInCode(r'''
class A {
  int get foo => 0;
}

void f(A? a) {
  ~a?.foo;
}
''', [
      error(CompileTimeErrorCode.UNCHECKED_METHOD_INVOCATION_OF_NULLABLE_VALUE,
          50, 1),
    ]);

    assertResolvedNodeText(findNode.prefix('~a'), r'''
PrefixExpression
  operator: ~
  operand: PropertyAccess
    target: SimpleIdentifier
      token: a
      staticElement: a@43
      staticType: A?
    operator: ?.
    propertyName: SimpleIdentifier
      token: foo
      staticElement: self::@class::A::@getter::foo
      staticType: int
    staticType: int?
  staticElement: dart:core::@class::int::@method::~
  staticType: int
''');
  }
}

mixin PrefixExpressionResolutionTestCases on PubPackageResolutionTest {
  test_bang_bool_context() async {
    await assertNoErrorsInCode(r'''
T f<T>() {
  throw 42;
}

main() {
  !f();
}
''');

    var node = findNode.methodInvocation('f();');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
MethodInvocation
  methodName: SimpleIdentifier
    token: f
    staticElement: self::@function::f
    staticType: T Function<T>()
  argumentList: ArgumentList
    leftParenthesis: (
    rightParenthesis: )
  staticInvokeType: bool Function()
  staticType: bool
  typeArgumentTypes
    bool
''');
    } else {
      assertResolvedNodeText(node, r'''
MethodInvocation
  methodName: SimpleIdentifier
    token: f
    staticElement: self::@function::f
    staticType: T* Function<T>()*
  argumentList: ArgumentList
    leftParenthesis: (
    rightParenthesis: )
  staticInvokeType: bool* Function()*
  staticType: bool*
  typeArgumentTypes
    bool*
''');
    }
  }

  test_bang_bool_localVariable() async {
    await assertNoErrorsInCode(r'''
void f(bool x) {
  !x;
}
''');

    var node = findNode.prefix('!x');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: !
  operand: SimpleIdentifier
    token: x
    staticElement: x@12
    staticType: bool
  staticElement: <null>
  staticType: bool
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: !
  operand: SimpleIdentifier
    token: x
    staticElement: x@12
    staticType: bool*
  staticElement: <null>
  staticType: bool*
''');
    }
  }

  test_bang_int_localVariable() async {
    await assertErrorsInCode(r'''
void f(int x) {
  !x;
}
''', [
      error(CompileTimeErrorCode.NON_BOOL_NEGATION_EXPRESSION, 19, 1),
    ]);

    var node = findNode.prefix('!x');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: !
  operand: SimpleIdentifier
    token: x
    staticElement: x@11
    staticType: int
  staticElement: <null>
  staticType: bool
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: !
  operand: SimpleIdentifier
    token: x
    staticElement: x@11
    staticType: int*
  staticElement: <null>
  staticType: bool*
''');
    }
  }

  test_inc_indexExpression_instance() async {
    await assertNoErrorsInCode(r'''
class A {
  int operator[](int index) => 0;
  operator[]=(int index, num _) {}
}

void f(A a) {
  ++a[0];
}
''');

    var node = findNode.prefix('++');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: IndexExpression
    target: SimpleIdentifier
      token: a
      staticElement: a@91
      staticType: A
    leftBracket: [
    index: IntegerLiteral
      literal: 0
      staticType: int
    rightBracket: ]
    staticElement: <null>
    staticType: null
  readElement: self::@class::A::@method::[]
  readType: int
  writeElement: self::@class::A::@method::[]=
  writeType: num
  staticElement: dart:core::@class::num::@method::+
  staticType: int
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: IndexExpression
    target: SimpleIdentifier
      token: a
      staticElement: a@91
      staticType: A*
    leftBracket: [
    index: IntegerLiteral
      literal: 0
      staticType: int*
    rightBracket: ]
    staticElement: <null>
    staticType: null
  readElement: self::@class::A::@method::[]
  readType: int*
  writeElement: self::@class::A::@method::[]=
  writeType: num*
  staticElement: MethodMember
    base: dart:core::@class::num::@method::+
    isLegacy: true
  staticType: int*
''');
    }
  }

  test_inc_indexExpression_super() async {
    await assertNoErrorsInCode(r'''
class A {
  int operator[](int index) => 0;
  operator[]=(int index, num _) {}
}

class B extends A {
  void f(A a) {
    ++super[0];
  }
}
''');

    var node = findNode.prefix('++');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: IndexExpression
    target: SuperExpression
      superKeyword: super
      staticType: B
    leftBracket: [
    index: IntegerLiteral
      literal: 0
      staticType: int
    rightBracket: ]
    staticElement: <null>
    staticType: null
  readElement: self::@class::A::@method::[]
  readType: int
  writeElement: self::@class::A::@method::[]=
  writeType: num
  staticElement: dart:core::@class::num::@method::+
  staticType: int
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: IndexExpression
    target: SuperExpression
      superKeyword: super
      staticType: B*
    leftBracket: [
    index: IntegerLiteral
      literal: 0
      staticType: int*
    rightBracket: ]
    staticElement: <null>
    staticType: null
  readElement: self::@class::A::@method::[]
  readType: int*
  writeElement: self::@class::A::@method::[]=
  writeType: num*
  staticElement: MethodMember
    base: dart:core::@class::num::@method::+
    isLegacy: true
  staticType: int*
''');
    }
  }

  test_inc_indexExpression_this() async {
    await assertNoErrorsInCode(r'''
class A {
  int operator[](int index) => 0;
  operator[]=(int index, num _) {}

  void f() {
    ++this[0];
  }
}
''');

    var node = findNode.prefix('++');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: IndexExpression
    target: ThisExpression
      thisKeyword: this
      staticType: A
    leftBracket: [
    index: IntegerLiteral
      literal: 0
      staticType: int
    rightBracket: ]
    staticElement: <null>
    staticType: null
  readElement: self::@class::A::@method::[]
  readType: int
  writeElement: self::@class::A::@method::[]=
  writeType: num
  staticElement: dart:core::@class::num::@method::+
  staticType: int
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: IndexExpression
    target: ThisExpression
      thisKeyword: this
      staticType: A*
    leftBracket: [
    index: IntegerLiteral
      literal: 0
      staticType: int*
    rightBracket: ]
    staticElement: <null>
    staticType: null
  readElement: self::@class::A::@method::[]
  readType: int*
  writeElement: self::@class::A::@method::[]=
  writeType: num*
  staticElement: MethodMember
    base: dart:core::@class::num::@method::+
    isLegacy: true
  staticType: int*
''');
    }
  }

  test_minus_simpleIdentifier_parameter_int() async {
    await assertNoErrorsInCode(r'''
void f(int x) {
  -x;
}
''');

    var node = findNode.prefix('-x');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: -
  operand: SimpleIdentifier
    token: x
    staticElement: x@11
    staticType: int
  staticElement: dart:core::@class::int::@method::unary-
  staticType: int
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: -
  operand: SimpleIdentifier
    token: x
    staticElement: x@11
    staticType: int*
  staticElement: MethodMember
    base: dart:core::@class::int::@method::unary-
    isLegacy: true
  staticType: int*
''');
    }
  }

  test_plusPlus_notLValue_extensionOverride() async {
    await assertErrorsInCode(r'''
class C {}

extension Ext on C {
  int operator +(int _) {
    return 0;
  }
}

void f(C c) {
  ++Ext(c);
}
''', [
      error(ParserErrorCode.MISSING_ASSIGNABLE_SELECTOR, 103, 1),
    ]);

    var node = findNode.prefix('++Ext');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: ExtensionOverride
    extensionName: SimpleIdentifier
      token: Ext
      staticElement: self::@extension::Ext
      staticType: null
    argumentList: ArgumentList
      leftParenthesis: (
      arguments
        SimpleIdentifier
          token: c
          staticElement: c@89
          staticType: C
      rightParenthesis: )
    extendedType: C
    staticType: null
  readElement: <null>
  readType: dynamic
  writeElement: <null>
  writeType: dynamic
  staticElement: self::@extension::Ext::@method::+
  staticType: int
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: ExtensionOverride
    extensionName: SimpleIdentifier
      token: Ext
      staticElement: self::@extension::Ext
      staticType: null
    argumentList: ArgumentList
      leftParenthesis: (
      arguments
        SimpleIdentifier
          token: c
          staticElement: c@89
          staticType: C*
      rightParenthesis: )
    extendedType: C*
    staticType: null
  readElement: <null>
  readType: dynamic
  writeElement: <null>
  writeType: dynamic
  staticElement: self::@extension::Ext::@method::+
  staticType: int*
''');
    }
  }

  test_plusPlus_notLValue_simpleIdentifier_typeLiteral() async {
    await assertErrorsInCode(r'''
void f() {
  ++int;
}
''', [
      error(CompileTimeErrorCode.ASSIGNMENT_TO_TYPE, 15, 3),
    ]);

    var node = findNode.prefix('++int');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: int
    staticElement: <null>
    staticType: null
  readElement: dart:core::@class::int
  readType: dynamic
  writeElement: dart:core::@class::int
  writeType: dynamic
  staticElement: <null>
  staticType: dynamic
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: int
    staticElement: <null>
    staticType: null
  readElement: dart:core::@class::int
  readType: dynamic
  writeElement: dart:core::@class::int
  writeType: dynamic
  staticElement: <null>
  staticType: dynamic
''');
    }
  }

  test_plusPlus_prefixedIdentifier_instance() async {
    await assertNoErrorsInCode(r'''
class A {
  int x = 0;
}

void f(A a) {
  ++a.x;
}
''');

    var node = findNode.prefix('++');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: PrefixedIdentifier
    prefix: SimpleIdentifier
      token: a
      staticElement: a@35
      staticType: A
    period: .
    identifier: SimpleIdentifier
      token: x
      staticElement: <null>
      staticType: null
    staticElement: <null>
    staticType: null
  readElement: self::@class::A::@getter::x
  readType: int
  writeElement: self::@class::A::@setter::x
  writeType: int
  staticElement: dart:core::@class::num::@method::+
  staticType: int
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: PrefixedIdentifier
    prefix: SimpleIdentifier
      token: a
      staticElement: a@35
      staticType: A*
    period: .
    identifier: SimpleIdentifier
      token: x
      staticElement: <null>
      staticType: null
    staticElement: <null>
    staticType: null
  readElement: self::@class::A::@getter::x
  readType: int*
  writeElement: self::@class::A::@setter::x
  writeType: int*
  staticElement: MethodMember
    base: dart:core::@class::num::@method::+
    isLegacy: true
  staticType: int*
''');
    }
  }

  test_plusPlus_prefixedIdentifier_topLevel() async {
    newFile2('$testPackageLibPath/a.dart', r'''
int x = 0;
''');
    await assertNoErrorsInCode(r'''
import 'a.dart' as p;

void f() {
  ++p.x;
}
''');

    var node = findNode.prefix('++');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: PrefixedIdentifier
    prefix: SimpleIdentifier
      token: p
      staticElement: self::@prefix::p
      staticType: null
    period: .
    identifier: SimpleIdentifier
      token: x
      staticElement: <null>
      staticType: null
    staticElement: <null>
    staticType: null
  readElement: package:test/a.dart::@getter::x
  readType: int
  writeElement: package:test/a.dart::@setter::x
  writeType: int
  staticElement: dart:core::@class::num::@method::+
  staticType: int
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: PrefixedIdentifier
    prefix: SimpleIdentifier
      token: p
      staticElement: self::@prefix::p
      staticType: null
    period: .
    identifier: SimpleIdentifier
      token: x
      staticElement: <null>
      staticType: null
    staticElement: <null>
    staticType: null
  readElement: package:test/a.dart::@getter::x
  readType: int*
  writeElement: package:test/a.dart::@setter::x
  writeType: int*
  staticElement: MethodMember
    base: dart:core::@class::num::@method::+
    isLegacy: true
  staticType: int*
''');
    }
  }

  test_plusPlus_propertyAccess_instance() async {
    await assertNoErrorsInCode(r'''
class A {
  int x = 0;
}

void f() {
  ++A().x;
}
''');

    var node = findNode.prefix('++');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: PropertyAccess
    target: InstanceCreationExpression
      constructorName: ConstructorName
        type: NamedType
          name: SimpleIdentifier
            token: A
            staticElement: self::@class::A
            staticType: null
          type: A
        staticElement: self::@class::A::@constructor::•
      argumentList: ArgumentList
        leftParenthesis: (
        rightParenthesis: )
      staticType: A
    operator: .
    propertyName: SimpleIdentifier
      token: x
      staticElement: <null>
      staticType: null
    staticType: null
  readElement: self::@class::A::@getter::x
  readType: int
  writeElement: self::@class::A::@setter::x
  writeType: int
  staticElement: dart:core::@class::num::@method::+
  staticType: int
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: PropertyAccess
    target: InstanceCreationExpression
      constructorName: ConstructorName
        type: NamedType
          name: SimpleIdentifier
            token: A
            staticElement: self::@class::A
            staticType: null
          type: A*
        staticElement: self::@class::A::@constructor::•
      argumentList: ArgumentList
        leftParenthesis: (
        rightParenthesis: )
      staticType: A*
    operator: .
    propertyName: SimpleIdentifier
      token: x
      staticElement: <null>
      staticType: null
    staticType: null
  readElement: self::@class::A::@getter::x
  readType: int*
  writeElement: self::@class::A::@setter::x
  writeType: int*
  staticElement: MethodMember
    base: dart:core::@class::num::@method::+
    isLegacy: true
  staticType: int*
''');
    }
  }

  test_plusPlus_propertyAccess_super() async {
    await assertNoErrorsInCode(r'''
class A {
  set x(num _) {}
  int get x => 0;
}

class B extends A {
  set x(num _) {}
  int get x => 0;

  void f() {
    ++super.x;
  }
}
''');

    var node = findNode.prefix('++');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: PropertyAccess
    target: SuperExpression
      superKeyword: super
      staticType: B
    operator: .
    propertyName: SimpleIdentifier
      token: x
      staticElement: <null>
      staticType: null
    staticType: null
  readElement: self::@class::A::@getter::x
  readType: int
  writeElement: self::@class::A::@setter::x
  writeType: num
  staticElement: dart:core::@class::num::@method::+
  staticType: int
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: PropertyAccess
    target: SuperExpression
      superKeyword: super
      staticType: B*
    operator: .
    propertyName: SimpleIdentifier
      token: x
      staticElement: <null>
      staticType: null
    staticType: null
  readElement: self::@class::A::@getter::x
  readType: int*
  writeElement: self::@class::A::@setter::x
  writeType: num*
  staticElement: MethodMember
    base: dart:core::@class::num::@method::+
    isLegacy: true
  staticType: int*
''');
    }
  }

  test_plusPlus_propertyAccess_this() async {
    await assertNoErrorsInCode(r'''
class A {
  set x(num _) {}
  int get x => 0;

  void f() {
    ++this.x;
  }
}
''');

    var node = findNode.prefix('++');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: PropertyAccess
    target: ThisExpression
      thisKeyword: this
      staticType: A
    operator: .
    propertyName: SimpleIdentifier
      token: x
      staticElement: <null>
      staticType: null
    staticType: null
  readElement: self::@class::A::@getter::x
  readType: int
  writeElement: self::@class::A::@setter::x
  writeType: num
  staticElement: dart:core::@class::num::@method::+
  staticType: int
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: PropertyAccess
    target: ThisExpression
      thisKeyword: this
      staticType: A*
    operator: .
    propertyName: SimpleIdentifier
      token: x
      staticElement: <null>
      staticType: null
    staticType: null
  readElement: self::@class::A::@getter::x
  readType: int*
  writeElement: self::@class::A::@setter::x
  writeType: num*
  staticElement: MethodMember
    base: dart:core::@class::num::@method::+
    isLegacy: true
  staticType: int*
''');
    }
  }

  test_plusPlus_simpleIdentifier_parameter_double() async {
    await assertNoErrorsInCode(r'''
void f(double x) {
  ++x;
}
''');

    var node = findNode.prefix('++x');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: x
    staticElement: x@14
    staticType: null
  readElement: x@14
  readType: double
  writeElement: x@14
  writeType: double
  staticElement: dart:core::@class::double::@method::+
  staticType: double
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: x
    staticElement: x@14
    staticType: null
  readElement: x@14
  readType: double*
  writeElement: x@14
  writeType: double*
  staticElement: MethodMember
    base: dart:core::@class::double::@method::+
    isLegacy: true
  staticType: double*
''');
    }
  }

  test_plusPlus_simpleIdentifier_parameter_int() async {
    await assertNoErrorsInCode(r'''
void f(int x) {
  ++x;
}
''');

    var node = findNode.prefix('++x');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: x
    staticElement: x@11
    staticType: null
  readElement: x@11
  readType: int
  writeElement: x@11
  writeType: int
  staticElement: dart:core::@class::num::@method::+
  staticType: int
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: x
    staticElement: x@11
    staticType: null
  readElement: x@11
  readType: int*
  writeElement: x@11
  writeType: int*
  staticElement: MethodMember
    base: dart:core::@class::num::@method::+
    isLegacy: true
  staticType: int*
''');
    }
  }

  test_plusPlus_simpleIdentifier_parameter_num() async {
    await assertNoErrorsInCode(r'''
void f(num x) {
  ++x;
}
''');

    var node = findNode.prefix('++x');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: x
    staticElement: x@11
    staticType: null
  readElement: x@11
  readType: num
  writeElement: x@11
  writeType: num
  staticElement: dart:core::@class::num::@method::+
  staticType: num
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: x
    staticElement: x@11
    staticType: null
  readElement: x@11
  readType: num*
  writeElement: x@11
  writeType: num*
  staticElement: MethodMember
    base: dart:core::@class::num::@method::+
    isLegacy: true
  staticType: num*
''');
    }
  }

  test_plusPlus_simpleIdentifier_parameter_typeParameter() async {
    await assertErrorsInCode(
      r'''
void f<T extends num>(T x) {
  ++x;
}
''',
      expectedErrorsByNullability(nullable: [
        error(CompileTimeErrorCode.INVALID_ASSIGNMENT, 31, 3),
      ], legacy: []),
    );

    var node = findNode.prefix('++x');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: x
    staticElement: x@24
    staticType: null
  readElement: x@24
  readType: T
  writeElement: x@24
  writeType: T
  staticElement: dart:core::@class::num::@method::+
  staticType: num
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: x
    staticElement: x@24
    staticType: null
  readElement: x@24
  readType: T*
  writeElement: x@24
  writeType: T*
  staticElement: MethodMember
    base: dart:core::@class::num::@method::+
    isLegacy: true
  staticType: num*
''');
    }
  }

  test_plusPlus_simpleIdentifier_thisGetter_superSetter() async {
    await assertNoErrorsInCode(r'''
class A {
  set x(num _) {}
}

class B extends A {
  int get x => 0;
  void f() {
    ++x;
  }
}
''');

    var node = findNode.prefix('++x');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: x
    staticElement: <null>
    staticType: null
  readElement: self::@class::B::@getter::x
  readType: int
  writeElement: self::@class::A::@setter::x
  writeType: num
  staticElement: dart:core::@class::num::@method::+
  staticType: int
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: x
    staticElement: <null>
    staticType: null
  readElement: self::@class::B::@getter::x
  readType: int*
  writeElement: self::@class::A::@setter::x
  writeType: num*
  staticElement: MethodMember
    base: dart:core::@class::num::@method::+
    isLegacy: true
  staticType: int*
''');
    }

    assertSimpleIdentifierAssignmentTarget(
      node.operand,
    );
  }

  test_plusPlus_simpleIdentifier_thisGetter_thisSetter() async {
    await assertNoErrorsInCode(r'''
class A {
  int get x => 0;
  set x(num _) {}
  void f() {
    ++x;
  }
}
''');

    var node = findNode.prefix('++x');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: x
    staticElement: <null>
    staticType: null
  readElement: self::@class::A::@getter::x
  readType: int
  writeElement: self::@class::A::@setter::x
  writeType: num
  staticElement: dart:core::@class::num::@method::+
  staticType: int
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: x
    staticElement: <null>
    staticType: null
  readElement: self::@class::A::@getter::x
  readType: int*
  writeElement: self::@class::A::@setter::x
  writeType: num*
  staticElement: MethodMember
    base: dart:core::@class::num::@method::+
    isLegacy: true
  staticType: int*
''');
    }

    assertSimpleIdentifierAssignmentTarget(
      node.operand,
    );
  }

  test_plusPlus_simpleIdentifier_topGetter_topSetter() async {
    await assertNoErrorsInCode(r'''
int get x => 0;

set x(num _) {}

void f() {
  ++x;
}
''');

    var node = findNode.prefix('++x');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: x
    staticElement: <null>
    staticType: null
  readElement: self::@getter::x
  readType: int
  writeElement: self::@setter::x
  writeType: num
  staticElement: dart:core::@class::num::@method::+
  staticType: int
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: x
    staticElement: <null>
    staticType: null
  readElement: self::@getter::x
  readType: int*
  writeElement: self::@setter::x
  writeType: num*
  staticElement: MethodMember
    base: dart:core::@class::num::@method::+
    isLegacy: true
  staticType: int*
''');
    }

    assertSimpleIdentifierAssignmentTarget(
      node.operand,
    );
  }

  test_plusPlus_simpleIdentifier_topGetter_topSetter_fromClass() async {
    await assertNoErrorsInCode(r'''
int get x => 0;

set x(num _) {}

class A {
  void f() {
    ++x;
  }
}
''');

    var node = findNode.prefix('++x');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: x
    staticElement: <null>
    staticType: null
  readElement: self::@getter::x
  readType: int
  writeElement: self::@setter::x
  writeType: num
  staticElement: dart:core::@class::num::@method::+
  staticType: int
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: x
    staticElement: <null>
    staticType: null
  readElement: self::@getter::x
  readType: int*
  writeElement: self::@setter::x
  writeType: num*
  staticElement: MethodMember
    base: dart:core::@class::num::@method::+
    isLegacy: true
  staticType: int*
''');
    }

    assertSimpleIdentifierAssignmentTarget(
      node.operand,
    );
  }

  /// Verify that we get all necessary types when building the dependencies
  /// graph during top-level inference.
  test_plusPlus_topLevelInference() async {
    await assertNoErrorsInCode(r'''
var x = 0;

class A {
  final y = ++x;
}
''');

    var node = findNode.prefix('++x');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: x
    staticElement: <null>
    staticType: null
  readElement: self::@getter::x
  readType: int
  writeElement: self::@setter::x
  writeType: int
  staticElement: dart:core::@class::num::@method::+
  staticType: int
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ++
  operand: SimpleIdentifier
    token: x
    staticElement: <null>
    staticType: null
  readElement: self::@getter::x
  readType: int*
  writeElement: self::@setter::x
  writeType: int*
  staticElement: MethodMember
    base: dart:core::@class::num::@method::+
    isLegacy: true
  staticType: int*
''');
    }
  }

  test_tilde_simpleIdentifier_parameter_int() async {
    await assertNoErrorsInCode(r'''
void f(int x) {
  ~x;
}
''');

    var node = findNode.prefix('~x');
    if (isNullSafetyEnabled) {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ~
  operand: SimpleIdentifier
    token: x
    staticElement: x@11
    staticType: int
  staticElement: dart:core::@class::int::@method::~
  staticType: int
''');
    } else {
      assertResolvedNodeText(node, r'''
PrefixExpression
  operator: ~
  operand: SimpleIdentifier
    token: x
    staticElement: x@11
    staticType: int*
  staticElement: MethodMember
    base: dart:core::@class::int::@method::~
    isLegacy: true
  staticType: int*
''');
    }
  }
}

@reflectiveTest
class PrefixExpressionResolutionWithoutNullSafetyTest
    extends PubPackageResolutionTest
    with PrefixExpressionResolutionTestCases, WithoutNullSafetyMixin {}
