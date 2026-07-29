// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

void main(List<String> arguments) {
  final outputPath = arguments.isEmpty
      ? 'docs/deep analysis/02-function-signatures.md'
      : arguments.single;
  final roots = [Directory('lib'), Directory('test'), Directory('tool')];
  if (roots.any((root) => !root.existsSync())) {
    stderr.writeln('Run this tool from the Flutter package root.');
    exitCode = 2;
    return;
  }

  final declarations = <_Declaration>[];
  final files = roots
      .expand((root) => root.listSync(recursive: true, followLinks: false))
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) => !_isGenerated(file.path))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final parseFailures = <String>[];
  for (final file in files) {
    final content = file.readAsStringSync();
    final result = parseString(
      content: content,
      path: file.absolute.path,
      throwIfDiagnostics: false,
    );
    if (result.errors.isNotEmpty) {
      for (final diagnostic in result.errors) {
        final location = result.lineInfo.getLocation(diagnostic.offset);
        parseFailures.add(
          '${file.path}:${location.lineNumber}:${location.columnNumber}: '
          '${diagnostic.problemMessage}',
        );
      }
      continue;
    }
    result.unit.accept(_DeclarationVisitor(
      file.path.replaceAll('\\', '/'),
      content,
      result.lineInfo,
      declarations,
    ));
  }

  if (parseFailures.isNotEmpty) {
    stderr.writeln('Signature inventory aborted because parsing failed:');
    for (final failure in parseFailures) {
      stderr.writeln(failure);
    }
    exitCode = 1;
    return;
  }

  declarations.sort((a, b) {
    final fileOrder = a.path.compareTo(b.path);
    return fileOrder != 0 ? fileOrder : a.line.compareTo(b.line);
  });

  final output = StringBuffer()
    ..writeln('# Índice de firmas mantenidas')
    ..writeln()
    ..writeln('Generado por `tool/generate_deep_analysis_signatures.dart`.')
    ..writeln(
        'Incluye `lib/`, `test/` y `tool/`: funciones top-level, métodos,')
    ..writeln('constructores, getters y')
    ..writeln('setters explícitos. Excluye closures/local functions y código')
    ..writeln('generado de localización, protobuf y FFI.')
    ..writeln()
    ..writeln('- Archivos: ${files.length}')
    ..writeln('- Declaraciones: ${declarations.length}')
    ..writeln('- Regenerar:')
    ..writeln('  `dart run tool/generate_deep_analysis_signatures.dart`')
    ..writeln();

  String? currentFile;
  for (final declaration in declarations) {
    if (currentFile != declaration.path) {
      currentFile = declaration.path;
      output
        ..writeln('## `${_escape(currentFile)}`')
        ..writeln()
        ..writeln('| Línea | Tipo | Owner | Firma | Descripción |')
        ..writeln('|---:|---|---|---|---|');
    }
    output.writeln(
      '| ${declaration.line} | ${declaration.kind} | '
      '${_escape(declaration.owner ?? '-')} | '
      '`${_escapeCode(declaration.signature)}` | '
      '${_escape(declaration.description)} |',
    );
  }

  File(outputPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(output.toString());
}

bool _isGenerated(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.contains('/generated/') ||
      normalized.contains('/protobuf/') ||
      normalized.endsWith('/recovery/bindings.dart');
}

String _escape(String value) =>
    value.replaceAll('|', r'\|').replaceAll('\n', ' ');

String _escapeCode(String value) => _escape(value)
    .replaceAll('`', r'\`')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class _Declaration {
  final String path;
  final int line;
  final String kind;
  final String? owner;
  final String signature;
  final String description;

  const _Declaration({
    required this.path,
    required this.line,
    required this.kind,
    required this.owner,
    required this.signature,
    required this.description,
  });
}

class _DeclarationVisitor extends RecursiveAstVisitor<void> {
  final String path;
  final String content;
  final LineInfo lineInfo;
  final List<_Declaration> declarations;

