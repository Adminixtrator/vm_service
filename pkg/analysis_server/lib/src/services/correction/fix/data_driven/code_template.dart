// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/fix/data_driven/expression.dart'
    as data_driven;
import 'package:analysis_server/src/services/correction/fix/data_driven/value_generator.dart';
import 'package:analysis_server/src/services/correction/util.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_dart.dart';

/// An object used to generate code to be inserted.
class CodeTemplate {
  /// The kind of code that will be generated by this template.
  final CodeTemplateKind kind;

  /// The components of the template.
  final List<TemplateComponent> components;

  /// The expression used to determine whether the template is required to be
  /// used, or `null` if the template is not required to be used.
  final data_driven.Expression? requiredIfCondition;

  /// Initialize a newly generated code template with the given [kind] and
  /// [components].
  CodeTemplate(this.kind, this.components, this.requiredIfCondition);

  /// Use the [context] to validate that this template will be able to generate
  /// a value.
  bool validate(TemplateContext context) {
    for (var component in components) {
      if (!component.validate(context)) {
        return false;
      }
    }
    return true;
  }

  void writeOn(DartEditBuilder builder, TemplateContext context) {
    for (var component in components) {
      component.writeOn(builder, context);
    }
  }
}

/// The kinds of code that can be generated by a template.
enum CodeTemplateKind {
  // We currently only support expressions, but we will likely need to support
  // statements at some point.
  expression,
}

/// An object used to compute some portion of a template.
abstract class TemplateComponent {
  /// Use the [context] to validate that this component will be able to generate
  /// a value.
  bool validate(TemplateContext context);

  /// Write the text contributed by this component to the given [builder], using
  /// the [context] to access needed information that isn't already known to
  /// this component.
  void writeOn(DartEditBuilder builder, TemplateContext context);
}

/// The context in which a template is being evaluated.
class TemplateContext {
  /// The node in the AST that is being transformed.
  final AstNode? node;

  /// The utilities used to help extract the code associated with various nodes.
  final CorrectionUtils utils;

  /// Initialize a newly created template context with the [node] and [utils].
  TemplateContext(this.node, this.utils);

  /// Initialize a newly created template context that uses the invocation
  /// containing the [node] and the [utils].
  factory TemplateContext.forInvocation(AstNode node, CorrectionUtils utils) =>
      TemplateContext(_getInvocation(node), utils);

  /// Return the invocation containing the given [node]. The invocation will be
  /// either an instance creation expression, function invocation, method
  /// invocation, or an extension override.
  static AstNode? _getInvocation(AstNode node) {
    if (node is ArgumentList) {
      return node.parent;
    } else if (node.parent is ArgumentList) {
      return node.parent?.parent;
    } else if (node is InstanceCreationExpression ||
        node is InvocationExpression) {
      return node;
    } else if (node is SimpleIdentifier) {
      var parent = node.parent;
      if (parent is ConstructorName) {
        var grandparent = parent.parent;
        if (grandparent is InstanceCreationExpression) {
          return grandparent;
        }
      } else if (parent is Label && parent.parent is NamedExpression) {
        return parent.parent?.parent?.parent;
      } else if (parent is MethodInvocation && parent.methodName == node) {
        return parent;
      } else if (parent is NamedType &&
          parent.parent is ConstructorName &&
          parent.parent?.parent is InstanceCreationExpression) {
        return parent.parent?.parent;
      }
    } else if (node is TypeArgumentList) {
      var parent = node.parent;
      if (parent is InvocationExpression) {
        return parent;
      } else if (parent is ExtensionOverride) {
        return parent;
      }
    }
    return null;
  }
}

/// Literal text within a template.
class TemplateText extends TemplateComponent {
  /// The literal text to be included in the resulting code.
  final String text;

  /// Initialize a newly create template text with the given [text].
  TemplateText(this.text);

  @override
  bool validate(TemplateContext context) {
    return true;
  }

  @override
  void writeOn(DartEditBuilder builder, TemplateContext context) {
    builder.write(text);
  }
}

/// A reference to a variable within a template.
class TemplateVariable extends TemplateComponent {
  /// The generator used to compute the value of the variable.
  final ValueGenerator generator;

  /// Initialize a newly created template variable with the given [generator].
  TemplateVariable(this.generator);

  @override
  bool validate(TemplateContext context) {
    return generator.validate(context);
  }

  @override
  void writeOn(DartEditBuilder builder, TemplateContext context) {
    generator.writeOn(builder, context);
  }
}