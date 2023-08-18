import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dcpu_flutter/assembler/parser.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:dcpu_flutter/core/cpu.dart' show Register;
import 'package:dcpu_flutter/core/math.dart';
import 'package:dcpu_flutter/core/instructions.dart' as dcpu;
import 'package:dcpu_flutter/assembler/ast.dart';
import 'package:dcpu_flutter/assembler/mypetitparser.dart';
import 'package:petitparser/debug.dart';
import 'package:petitparser/petitparser.dart';

class SemanticError implements Exception {
  SemanticError(this.subject, this.message);

  final Location subject;
  final String message;

  @override
  String toString() {
    return '$subject: Error: $message: "${subject.text}"';
  }
}

class SyntaxError implements Exception {
  SyntaxError(this.subject, this.message);

  final Location subject;
  final String message;

  @override
  String toString() {
    return '$subject: Syntax error: $message: "${subject.text}"';
  }
}

class AssemblyWriter {
  final _words = List<int?>.filled(0x10000, null);

  var offset = 0x0000;

  void emitAndAdvance(Iterable<int> bytes) {
    _words.setAll(offset, bytes);
    offset += bytes.length;
  }

  void advance(int bytes) {
    offset += bytes;
  }

  void emitAt(Iterable<int> bytes, int address) {
    final overwriting = _words.getRange(address, address + bytes.length).any((byte) => byte != null);
    if (overwriting) {
      throw StateError('Double-write of bytes at $address');
    }

    _words.setAll(address, bytes);
  }

  void reserve(int bytes) {
    _words.fillRange(offset, offset + bytes, 0);
    offset += bytes;
  }

  List<int> toWords() {
    return _words.map<int>((e) => e ?? 0).toList();
  }

  List<int> toBytes({Endian endian = Endian.little}) {
    final words = toWords();

    switch (endian) {
      case Endian.big:
        return words.expand((word) {
          return [
            (word & 0xFF00) >> 8,
            word & 0xFF,
          ];
        }).toList();
      case Endian.little:
        return words.expand((word) {
          return [
            word & 0xFF,
            (word & 0xFF00) >> 8,
          ];
        }).toList();
      default:
        throw UnsupportedError('Unsupported endianess: $endian');
    }
  }
}

abstract class AssemblyContext {
  AssemblyContext();

  factory AssemblyContext.root(List<Directory> includeSearchPaths) = RootAssemblyContext;

  int? lookupSymbol(String name) => lookupConstant(name) ?? lookupLabel(name);

  bool symbolDefined(String name) => lookupSymbol(name) != null;

  int? lookupLabel(String name);

  bool labelDefined(String name) => lookupLabel(name) != null;

  int? lookupConstant(String name);

  bool constantDefined(String name) => lookupConstant(name) != null;

  MacroDefinition? lookupMacro(String name);

  bool macroDefined(String name) => lookupMacro(name) != null;

  void defineConstant(String name, int value);

  void undefConstant(String name);

  void defineLabel(String name, int value);

  void defineMacro(String name, MacroDefinition definition);

  ({String name, String contents}) resolveInclude(String includePath, {bool isSystem = false});
}

class RootAssemblyContext extends AssemblyContext {
  RootAssemblyContext(this.includeSearchPaths);

  final _labels = <String, int>{};
  final _constants = <String, int>{};
  final _macros = <String, MacroDefinition>{};

  final List<Directory> includeSearchPaths;

  @override
  int? lookupLabel(String name) {
    return _labels[name];
  }

  @override
  int? lookupConstant(String name) {
    return _constants[name];
  }

  @override
  MacroDefinition? lookupMacro(String name) {
    return _macros[name];
  }

  @override
  void defineConstant(String name, int value) {
    _constants[name] = value;
  }

  @override
  void undefConstant(String name) {
    _constants.remove(name);
  }

  @override
  void defineLabel(String name, int value) {
    _labels[name] = value;
  }

  @override
  void defineMacro(String name, MacroDefinition definition) {
    _macros[name] = definition;
  }