  _DeclarationVisitor(
    this.path,
    this.content,
    this.lineInfo,
    this.declarations,
  );

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is CompilationUnit) {
      final kind = node.isGetter
          ? 'getter'
          : node.isSetter
              ? 'setter'
              : 'función';
      _add(node, node.functionExpression.body.offset, kind, null,
          node.name.lexeme);
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final owner = _ownerName(node.parent);
    if (owner != null) {
      final kind = node.isGetter
          ? 'getter'
          : node.isSetter
              ? 'setter'
              : node.isOperator
                  ? 'operador'
                  : 'método';
      _add(node, node.body.offset, kind, owner, node.name.lexeme);
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final owner = _ownerName(node.parent);
    if (owner != null) {
      final name = node.name?.lexeme;
      _add(
        node,
        node.body.offset,
        node.factoryKeyword == null ? 'constructor' : 'factory',
        owner,
        name == null ? owner : '$owner.$name',
      );
    }
    super.visitConstructorDeclaration(node);
  }

  void _add(
    Declaration node,
    int bodyOffset,
    String kind,
    String? owner,
    String name,
  ) {
    final declarationOffset = node.metadata.isEmpty
        ? node.firstTokenAfterCommentAndMetadata.offset
        : node.metadata.first.offset;
    final location = lineInfo.getLocation(declarationOffset);
    final rawHeader = content.substring(declarationOffset, bodyOffset);
    final signature = rawHeader
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
        .replaceAll(RegExp(r'///.*?(\n|$)'), ' ')
        .replaceAll(RegExp(r'//.*?(\n|$)'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceFirst(RegExp(r'\s*=>\s*$'), '')
        .replaceFirst(RegExp(r'\s*;\s*$'), '');
    declarations.add(_Declaration(
      path: path,
      line: location.lineNumber,
      kind: kind,
      owner: owner,
      signature: signature,
      description: _description(node.documentationComment, kind, owner, name),
    ));
  }
}

String? _ownerName(AstNode? node) {
  var current = node;
  while (current != null) {
    final name = switch (current) {
      ClassDeclaration() => current.name.lexeme,
      MixinDeclaration() => current.name.lexeme,
      EnumDeclaration() => current.name.lexeme,
      ExtensionDeclaration() => current.name?.lexeme ?? '<extension>',
      ExtensionTypeDeclaration() => current.name.lexeme,
      _ => null,
    };
    if (name != null) return name;
    current = current.parent;
  }
  return null;
}

String _description(
  Comment? comment,
  String kind,
  String? owner,
  String name,
) {
  if (comment != null) {
    final text = comment.tokens
        .map((token) => token.lexeme)
        .join('\n')
        .replaceAll(RegExp(r'^\s*/\*\*?'), '')
        .replaceAll(RegExp(r'\*/\s*$'), '')
        .replaceAll(RegExp(r'^\s*///?', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*\*\s?', multiLine: true), '')
        .trim();
    final firstParagraph = text
        .split(RegExp(r'\n\s*\n'))
        .first
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join(' ');
    if (firstParagraph.isNotEmpty) {
      final sentence = RegExp(r'^.*?[.!?](?:\s|$)').firstMatch(firstParagraph);
      return sentence?.group(0)?.trim() ?? firstParagraph;
    }
  }

  if (kind == 'constructor' || kind == 'factory') {
    return 'Construye ${owner ?? name}.';
  }
  if (kind == 'getter') return 'Obtiene `$name`.';
  if (kind == 'setter') return 'Actualiza `$name`.';
  return switch (name) {
    'build' => 'Construye la interfaz de ${owner ?? 'este widget'}.',
    'dispose' => 'Libera recursos de ${owner ?? 'este objeto'}.',
    'initState' => 'Inicializa el estado de ${owner ?? 'este widget'}.',
    'toJson' || 'toJsonMap' => 'Serializa ${owner ?? 'el modelo'}.',
    'fromJson' || 'fromJsonMap' => 'Deserializa ${owner ?? 'el modelo'}.',
    _ => '${kind == 'función' ? 'Función' : 'Operación'} `$name`.',
  };
}
