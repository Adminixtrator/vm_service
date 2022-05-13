// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:isolate';

import 'package:_fe_analyzer_shared/src/macros/bootstrap.dart';
import 'package:_fe_analyzer_shared/src/macros/executor.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/serialization.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/isolated_executor.dart'
    as isolatedExecutor;
import 'package:_fe_analyzer_shared/src/macros/executor/process_executor.dart'
    as processExecutor;

import 'package:test/test.dart';

import '../util.dart';

void main() {
  late MacroExecutor executor;
  late File kernelOutputFile;
  final macroName = 'SimpleMacro';
  late MacroInstanceIdentifier instanceId;
  late Uri macroUri;
  late File simpleMacroFile;
  late Directory tmpDir;

  for (var executorKind in ['Isolated', 'Process']) {
    group('$executorKind executor', () {
      for (var mode in [
        SerializationMode.byteDataServer,
        SerializationMode.jsonServer
      ]) {
        final clientMode = mode == SerializationMode.byteDataServer
            ? SerializationMode.byteDataClient
            : SerializationMode.jsonClient;

        group('$mode', () {
          setUpAll(() async {
            simpleMacroFile =
                File(Platform.script.resolve('simple_macro.dart').toFilePath());
            executor = executorKind == 'Isolated'
                ? await isolatedExecutor.start(mode)
                : await processExecutor.start(mode);
            tmpDir = Directory.systemTemp.createTempSync('executor_test');
            macroUri = simpleMacroFile.absolute.uri;

            var bootstrapContent = bootstrapMacroIsolate({
              macroUri.toString(): {
                macroName: ['', 'named']
              }
            }, clientMode);
            var bootstrapFile =
                File(tmpDir.uri.resolve('main.dart').toFilePath())
                  ..writeAsStringSync(bootstrapContent);
            kernelOutputFile =
                File(tmpDir.uri.resolve('main.dart.dill').toFilePath());
            var packageConfigPath = (await Isolate.packageConfig)!.toFilePath();
            var buildSnapshotResult =
                await Process.run(Platform.resolvedExecutable, [
              if (executorKind == 'Isolated') ...[
                '--snapshot=${kernelOutputFile.uri.toFilePath()}',
                '--snapshot-kind=kernel',
              ] else ...[
                'compile',
                'exe',
                '-o',
                kernelOutputFile.uri.toFilePath(),
              ],
              '--packages=${packageConfigPath}',
              bootstrapFile.uri.toFilePath(),
            ]);
            expect(buildSnapshotResult.exitCode, 0,
                reason: 'stdout: ${buildSnapshotResult.stdout}\n'
                    'stderr: ${buildSnapshotResult.stderr}');

            var clazzId = await executor.loadMacro(macroUri, macroName,
                precompiledKernelUri: kernelOutputFile.uri);
            expect(clazzId, isNotNull, reason: 'Can load a macro.');

            instanceId =
                await executor.instantiateMacro(clazzId, '', Arguments([], {}));
            expect(instanceId, isNotNull,
                reason: 'Can create an instance with no arguments.');

            instanceId = await executor.instantiateMacro(
                clazzId, '', Arguments([1, 2], {}));
            expect(instanceId, isNotNull,
                reason: 'Can create an instance with positional arguments.');

            instanceId = await executor.instantiateMacro(
                clazzId, 'named', Arguments([], {'x': 1, 'y': 2}));
            expect(instanceId, isNotNull,
                reason: 'Can create an instance with named arguments.');
          });

          tearDownAll(() {
            if (tmpDir.existsSync()) {
              try {
                // Fails flakily on windows if a process still has the file open
                tmpDir.deleteSync(recursive: true);
              } catch (_) {}
            }
            executor.close();
          });

          group('run macros', () {
            group('in the types phase', () {
              test('on functions', () async {
                var result = await executor.executeTypesPhase(
                    instanceId, Fixtures.myFunction, FakeIdentifierResolver());
                expect(result.classAugmentations, isEmpty);
                expect(
                    result.libraryAugmentations.single.debugString().toString(),
                    equalsIgnoringWhitespace('class GeneratedByMyFunction {}'));
              });

              test('on methods', () async {
                var result = await executor.executeTypesPhase(
                    instanceId, Fixtures.myMethod, FakeIdentifierResolver());
                expect(result.classAugmentations, isEmpty);
                expect(
                    result.libraryAugmentations.single.debugString().toString(),
                    equalsIgnoringWhitespace('class GeneratedByMyMethod {}'));
              });

              test('on getters', () async {
                var result = await executor.executeTypesPhase(instanceId,
                    Fixtures.myVariableGetter, FakeIdentifierResolver());
                expect(result.classAugmentations, isEmpty);
                expect(
                    result.libraryAugmentations.single.debugString().toString(),
                    equalsIgnoringWhitespace(
                        'class GeneratedByMyVariableGetter {}'));
              });

              test('on setters', () async {
                var result = await executor.executeTypesPhase(instanceId,
                    Fixtures.myVariableSetter, FakeIdentifierResolver());
                expect(result.classAugmentations, isEmpty);
                expect(
                    result.libraryAugmentations.single.debugString().toString(),
                    equalsIgnoringWhitespace(
                        'class GeneratedByMyVariableSetter {}'));
              });

              test('on variables', () async {
                var result = await executor.executeTypesPhase(
                    instanceId, Fixtures.myVariable, FakeIdentifierResolver());
                expect(result.classAugmentations, isEmpty);
                expect(
                    result.libraryAugmentations.single.debugString().toString(),
                    equalsIgnoringWhitespace(
                        'class GeneratedBy_myVariable {}'));
              });

              test('on constructors', () async {
                var result = await executor.executeTypesPhase(instanceId,
                    Fixtures.myConstructor, FakeIdentifierResolver());
                expect(result.classAugmentations, isEmpty);
                expect(
                    result.libraryAugmentations.single.debugString().toString(),
                    equalsIgnoringWhitespace(
                        'class GeneratedByMyConstructor {}'));
              });

              test('on fields', () async {
                var result = await executor.executeTypesPhase(
                    instanceId, Fixtures.myField, FakeIdentifierResolver());
                expect(result.classAugmentations, isEmpty);
                expect(
                    result.libraryAugmentations.single.debugString().toString(),
                    equalsIgnoringWhitespace('class GeneratedByMyField {}'));
              });

              test('on classes', () async {
                var result = await executor.executeTypesPhase(
                    instanceId, Fixtures.myClass, FakeIdentifierResolver());
                expect(result.classAugmentations, isEmpty);
                expect(
                    result.libraryAugmentations.single.debugString().toString(),
                    equalsIgnoringWhitespace(
                        'class MyClassBuilder implements Builder<MyClass> {}'));
              });
            });

            group('in the declaration phase', () {
              test('on functions', () async {
                var result = await executor.executeDeclarationsPhase(
                    instanceId,
                    Fixtures.myFunction,
                    FakeIdentifierResolver(),
                    Fixtures.testTypeResolver,
                    Fixtures.testClassIntrospector);
                expect(result.classAugmentations, isEmpty);
                expect(
                    result.libraryAugmentations.single.debugString().toString(),
                    equalsIgnoringWhitespace(
                        'String delegateMyFunction() => myFunction();'));
              });

              test('on methods', () async {
                var result = await executor.executeDeclarationsPhase(
                    instanceId,
                    Fixtures.myMethod,
                    FakeIdentifierResolver(),
                    Fixtures.testTypeResolver,
                    Fixtures.testClassIntrospector);
                expect(result.classAugmentations, isEmpty);
                expect(
                    result.libraryAugmentations.single.debugString().toString(),
                    equalsIgnoringWhitespace(
                        'String delegateMemberMyMethod() => myMethod();'));
              });

              test('on constructors', () async {
                var result = await executor.executeDeclarationsPhase(
                    instanceId,
                    Fixtures.myConstructor,
                    FakeIdentifierResolver(),
                    Fixtures.testTypeResolver,
                    Fixtures.testClassIntrospector);
                expect(result.classAugmentations, hasLength(1));
                expect(
                    result.classAugmentations['MyClass']!.single
                        .debugString()
                        .toString(),
                    equalsIgnoringWhitespace('''
                factory MyClass.myConstructorDelegate() => MyClass.myConstructor();
              '''));
                expect(result.libraryAugmentations, isEmpty);
              });

              test('on getters', () async {
                var result = await executor.executeDeclarationsPhase(
                    instanceId,
                    Fixtures.myVariableGetter,
                    FakeIdentifierResolver(),
                    Fixtures.testTypeResolver,
                    Fixtures.testClassIntrospector);
                expect(result.classAugmentations, isEmpty);
                expect(
                    result.libraryAugmentations.single.debugString().toString(),
                    equalsIgnoringWhitespace('''
                String get delegateMyVariable => myVariable;'''));
              });

              test('on setters', () async {
                var result = await executor.executeDeclarationsPhase(
                    instanceId,
                    Fixtures.myVariableSetter,
                    FakeIdentifierResolver(),
                    Fixtures.testTypeResolver,
                    Fixtures.testClassIntrospector);
                expect(result.classAugmentations, isEmpty);
                expect(
                    result.libraryAugmentations.single.debugString().toString(),
                    equalsIgnoringWhitespace('''
                void set delegateMyVariable(String value) => myVariable = value;'''));
              });

              test('on variables', () async {
                var result = await executor.executeDeclarationsPhase(
                    instanceId,
                    Fixtures.myVariable,
                    FakeIdentifierResolver(),
                    Fixtures.testTypeResolver,
                    Fixtures.testClassIntrospector);
                expect(result.classAugmentations, isEmpty);
                expect(
                    result.libraryAugmentations.single.debugString().toString(),
                    equalsIgnoringWhitespace('''
                String get delegate_myVariable => _myVariable;'''));
              });

              test('on fields', () async {
                var result = await executor.executeDeclarationsPhase(
                    instanceId,
                    Fixtures.myField,
                    FakeIdentifierResolver(),
                    Fixtures.testTypeResolver,
                    Fixtures.testClassIntrospector);
                expect(result.classAugmentations, hasLength(1));
                expect(
                    result.classAugmentations['MyClass']!.single
                        .debugString()
                        .toString(),
                    equalsIgnoringWhitespace('''
                String get delegateMyField => myField;
              '''));
                expect(result.libraryAugmentations, isEmpty);
              });

              test('on classes', () async {
                var result = await executor.executeDeclarationsPhase(
                    instanceId,
                    Fixtures.myClass,
                    FakeIdentifierResolver(),
                    Fixtures.testTypeResolver,
                    Fixtures.testClassIntrospector);
                expect(result.classAugmentations, hasLength(1));
                expect(
                    result.classAugmentations['MyClass']!.single
                        .debugString()
                        .toString(),
                    equalsIgnoringWhitespace('''
                static const List<String> fieldNames = ['myField',];
              '''));
                expect(result.libraryAugmentations, isEmpty);
              });
            });

            group('in the definition phase', () {
              test('on functions', () async {
                var result = await executor.executeDefinitionsPhase(
                    instanceId,
                    Fixtures.myFunction,
                    FakeIdentifierResolver(),
                    Fixtures.testTypeResolver,
                    Fixtures.testClassIntrospector,
                    Fixtures.testTypeDeclarationResolver);
                expect(result.classAugmentations, isEmpty);
                expect(
                    result.libraryAugmentations.single.debugString().toString(),
                    equalsIgnoringWhitespace('''
                augment String myFunction() {
                  print('isAbstract: false');
                  print('isExternal: false');
                  print('isGetter: false');
                  print('isSetter: false');
                  print('returnType: String');
                  return augment super();
                }'''));
              });

              test('on methods', () async {
                var definitionResult = await executor.executeDefinitionsPhase(
                    instanceId,
                    Fixtures.myMethod,
                    FakeIdentifierResolver(),
                    Fixtures.testTypeResolver,
                    Fixtures.testClassIntrospector,
                    Fixtures.testTypeDeclarationResolver);
                expect(definitionResult.classAugmentations, hasLength(1));
                var augmentationStrings = definitionResult
                    .classAugmentations['MyClass']!
                    .map((a) => a.debugString().toString())
                    .toList();
                expect(augmentationStrings,
                    unorderedEquals(methodDefinitionMatchers));
                expect(definitionResult.libraryAugmentations, isEmpty);
              });

              test('on constructors', () async {
                var definitionResult = await executor.executeDefinitionsPhase(
                    instanceId,
                    Fixtures.myConstructor,
                    FakeIdentifierResolver(),
                    Fixtures.testTypeResolver,
                    Fixtures.testClassIntrospector,
                    Fixtures.testTypeDeclarationResolver);
                expect(definitionResult.classAugmentations, hasLength(1));
                expect(
                    definitionResult.classAugmentations['MyClass']!.first
                        .debugString()
                        .toString(),
                    constructorDefinitionMatcher);
                expect(definitionResult.libraryAugmentations, isEmpty);
              });

              test('on getters', () async {
                var result = await executor.executeDefinitionsPhase(
                    instanceId,
                    Fixtures.myVariableGetter,
                    FakeIdentifierResolver(),
                    Fixtures.testTypeResolver,
                    Fixtures.testClassIntrospector,
                    Fixtures.testTypeDeclarationResolver);
                expect(result.classAugmentations, isEmpty);
                expect(
                    result.libraryAugmentations.single.debugString().toString(),
                    equalsIgnoringWhitespace('''
                augment String myVariable() {
                  print('isAbstract: false');
                  print('isExternal: false');
                  print('isGetter: true');
                  print('isSetter: false');
                  print('returnType: String');
                  return augment super;
                }'''));
              });

              test('on setters', () async {
                var result = await executor.executeDefinitionsPhase(
                    instanceId,
                    Fixtures.myVariableSetter,
                    FakeIdentifierResolver(),
                    Fixtures.testTypeResolver,
                    Fixtures.testClassIntrospector,
                    Fixtures.testTypeDeclarationResolver);
                expect(result.classAugmentations, isEmpty);
                expect(
                    result.libraryAugmentations.single.debugString().toString(),
                    equalsIgnoringWhitespace('''
                augment void myVariable(String value, ) {
                  print('isAbstract: false');
                  print('isExternal: false');
                  print('isGetter: false');
                  print('isSetter: true');
                  print('returnType: void');
                  print('positionalParam: String value');
                  return augment super = value;
                }'''));
              });

              test('on variables', () async {
                var result = await executor.executeDefinitionsPhase(
                    instanceId,
                    Fixtures.myVariable,
                    FakeIdentifierResolver(),
                    Fixtures.testTypeResolver,
                    Fixtures.testClassIntrospector,
                    Fixtures.testTypeDeclarationResolver);
                expect(result.classAugmentations, isEmpty);
                expect(
                    result.libraryAugmentations
                        .map((a) => a.debugString().toString()),
                    unorderedEquals([
                      equalsIgnoringWhitespace('''
                augment String get _myVariable {
                  print('parentClass: ');
                  print('isExternal: false');
                  print('isFinal: true');
                  print('isLate: false');
                  return augment super;
                }'''),
                      equalsIgnoringWhitespace('''
                augment set _myVariable(String value) {
                  augment super = value;
                }'''),
                      equalsIgnoringWhitespace('''
                augment final String _myVariable = 'new initial value' + augment super;
                '''),
                    ]));
              });

              test('on fields', () async {
                var definitionResult = await executor.executeDefinitionsPhase(
                    instanceId,
                    Fixtures.myField,
                    FakeIdentifierResolver(),
                    Fixtures.testTypeResolver,
                    Fixtures.testClassIntrospector,
                    Fixtures.testTypeDeclarationResolver);
                expect(definitionResult.classAugmentations, hasLength(1));
                expect(
                    definitionResult.classAugmentations['MyClass']!
                        .map((a) => a.debugString().toString()),
                    unorderedEquals(fieldDefinitionMatchers));
                expect(definitionResult.libraryAugmentations, isEmpty);
              });

              test('on classes', () async {
                var definitionResult = await executor.executeDefinitionsPhase(
                    instanceId,
                    Fixtures.myClass,
                    FakeIdentifierResolver(),
                    Fixtures.testTypeResolver,
                    Fixtures.testClassIntrospector,
                    Fixtures.testTypeDeclarationResolver);
                expect(definitionResult.classAugmentations, hasLength(1));
                var augmentationStrings = definitionResult
                    .classAugmentations['MyClass']!
                    .map((a) => a.debugString().toString())
                    .toList();
                expect(
                    augmentationStrings,
                    unorderedEquals([
                      ...methodDefinitionMatchers,
                      constructorDefinitionMatcher,
                      ...fieldDefinitionMatchers,
                    ]));
              });
            });
          });
        });
      }
    });
  }
}