  @override
  ({String name, String contents}) resolveInclude(String includePath, {bool isSystem = false}) {
    final relativeComponents = path.posix.split(path.posix.normalize(includePath));

    final platformPath = path.joinAll(relativeComponents);

    final resolved = includeSearchPaths
        .map((e) => File(path.joinAll([e.path, ...relativeComponents])))
        .firstWhere((includeFile) => includeFile.existsSync());

    return (
      name: platformPath,
      contents: resolved.readAsStringSync(),
    );
  }

  CapturedAssemblyContext capture() {
    return CapturedAssemblyContext(
      base: this,
      capturedMacros: Map.of(_macros),
      capturedConstants: Map.of(_constants),
    );
  }
}

class CapturedAssemblyContext extends AssemblyContext {
  CapturedAssemblyContext({
    required AssemblyContext base,
    required Map<String, MacroDefinition> capturedMacros,
    required Map<String, int> capturedConstants,
  })  : _base = base,
        _capturedMacros = capturedMacros,
        _capturedConstants = capturedConstants;

  final AssemblyContext _base;

  final Map<String, MacroDefinition> _capturedMacros;
  final Map<String, int> _capturedConstants;

  @override
  int? lookupConstant(String name) {
    return _capturedConstants[name];
  }

  @override
  int? lookupLabel(String name) {
    return _base.lookupLabel(name);
  }

  @override
  MacroDefinition? lookupMacro(String name) {
    return _capturedMacros[name];
  }

  @override
  void defineConstant(String name, int value) {
    throw UnsupportedError('Action is not supported for a read-only assembly context');
  }

  @override
  void undefConstant(String name) {
    throw UnsupportedError('Action is not supported for a read-only assembly context');
  }

  @override
  void defineLabel(String name, [int? value]) {
    throw UnsupportedError('Action is not supported for a read-only assembly context');
  }

  @override
  void defineMacro(String name, MacroDefinition definition) {
    throw UnsupportedError('Action is not supported for a read-only assembly context');
  }

  @override
  ({String contents, String name}) resolveInclude(
    String includePath, {
    bool isSystem = false,
  }) {
    return _base.resolveInclude(includePath);
  }
}

sealed class MaybeUnassembled<T> {
  const MaybeUnassembled();

  Iterable<String> get symbolDependencies;

  T get substituteOrValue;
}

sealed class Unassembled<T> extends MaybeUnassembled<T> {
  const Unassembled();

  T get substitute;

  @override
  Iterable<String> get symbolDependencies;

  Iterable<String> missingDependencies(AssemblyContext context) {
    return symbolDependencies.where((symbol) => !context.symbolDefined(symbol));
  }

  bool canAssemble(AssemblyContext context);

  Assembled<T> assemble(AssemblyContext context);

  @override
  T get substituteOrValue => substitute;
}

sealed class UnassembledDepending<T, D> extends Unassembled<T> {
  const UnassembledDepending();

  Iterable<MaybeUnassembled<D>> get dependencies;

  @override
  Iterable<String> get symbolDependencies {
    return dependencies.expand((dep) => dep.symbolDependencies);
  }

  @override
  bool canAssemble(AssemblyContext context) {
    return dependencies.whereType<Unassembled>().every((dep) => dep.canAssemble(context));
  }

  Assembled<T> assembleWithDeps(AssemblyContext context, Iterable<Assembled<D>> resolvedDeps);

  @override
  Assembled<T> assemble(AssemblyContext context) {
    final resolved = dependencies.map((dep) {
      return switch (dep) {
        Unassembled<D>() => dep.assemble(context),
        Assembled<D> dep => dep,
      };
    }).toList();

    return assembleWithDeps(context, resolved);
  }
}

class UnassembledTerm extends Unassembled<int> {
  const UnassembledTerm(this.term);

  final Term term;

  @override
  int get substitute => 0;

  @override
  Iterable<String> get symbolDependencies => [
        for (final symbol in term.symbolDependencies) symbol,
      ];

  @override
  bool canAssemble(AssemblyContext context) {
    return symbolDependencies.every((symbol) => context.symbolDefined(symbol));
  }

  static int evaluateTerm(Term ast, AssemblyContext context) {
    return UnassembledTerm(ast).assemble(context).value;
  }

