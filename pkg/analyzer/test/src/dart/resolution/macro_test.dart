// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/src/summary2/macro.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../../summary/repository_macro_kernel_builder.dart';
import 'context_collection_resolution.dart';

main() {
  try {
    MacrosEnvironment.instance;
  } catch (_) {
    print('Cannot initialize environment. Skip macros tests.');
    return;
  }

  defineReflectiveSuite(() {
    defineReflectiveTests(MacroResolutionTest);
  });
}

@reflectiveTest
class MacroResolutionTest extends PubPackageResolutionTest {
  @override
  MacroKernelBuilder? get macroKernelBuilder {
    return DartRepositoryMacroKernelBuilder(
      MacrosEnvironment.instance.platformDillBytes,
    );
  }

  @override
  void setUp() {
    super.setUp();

    writeTestPackageConfig(
      PackageConfigFileBuilder(),
      macrosEnvironment: MacrosEnvironment.instance,
    );
  }

  test_0() async {
    await assertNoErrorsInCode(r'''
import 'dart:async';
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class EmptyMacro implements ClassTypesMacro {
  const EmptyMacro();
  FutureOr<void> buildTypesForClass(clazz, builder) {}
}
''');
  }
}