final constructorDefinitionMatcher = equalsIgnoringWhitespace('''
augment MyClass.myConstructor() {
  print('definingClass: MyClass');
  print('isFactory: false');
  print('isAbstract: false');
  print('isExternal: false');
  print('isGetter: false');
  print('isSetter: false');
  print('returnType: MyClass');
  return augment super();
}''');

final fieldDefinitionMatchers = [
  equalsIgnoringWhitespace('''
    augment String get myField {
      print('parentClass: MyClass');
      print('isExternal: false');
      print('isFinal: false');
      print('isLate: false');
      return augment super;
    }'''),
  equalsIgnoringWhitespace('''
    augment set myField(String value) {
      augment super = value;
    }'''),
  equalsIgnoringWhitespace('''
    augment String myField = \'new initial value\' + augment super;'''),
];

final methodDefinitionMatchers = [
  equalsIgnoringWhitespace('''
    augment String myMethod() {
      print('definingClass: MyClass');
      print('isAbstract: false');
      print('isExternal: false');
      print('isGetter: false');
      print('isSetter: false');
      print('returnType: String');
      return augment super();
    }'''),
  equalsIgnoringWhitespace('''
    augment String myMethod() {
      print('x: 1, y: 2');
      print('parentClass: MyClass');
      print('superClass: MySuperclass');
      print('interface: MyInterface');
      print('mixin: MyMixin');
      print('field: myField');
      print('method: myMethod');
      print('constructor: myConstructor');
      return augment super();
    }'''),
];