  @override
  Assembled<int> assemble(AssemblyContext context) {
    assert(canAssemble(context));

    final value = switch (term) {
      LiteralTerm(value: MyToken(:final value)) => value,
      LabelTerm(label: LabelName(name: MyToken<String>(value: final label))) => context.lookupSymbol(label)!,
      BinaryOpTerm(
        :final lhs,
        op: MyToken<BinOp>(value: BinOp.add),
        :final rhs,
      ) =>
        add16bit(
          evaluateTerm(lhs, context),
          evaluateTerm(rhs, context),
        ),
      BinaryOpTerm(
        :final lhs,
        op: MyToken<BinOp>(value: BinOp.sub),
        :final rhs,
      ) =>
        sub16bit(
          evaluateTerm(lhs, context),
          evaluateTerm(rhs, context),
        ),
      BinaryOpTerm(
        :final lhs,
        op: MyToken<BinOp>(value: BinOp.bitwiseOr),
        :final rhs,
      ) =>
        evaluateTerm(lhs, context) | evaluateTerm(rhs, context),
      UnaryOpTerm(op: MyToken<UnaryOp>(value: UnaryOp.minus), :final child) =>
        sub16bit(0, evaluateTerm(child, context)),
    };

    return Assembled(value, term.symbolDependencies.toList());
  }
}

class UnassembledIndirectRegisterImmediateArg extends UnassembledDepending<dcpu.IndirectRegisterImmediateArg, int> {
  const UnassembledIndirectRegisterImmediateArg(this.register, this.term);

  final UnassembledTerm term;
  final Register register;

  @override
  Iterable<Unassembled<int>> get dependencies => [term];

  @override
  Assembled<dcpu.IndirectRegisterImmediateArg> assembleWithDeps(
    AssemblyContext context,
    Iterable<Assembled<int>> resolvedDeps,
  ) {
    return Assembled(
      dcpu.IndirectRegisterImmediateArg(register, resolvedDeps.single.value),
      symbolDependencies.toList(),
    );
  }

  @override
  final dcpu.IndirectRegisterImmediateArg substitute = const dcpu.IndirectRegisterImmediateArg(Register.a, 0);
}

class UnassembledImmediateArg extends UnassembledDepending<dcpu.ImmediateArg, int> {
  const UnassembledImmediateArg(this.term);

  final UnassembledTerm term;

  @override
  Iterable<Unassembled<int>> get dependencies => [term];

  @override
  Assembled<dcpu.ImmediateArg> assembleWithDeps(
    AssemblyContext context,
    Iterable<Assembled<int>> resolvedDeps,
  ) {
    return Assembled(
      dcpu.ImmediateArg(resolvedDeps.single.value),
      symbolDependencies.toList(),
    );
  }

  @override
  final dcpu.ImmediateArg substitute = const dcpu.ImmediateArg(0);
}

class UnassembledIndirectImmediateArg extends UnassembledDepending<dcpu.IndirectImmediateArg, int> {
  const UnassembledIndirectImmediateArg(this.term);

  final UnassembledTerm term;

  @override
  Iterable<Unassembled<int>> get dependencies => [term];

  @override
  Assembled<dcpu.IndirectImmediateArg> assembleWithDeps(
    AssemblyContext context,
    Iterable<Assembled<int>> resolvedDeps,
  ) {
    return Assembled(
      dcpu.IndirectImmediateArg(resolvedDeps.single.value),
      symbolDependencies.toList(),
    );
  }

  @override
  final dcpu.IndirectImmediateArg substitute = const dcpu.IndirectImmediateArg(0);
}

sealed class UnassembledInstruction extends UnassembledDepending<dcpu.Instruction, dcpu.Arg> {
  const UnassembledInstruction();

  dcpu.Op get opcode;
}

class UnassembledBasicInstruction extends UnassembledInstruction {
  const UnassembledBasicInstruction(this.opcode, this.b, this.a);

  @override
  final dcpu.BasicOp opcode;

  final MaybeUnassembled<dcpu.Arg> b;
  final MaybeUnassembled<dcpu.Arg> a;

  @override
  Iterable<MaybeUnassembled<dcpu.Arg>> get dependencies => [b, a];

  @override
  Assembled<dcpu.Instruction> assembleWithDeps(AssemblyContext context, Iterable<Assembled<dcpu.Arg>> resolvedDeps) {
    if (resolvedDeps case [Assembled<dcpu.Arg>(value: final b), Assembled<dcpu.Arg>(value: final a)]) {
      return Assembled(
        dcpu.BasicInstruction(op: opcode, b: b, a: a),
        symbolDependencies.toList(),
      );
    } else {
      throw ArgumentError.value(resolvedDeps, 'resolvedDependencies');
    }
  }

  @override
  dcpu.Instruction get substitute => dcpu.BasicInstruction(
        op: opcode,
        b: b.substituteOrValue,
        a: a.substituteOrValue,
      );
}

class UnassembledSpecialInstruction extends UnassembledInstruction {
  const UnassembledSpecialInstruction(this.opcode, this.a);

  @override
  final dcpu.SpecialOp opcode;

  final MaybeUnassembled<dcpu.Arg> a;

  @override
  Iterable<MaybeUnassembled<dcpu.Arg>> get dependencies => [a];

  @override
  Assembled<dcpu.Instruction> assembleWithDeps(AssemblyContext context, Iterable<Assembled<dcpu.Arg>> resolvedDeps) {
    if (resolvedDeps case [Assembled<dcpu.Arg>(value: final a)]) {
      return Assembled(
        dcpu.SpecialInstruction(op: opcode, a: a),
        symbolDependencies.toList(),
      );
    } else {
      throw ArgumentError.value(resolvedDeps, 'resolvedDependencies');
    }
  }

  @override
  dcpu.Instruction get substitute => dcpu.SpecialInstruction(op: opcode, a: a.substituteOrValue);
}

class UnassembledInstructionBytes extends UnassembledDepending<Iterable<int>, dcpu.Instruction> {
  const UnassembledInstructionBytes(this.instruction);

  final Unassembled<dcpu.Instruction> instruction;

  @override
  Iterable<int> get substitute => instruction.substitute.encode();

  @override
  Iterable<MaybeUnassembled<dcpu.Instruction>> get dependencies => [instruction];

  @override
  Assembled<Iterable<int>> assembleWithDeps(
      AssemblyContext context, Iterable<Assembled<dcpu.Instruction>> resolvedDeps) {
    return Assembled(resolvedDeps.single.value.encode());
  }
}

sealed class Assembled<T> extends MaybeUnassembled<T> {
  const factory Assembled(T value, [List<String> symbolDependencies]) = _AssembledImpl;

  @override
  Iterable<String> get symbolDependencies;

  T get value;
}

class _AssembledImpl<T> implements Assembled<T> {
  const _AssembledImpl(this.value, [this.symbolDependencies = const []]);

  @override
  final List<String> symbolDependencies;

  @override
  final T value;

  @override
  T get substituteOrValue => value;
}

dcpu.Op assembleOp(String sourceFile, MyToken<String> mnemonic) {
  return dcpu.Op.values.singleWhere(
    (op) => op.mnemonic.toUpperCase() == mnemonic.value.toUpperCase(),
    orElse: () => throw SemanticError(
      Location.fromToken(mnemonic),
      'Unknown Opcode: ${mnemonic.value}',
    ),
  );
}

MaybeUnassembled<dcpu.Arg> assembleArg(
  InstructionArg ast, {
  required AssemblyContext context,
  required bool isA,
}) {
  switch (ast) {
    case RegisterArg(:final register):
      return Assembled(dcpu.DirectRegisterArg(register.value));

    case IndirectArg(child: RegisterArg(:final register)):
      return Assembled(dcpu.IndirectRegisterArg(register.value));

    case RegisterOffsetArg arg:
      throw SemanticError(
        arg.location,
        'Direct Register + Immediate arguments are not supported by DCPU-16.',
      );

    case IndirectArg(child: RegisterOffsetArg(:final register, :final offsetOp, :final offset)):
      final summand = switch (offsetOp.value) {
        BinOp.add => offset,
        BinOp.sub => Term.unaryOp(
            MyToken.virtual(
              UnaryOp.minus,
              buffer: offsetOp.buffer,
              start: offsetOp.stop,
              stop: offsetOp.stop,
              fileName: offsetOp.fileName,
            ),
            offset,
          ),
        _ => throw SemanticError(
            Location.fromToken(offsetOp),
            'Unsupported operator for indirect immediate addressing',
          ),
      };

      final unassembled = UnassembledIndirectRegisterImmediateArg(
        register.value,
        UnassembledTerm(summand),
      );

      if (unassembled.canAssemble(context)) {
        return unassembled.assemble(context);
      } else {
        return unassembled;
      }

    case SpPlusPlusArg(:final location):
      throw SemanticError(
        location,
        'SP++ is only supported in indirect addressing ([SP++])',
      );

    case IndirectArg(child: SpPlusPlusArg(), :final location):
      return switch (isA) {
        true => const Assembled(dcpu.PushPopArg()),
        false => throw SemanticError(
            location,
            'POP / [SP++] arg is not supported in B.',
          )
      };

    case PopArg(:final location):
      return switch (isA) {
        true => const Assembled(dcpu.PushPopArg()),
        false => throw SemanticError(
            location,
            'POP / [SP++] arg is not supported in B.',
          )
      };

    case IndirectArg(child: PopArg(:final location)):
      throw SemanticError(
        location,
        'POP is only supported with direct addressing.',
      );

    case MinusMinusSpArg(:final location):
      throw SemanticError(
        location,
        '--SP is only supported in indirect addressing ([--SP])',
      );

    case IndirectArg(child: MinusMinusSpArg(:final location)):
      return switch (isA) {
        true => throw SemanticError(
            location,
            'PUSH / [--SP] arg not supported in A.',
          ),
        false => const Assembled(dcpu.PushPopArg()),
      };

    case PushArg(:final location):
      return switch (isA) {
        true => throw SemanticError(
            location,
            'PUSH / [--SP] arg not supported in A.',
          ),
        false => const Assembled(dcpu.PushPopArg()),
      };

    case IndirectArg(child: PushArg(:final location)):
      throw SemanticError(
        location,
        'PUSH / [--SP] is only supported with direct addressing.',
      );

    case PeekArg():
      return const Assembled(
        dcpu.IndirectRegisterArg(Register.sp),
      );

    case IndirectArg(child: PeekArg(:final location)):
      throw SemanticError(
        location,
        'Indirect PEEK is not supported. (i.e. [PEEK])',
      );

    case PickArg(:final offset):
      final unassembled = UnassembledIndirectRegisterImmediateArg(
        Register.sp,
        UnassembledTerm(offset),
      );

      if (unassembled.canAssemble(context)) {
        return unassembled.assemble(context);
      } else {
        return unassembled;
      }

    case IndirectArg(child: PickArg(:final location)):
      throw SemanticError(
        location,
        'Indirect PICK is not supported. (i.e. [PICK 1])',
      );

    case final Term term:
      final unassembled = UnassembledTerm(term);

      if (unassembled.canAssemble(context)) {
        final assembled = unassembled.assemble(context);
        final assembledImm = assembled.value;

        // If we're in arg A, we can try encoding the arg as an immediate arg.
        if (isA && dcpu.SmallImmediateArg.immediateInRange(assembledImm)) {
          return Assembled(
            dcpu.SmallImmediateArg(assembledImm),
            unassembled.symbolDependencies.toList(),
          );
        } else {
          return Assembled(
            dcpu.ImmediateArg(assembledImm),
            unassembled.symbolDependencies.toList(),
          );
        }
      } else {
        return UnassembledImmediateArg(unassembled);
      }

    case IndirectArg(child: final Term term):
      final unassembled = UnassembledIndirectImmediateArg(
        UnassembledTerm(term),
      );

      if (unassembled.canAssemble(context)) {
        return unassembled.assemble(context);
      } else {
        return unassembled;
      }

    case IndirectArg(child: IndirectArg(:final location)):
      throw SemanticError(
        location,
        'Double indirect addressing is not supported. (i.e.: [[x]])',
      );
  }
}

MaybeUnassembled<dcpu.Instruction> assembleInstruction(Instruction ast, {required AssemblyContext context}) {
  final name = ast.mnemonic;
  final astA = ast.argA;
  final astB = ast.argB;

  // assemble the opcode.
  final op = dcpu.Op.values.singleWhere(
    (op) => op.mnemonic.toUpperCase() == name.value.toUpperCase(),
    orElse: () => throw SemanticError(
      Location.fromToken(name),
      'Unknown Opcode',
    ),
  );

  // assemble the arguments.
  final assembledB = switch (astB) {
    null => null,
    _ => assembleArg(astB, context: context, isA: false),
  };

  final assembledA = assembleArg(astA, context: context, isA: true);

  // assemble the complete instruction.
  MaybeUnassembled<dcpu.Instruction> assembled = switch ((op, assembledB, assembledA)) {
    (dcpu.BasicOp(), null, _) => throw SemanticError(
        Location.fromToken(name),
        'Two parameters expected for basic opcode',
      ),
    (
      dcpu.BasicOp op,
      Assembled<dcpu.Arg>(value: final b, symbolDependencies: final depsB),
      Assembled<dcpu.Arg>(value: final a, symbolDependencies: final depsA)
    ) =>
      Assembled(dcpu.BasicInstruction(op: op, b: b, a: a), [...depsB, ...depsA]),
    (dcpu.BasicOp op, MaybeUnassembled<dcpu.Arg> b, MaybeUnassembled<dcpu.Arg> a) =>
      UnassembledBasicInstruction(op, b, a),
    (dcpu.SpecialOp op, null, Assembled<dcpu.Arg>(value: final a, symbolDependencies: final deps)) =>
      Assembled(dcpu.SpecialInstruction(op: op, a: a), deps.toList()),
    (dcpu.SpecialOp op, null, Unassembled<dcpu.Arg> a) => UnassembledSpecialInstruction(op, a),
    (dcpu.SpecialOp(), _, _) => throw SemanticError(
        Location.fromToken(name),
        'Single parameter expected for special opcode',
      ),
  };

  // If the instruction is not yet assembled, but we can assemble it,
  // assemble it here.
  if (assembled case final Unassembled<dcpu.Instruction> unassembledInstr) {
    if (unassembledInstr.canAssemble(context)) {
      // Try to assemble the instruction directly after we've parsed it.
      assembled = unassembledInstr.assemble(context);
    }
  }

  return assembled;
}

class FeatureFlags {
  const FeatureFlags({
    this.logBrkHltInstructions = true,
  });

  static const def = FeatureFlags();

  // Parse and assemble LOG, BRK and HLT instructions
  // supported by tech-compliant DCPU
  final bool logBrkHltInstructions;
}

class Assembler {
  Assembler({this.features = FeatureFlags.def}) : parserDefinition = Dasm16ParserDefinition(features: features);

  final logger = Logger.root;
  final FeatureFlags features;
  final Dasm16ParserDefinition parserDefinition;
  late final parser = parserDefinition.buildFrom(parserDefinition.start());

  AssemblyFile parse(String input, String inputName) {
    logger.finer('PARSING');

    var parser = this.parser;
    if (logger.level <= Level.FINER) {
      parser = trace(
        parser,
        output: (event) {
          if (event case TraceEvent(:final LabelParser? parser)) {
            logger.finer('${'  ' * event.level}${event.result ?? parser?.label}');
          }
        },
      );
    }

    final result = parser.parseOn(MyContext(
      input,
      0,
      fileName: inputName,
    ));

    switch (result) {
      case MyFailure failure:
        throw SyntaxError(
          Location(failure.fileName, result.buffer, result.position, result.position),
          failure.message,
        );
      case Result(value: final assemblyFile):
        return assemblyFile;
    }
  }

  void logEmittedInstruction(Assembled<dcpu.Instruction> instruction) {
    final bytes = instruction.value.encode();

    final disassembly = instruction.value.disassemble();
    final bytesStr = bytes.map(hexstring).join(', ');
    final depsStr = switch (instruction.symbolDependencies) {
      Iterable(isEmpty: true) => 'none',
      Iterable deps => deps.join(', '),
    };

    logger.info(
      'EMIT $bytesStr  ($disassembly, deps: $depsStr)',
    );
  }

  void assembleAndEmitInstruction(
    Instruction ast, {
    required RootAssemblyContext context,
    required AssemblyWriter writer,
    required List<(Unassembled<dcpu.Instruction>, CapturedAssemblyContext, int)> unassembled,
  }) {
    final assembled = assembleInstruction(ast, context: context);

    switch (assembled) {
      case Unassembled<dcpu.Instruction> instruction:
        // We previously tried to assemble/resolve the instruction,
        // but it didn't succeed, probably due to unmet symbol dependencies.
        // (Symbols that are defined later than their use)
        //
        // We keep track of this unassembled instruction and the address
        // where it should be put once assembled, so we can resolve it
        // later.

        unassembled.add((instruction, context.capture(), writer.offset));

        final instrBytes = instruction.substitute.encode().length;

        logger.info(
          'OFFSET += $instrBytes  (Unassembled ${assembled.substituteOrValue.op} instruction)',
        );

        writer.advance(instrBytes);
      case Assembled<dcpu.Instruction> instruction:
        // Instruction was successfully assembled/resolved.
        // We can emit the final bytes directly.

        final instrBytes = instruction.value.encode();

        logEmittedInstruction(instruction);

        writer.emitAndAdvance(instrBytes);
    }
  }

  MaybeUnassembled<int> assembleTerm(Term ast, {required AssemblyContext context}) {
    final unassembled = UnassembledTerm(ast);

    if (unassembled.canAssemble(context)) {
      return unassembled.assemble(context);
    } else {
      return unassembled;
    }
  }

  int evaluateTerm(Term ast, {required AssemblyContext context}) {
    return switch (assembleTerm(ast, context: context)) {
      Unassembled<int> unassembled => throw SemanticError(
          ast.location,
          'Term can not be evaluated. Term must be able to be evaluated in first pass. Missing symbol dependencies: ${unassembled.missingDependencies(context).join(', ')}',
        ),
      Assembled<int>(:final value) => value
    };
  }

  Iterable<(Unassembled<dcpu.Instruction>, CapturedAssemblyContext, int)> firstPass(
    Iterable<TopLevelASTNode> nodes, {
    required RootAssemblyContext context,
    required AssemblyWriter writer,
  }) {
    logger.info('ASSEMBLING - FIRST PASS');

    final unassembled = <(Unassembled<dcpu.Instruction>, CapturedAssemblyContext, int)>[];

    for (final node in nodes) {
      switch (node) {
        case DotInstruction(name: MyToken<String>(value: var name), args: SeparatedList(elements: final args)):
          switch (name.toLowerCase()) {
            case 'org':
              final value = switch (args) {
                [NameOrTerm(:final Term term)] => evaluateTerm(term, context: context),
                _ => throw SemanticError(
                    args.first.location,
                    '.org directive expects a name/literal/term argument',
                  ),
              };

              logger.info('ORG := ${hexstring(value)}');
              writer.offset = value;

            case 'fill':
              final (value, length) = switch (args) {
                [NameOrTerm(term: final Term value), NameOrTerm(term: final Term length)] => (
                    evaluateTerm(value, context: context),
                    evaluateTerm(length, context: context),
                  ),
                _ => throw SemanticError(
                    args.first.location,
                    '.fill directive expects exactly two name/literal/term arguments',
                  ),
              };

              logger.info(
                  '[${hexstring(writer.offset)}..${hexstring(writer.offset + length - 1)}] := ${hexstring(value)}');
              writer.emitAndAdvance(List.filled(length, value));

            case 'reserve':
              final value = switch (args) {
                [NameOrTerm(:final Term term)] => evaluateTerm(term, context: context),
                _ => throw SemanticError(
                    node.location,
                    '.reserve directive expects exactly one name/literal/term argument',
                  )
              };

              logger.info('ORG += ${hexstring(value)}');
              writer.reserve(value);

            case 'include':
              final path = switch (args) {
                [PackedString(flags: [], orValue: null, string: MyToken<String>(value: final path))] => path,
                _ => throw SemanticError(
                    args.first.location,
                    '.include expects exactly one string as argument',
                  ),
              };

              final included = context.resolveInclude(path);
              logger.info('INCLUDE ${included.name}');

              final parsed = parse(included.contents, included.name);
              final additionalUnassembled = firstPass(
                parsed.nodes,
                context: context,
                writer: writer,
              );

              unassembled.addAll(additionalUnassembled);

            case 'symbol':
            case 'sym':
            case 'equ':
            case 'set':
            case 'define':
            case 'def':
              final directiveName = node.name.value.toLowerCase();

              final (name, value) = switch (args) {
                [var name, var value] => (
                    switch (name) {
                      NameOrTerm(name: MyToken<String>(value: final name)) => name,
                      _ => throw SemanticError(
                          name.location,
                          '.$directiveName expects an identifier as it\'s first argument',
                        ),
                    },
                    switch (value) {
                      NameOrTerm(term: final Term term) => evaluateTerm(term, context: context),
                      _ => throw SemanticError(
                          value.location,
                          '.$directiveName expects an identifier/number/term as it\'s second argument',
                        ),
                    }
                  ),
                _ => throw SemanticError(
                    node.location,
                    '$directiveName expects exactly two arguments.',
                  ),
              };

              logger.info('LET CONST $name := $value');
              context.defineConstant(name, value);

            case 'undef':
              final name = switch (args) {
                [NameOrTerm(name: MyToken<String>(value: final name))] => name,
                _ => throw SemanticError(
                    args.first.location,
                    '.${node.name.value.toLowerCase()} expects exactly one identifier as it\'s second argument.',
                  ),
              };

              logger.info('LET CONST $name := nil');
              context.undefConstant(name);

            case 'dat':
              for (final arg in args) {
                switch (arg) {
                  case NameOrTerm(:final Term term):
                    final value = evaluateTerm(term, context: context);
                    logger.info('[${hexstring(writer.offset)}] := ${hexstring(value)}');

                    writer.emitAndAdvance([value]);

                  case PackedString(string: MyToken<String>(value: final string)):
                    final words = ascii.encode(string);
                    logger.info(
                      '[${hexstring(writer.offset)}..${hexstring(writer.offset + words.length - 1)}] := "$string"',
                    );

                    writer.emitAndAdvance(words);

                  default:
                    throw UnimplementedError();
                }
              }

            default:
              throw SemanticError(Location.fromToken(node.name), 'Unknown pseudo-instruction');
          }

        case MacroDefinition(name: MyToken<String>(value: final name)):
          logger.info('LET MACRO $name := $node');
          context.defineMacro(name, node);

        case MacroInvocation(name: MyToken<String>(value: final name), :final location):
          if (!context.macroDefined(name)) {
            throw SemanticError(location, 'Invocation of undefined macro $name');
          }

          logger.info('MACRO $name');
          throw UnimplementedError();

        case InstructionOrMacroInvocation(
            macroInvocation: MacroInvocation(name: MyToken<String>(value: final name)),
            instruction: final instr
          ):
          if (context.macroDefined(name)) {
            logger.info('MACRO $name');
            throw UnimplementedError();
          } else {
            assembleAndEmitInstruction(
              instr,
              writer: writer,
              context: context,
              unassembled: unassembled,
            );
          }

        case LabelDeclaration(name: LabelName(name: MyToken<String>(value: final name))):

          // Save the symbol in our context.
          Logger.root.info('LET LABEL $name := ${hexstring(writer.offset)}');
          context.defineLabel(name, writer.offset);

        case Instruction instr:
          assembleAndEmitInstruction(
            instr,
            writer: writer,
            context: context,
            unassembled: unassembled,
          );
      }
    }

    return unassembled;
  }

  List<int> assemble(
    String filePath,
    File file,
    List<Directory> includeSearchPath, {
    Endian endian = Endian.little,
  }) {
    final writer = AssemblyWriter();
    final context = RootAssemblyContext(includeSearchPath);

    final parsed = parse(file.readAsStringSync(), filePath);

    final unassembled = firstPass(
      parsed.nodes,
      context: context,
      writer: writer,
    );

    logger.info('ASSEMBLING - SECOND PASS');
    for (final (instr, context, offset) in unassembled) {
      if (!instr.canAssemble(context)) {
        final unmetDeps = instr.symbolDependencies.where((symbol) => !context.symbolDefined(symbol));
        logger.severe('Could not assemble instruction in 2nd pass, unmet symbol dependencies: ${unmetDeps.join(', ')}');
      } else {
        final assembled = instr.assemble(context);

        final instrBytes = assembled.value.encode();
        if (instrBytes.length != instr.substitute.encode().length) {
          throw StateError('Assembled instruction length differs from unassembled substitute');
        }

        logEmittedInstruction(assembled);

        writer.emitAt(instrBytes, offset);
      }
    }

    return writer.toBytes(endian: endian);
  }
}
