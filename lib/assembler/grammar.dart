// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:petitparser/debug.dart';
import 'package:petitparser/petitparser.dart' as petitparser;
import 'package:petitparser/petitparser.dart';

import 'package:dcpu_flutter/core/cpu.dart' show Register;
import 'package:dcpu_flutter/core/instructions.dart' as dcpu;
import 'package:dcpu_flutter/core/math.dart';

class MyContext implements Context {
  const MyContext(
    this.buffer,
    this.position, {
    required this.fileName,
  });

  final String fileName;

  @override
  final String buffer;

  @override
  final int position;

  @override
  MyFailure<R> failure<R>(String message, [int? position]) {
    return MyFailure(
      buffer,
      position ?? this.position,
      message,
      fileName: fileName,
    );
  }

  @override
  MySuccess<R> success<R>(R result, [int? position]) {
    return MySuccess(
      buffer,
      position ?? this.position,
      result,
      fileName: fileName,
    );
  }

  @override
  String toPositionString() => MyToken.positionString(buffer, position);

  @override
  String toString() => 'FileContext[${toPositionString()}]';
}

sealed class MyResult<R> extends MyContext implements Result<R> {
  const MyResult(
    super.buffer,
    super.position, {
    required super.fileName,
  });

  @override
  bool get isFailure => false;

  @override
  bool get isSuccess => false;

  @override
  String get message;

  @override
  R get value;
}

class MySuccess<R> extends MyResult<R> implements Success<R> {
  const MySuccess(
    super.buffer,
    super.position,
    this.value, {
    required super.fileName,
  });

  @override
  bool get isSuccess => true;

  @override
  final R value;

  @override
  String get message => throw UnsupportedError('Successful parse results do not have a message.');

  @override
  String toString() => 'Success[${toPositionString()}]: $value';
}

class MyFailure<R> extends MyResult<R> implements Failure<R> {
  const MyFailure(
    super.buffer,
    super.position,
    this.message, {
    required super.fileName,
  });

  @override
  bool get isFailure => true;

  @override
  R get value => throw ParserException(this);

  @override
  final String message;

  @override
  String toString() => 'Failure[${toPositionString()}]: $message';
}

class ContextPreservingTrimmingParser<R> extends DelegateParser<R, R> implements TrimmingParser<R> {
  ContextPreservingTrimmingParser(super.delegate, this.left, this.right);

  /// Parser that consumes input before the delegate.
  @override
  Parser<void> left;

  /// Parser that consumes input after the delegate.
  @override
  Parser<void> right;

  @override
  Result<R> parseOn(Context context) {
    // Trim the left part:
    context = _trim(left, context);

    // Consume the delegate:
    final result = delegate.parseOn(context);
    if (result.isFailure) {
      return result;
    }

    // Trim the right part:
    final after = _trim(right, result);
    return after == result ? result : result.success(result.value, after.position);
  }

  @override
  int fastParseOn(String buffer, int position) {
    throw UnimplementedError();
  }

  Context _trim(Parser parser, Context context) {
    for (;;) {
      final result = parser.parseOn(context);
      if (result.isFailure) {
        break;
      }

      context = context.success(result.value, result.position);
    }

    return context;
  }

  @override
  ContextPreservingTrimmingParser<R> copy() => ContextPreservingTrimmingParser<R>(delegate, left, right);

  @override
  List<Parser> get children => [delegate, left, right];

  @override
  void replace(covariant Parser source, covariant Parser target) {
    super.replace(source, target);
    if (left == source) {
      left = target;
    }
    if (right == source) {
      right = target;
    }
  }
}

extension ContextPreservingTrimmingParserExtension<R> on Parser<R> {
  Parser<R> trimPreserve([Parser<void>? left, Parser<void>? right]) {
    return ContextPreservingTrimmingParser(
      this,
      left ?? whitespace(),
      right ?? left ?? whitespace(),
    );
  }
}

class MyTokenParser<R> extends DelegateParser<R, MyToken<R>> {
  MyTokenParser(super.delegate);

  @override
  Result<MyToken<R>> parseOn(Context context) {
    final result = delegate.parseOn(context);
    if (result.isSuccess) {
      final token = MyToken<R>(
        result.value,
        context.buffer,
        context.position,
        result.position,
        fileName: (result as MyResult).fileName,
      );
      return result.success(token);
    } else {
      return result.failure(result.message);
    }
  }

  @override
  int fastParseOn(String buffer, int position) => delegate.fastParseOn(buffer, position);

  @override
  MyTokenParser<R> copy() => MyTokenParser<R>(delegate);
}

extension MyTokenParserExtension<R> on Parser<R> {
  Parser<MyToken<R>> dasmToken() => MyTokenParser<R>(this);
}

class SomeOfParser<R> extends ListParser<R, List<R?>> {
  SomeOfParser(super.children, {FailureJoiner<R>? failureJoiner}) : failureJoiner = failureJoiner ?? selectFarthest;

  FailureJoiner<R> failureJoiner;

  @override
  SomeOfParser<R> copy() {
    return SomeOfParser(children.toList());
  }

  @override
  Result<List<R?>> parseOn(Context context) {
    final results = [
      for (final child in children) child.parseOn(context),
    ];

    if (results.every((element) => element.isFailure)) {
      final result = results.cast<Failure<R>>().reduce(failureJoiner);
      return result.failure(result.message);
    }

    final succeeded = results.whereType<Success>();

    if (succeeded.skip(1).any((element) => element.position != succeeded.first.position)) {
      return context.failure('Ambigous anyOf continuation');
    }

    final list = results.map((e) {
      if (e case Success(:final value)) {
        return value;
      } else {
        return null;
      }
    }).toList();

    return context.success(list, succeeded.first.position);
  }
}

class MyToken<T> extends Token<T> {
  const MyToken(
    super.value,
    super.buffer,
    super.start,
    super.stop, {
    required this.fileName,
  });

  final String fileName;

  static List<int> lineAndColumnOf(String buffer, int position) {
    return Token.lineAndColumnOf(buffer, position);
  }

  static String positionString(String buffer, int position) {
    return Token.positionString(buffer, position);
  }
}

extension TokenMap<T> on Parser<Token<T>> {
  Parser<Token<R>> mapToken<R>(R Function(T) fn) {
    return map<Token<R>>((token) {
      return Token<R>(
        fn(token.value),
        token.buffer,
        token.start,
        token.stop,
      );
    });
  }
}

extension MyTokenMap<T> on Parser<MyToken<T>> {
  Parser<MyToken<R>> mapToken<R>(R Function(T) fn) {
    return map<MyToken<R>>((token) {
      return MyToken<R>(
        fn(token.value),
        token.buffer,
        token.start,
        token.stop,
        fileName: token.fileName,
      );
    });
  }
}

enum BinOp { add, sub, bitwiseOr }

enum UnaryOp { minus }

sealed class ASTNode {
  const ASTNode();

  Iterable<MyToken> get tokens;

  Location get location => Location.coverTokens(tokens);
}

class AssemblyFile extends ASTNode {
  const AssemblyFile(this.nodes);

  final List<TopLevelASTNode> nodes;

  @override
  Iterable<MyToken> get tokens => nodes.expand((element) => element.tokens);
}

sealed class TopLevelASTNode extends ASTNode {
  const TopLevelASTNode();
}

class DotInstruction extends TopLevelASTNode {
  const DotInstruction(this.prefix, this.name, this.args);

  final MyToken<String> prefix;
  final MyToken<String> name;
  final SeparatedList<DotInstrArg, MyToken<String>> args;

  @override
  Iterable<MyToken> get tokens => [
        prefix,
        name,
        ...args.sequential.expand((element) {
          if (element case DotInstrArg()) {
            return element.tokens;
          } else if (element case MyToken<String>()) {
            return [element];
          } else {
            throw ArgumentError.value(element, 'element');
          }
        })
      ];

  @override
  String toString() => 'DotInstruction(prefix: $prefix, name: $name, args: $args)';
}

sealed class DotInstrArg extends ASTNode {
  const DotInstrArg();

  factory DotInstrArg.nameOrTerm(MyToken<String>? name, Term? term) {
    return NameOrTerm(name, term);
  }

  factory DotInstrArg.string(List<MyToken<StringPackingFlag>> flags, MyToken<int>? orValue, MyToken<String> string) =
      PackedString;
}

class NameOrTerm extends DotInstrArg {
  NameOrTerm(this.name, this.term);

  final MyToken<String>? name;
  final Term? term;

  @override
  String toString() => 'NameOrTermDotInstrArg(name: $name, term: $term)';

  @override
  Iterable<MyToken> get tokens => [
        ...?term?.tokens,
        if (name != null) name!,
      ];
}

enum StringPackingFlag {
  packed,
  swapped,
  zeroZerminate,
  wordZeroTerminate,
  octetPascalLength,
  wordPascalLength,
}

class PackedString extends DotInstrArg {
  const PackedString(this.flags, this.orValue, this.string);

  final List<MyToken<StringPackingFlag>> flags;
  final MyToken<int>? orValue;
  final MyToken<String> string;

  bool hasFlag(StringPackingFlag flag) {
    return flags.any((element) => element.value == flag);
  }

  @override
  Iterable<MyToken> get tokens => [
        ...flags,
        if (orValue != null) orValue!,
        string,
      ];

  @override
  String toString() => 'StringDotInstrArg(flags: $flags, orValue: $orValue, string: $string)';

  String toStringShort() {
    return 'StringDotInstrArg(${flags.map((e) => e.value.name).join()}"${string.value}" | $orValue)';
  }
}

class MacroDefinition extends TopLevelASTNode {
  const MacroDefinition(this.name, this.equals, this.rest);

  final MyToken<String> name;

  final MyToken<String> equals;

  final MyToken<String> rest;

  @override
  Iterable<MyToken> get tokens => [name];
}

class MacroInvocation extends TopLevelASTNode {
  const MacroInvocation(this.name);

  final MyToken<String> name;

  @override
  Iterable<MyToken> get tokens => [name];
}

class InstructionOrMacroInvocation extends TopLevelASTNode {
  const InstructionOrMacroInvocation(this.instruction, this.macroInvocation);

  final Instruction instruction;
  final MacroInvocation macroInvocation;

  @override
  Iterable<MyToken> get tokens => instruction.tokens;
}

class LabelName extends ASTNode {
  const LabelName(this.name);

  final MyToken<String> name;

  @override
  Iterable<MyToken> get tokens => [name];

  @override
  String toString() => 'LabelName(name: $name)';
}

class LabelDeclaration extends TopLevelASTNode {
  const LabelDeclaration(this.labelSign, this.name);

  final MyToken<String> labelSign;
  final LabelName name;

  @override
  Iterable<MyToken> get tokens => [labelSign, ...name.tokens];

  @override
  String toString() => 'Label(name: $name)';
}

class Instruction extends TopLevelASTNode {
  const Instruction({
    required this.mnemonic,
    required this.argB,
    required this.argA,
  });

  final MyToken<String> mnemonic;

  final InstructionArg? argB;
  final InstructionArg argA;

  @override
  Iterable<MyToken> get tokens => [
        mnemonic,
        if (argB != null) ...argB!.tokens,
        ...argA.tokens,
      ];

  @override
  String toString() => 'Instruction(mnemonic: $mnemonic, argB: $argB, argA: $argA)';
}

sealed class InstructionArg extends ASTNode {
  const InstructionArg();

  const factory InstructionArg.indirect(
      MyToken<String> openBracket, InstructionArg inner, MyToken<String> closeBracket) = IndirectArg;

  const factory InstructionArg.register(MyToken<Register> register) = RegisterArg;

  const factory InstructionArg.registerOffset(MyToken<Register> register, MyToken<BinOp> op, Term offset) =
      RegisterOffsetArg;

  const factory InstructionArg.push(MyToken<String> token) = PushArg;

  const factory InstructionArg.spPlusPlus(MyToken<String> sp, MyToken<String> plusPlus) = SpPlusPlusArg;

  const factory InstructionArg.pop(MyToken<String> token) = PopArg;

  const factory InstructionArg.minusMinusSp(MyToken<String> minusMinus, MyToken<String> sp) = MinusMinusSpArg;

  const factory InstructionArg.peek(MyToken<String> token) = PeekArg;

  const factory InstructionArg.pick(MyToken<String> pick, Term offset) = PickArg;
}

class IndirectArg extends InstructionArg {
  const IndirectArg(this.openBracketToken, this.child, this.closeBracketToken);

  final MyToken<String> openBracketToken;
  final InstructionArg child;
  final MyToken<String> closeBracketToken;

  @override
  String toString() => 'IndirectArg(child: $child)';

  @override
  Iterable<MyToken> get tokens => [
        openBracketToken,
        ...child.tokens,
        closeBracketToken,
      ];
}

class RegisterArg extends InstructionArg {
  const RegisterArg(this.register);

  final MyToken<Register> register;

  @override
  Iterable<MyToken> get tokens => [register];

  @override
  String toString() => 'RegisterArg(register: $register)';
}

class RegisterOffsetArg extends InstructionArg {
  const RegisterOffsetArg(this.register, this.offsetOp, this.offset);

  final MyToken<Register> register;
  final MyToken<BinOp> offsetOp;
  final Term offset;

  @override
  Iterable<MyToken> get tokens => [
        register,
        offsetOp,
        ...offset.tokens,
      ];

  @override
  String toString() => 'RegisterOffsetArg(register: $register, offsetOp: $offsetOp, offset: $offset)';
}

class PushArg extends InstructionArg {
  const PushArg(this.token);

  final MyToken<String> token;

  @override
  get tokens => [token];

  @override
  String toString() => 'PushArg(token: $token)';
}

class SpPlusPlusArg extends InstructionArg {
  const SpPlusPlusArg(this.spToken, this.plusPlusToken);

  final MyToken<String> spToken;
  final MyToken<String> plusPlusToken;

  @override
  Iterable<MyToken> get tokens => [spToken, plusPlusToken];

  @override
  String toString() => 'SpPlusPlusArg(spToken: $spToken, plusPlusToken: $plusPlusToken)';
}

class PopArg extends InstructionArg {
  const PopArg(this.token);

  final MyToken<String> token;

  @override
  Iterable<MyToken> get tokens => [token];

  @override
  String toString() => 'PopArg(token: $token)';
}

class MinusMinusSpArg extends InstructionArg {
  const MinusMinusSpArg(this.minusMinusToken, this.spToken);

  final MyToken<String> minusMinusToken;
  final MyToken<String> spToken;

  @override
  Iterable<MyToken> get tokens => [minusMinusToken, spToken];

  @override
  String toString() => 'MinusMinusSpArg(minusMinusToken: $minusMinusToken, spToken: $spToken)';
}

class PeekArg extends InstructionArg {
  const PeekArg(this.token);

  final MyToken<String> token;

  @override
  Iterable<MyToken> get tokens => [token];

  @override
  String toString() => 'PeekArg(token: $token)';
}

class PickArg extends InstructionArg {
  const PickArg(this.pickToken, this.offset);

  final MyToken<String> pickToken;
  final Term offset;

  @override
  Iterable<MyToken> get tokens => [pickToken, ...offset.tokens];

  @override
  String toString() => 'PickArg(pickToken: $pickToken, offset: $offset)';
}

sealed class Term extends ASTNode implements InstructionArg {
  const Term();

  const factory Term.literal(MyToken<int> value) = LiteralTerm;
  const factory Term.label(LabelName label) = LabelTerm;
  const factory Term.binOp(Term lhs, MyToken<BinOp> op, Term rhs) = BinaryOpTerm;
  const factory Term.unaryOp(MyToken<UnaryOp> op, Term a) = UnaryOpTerm;

  Iterable<String> get symbolDependencies;
}

class LiteralTerm extends Term {
  const LiteralTerm(this.value);

  final MyToken<int> value;

  @override
  Iterable<MyToken> get tokens => [value];

  @override
  Iterable<String> get symbolDependencies => [];

  @override
  String toString() => 'LiteralTerm(value: $value)';
}

class LabelTerm extends Term {
  const LabelTerm(this.label);

  final LabelName label;

  @override
  Iterable<MyToken> get tokens => [...label.tokens];

  @override
  Iterable<String> get symbolDependencies => [label.name.value];

  @override
  String toString() => 'LabelTerm(label: $label)';
}

class BinaryOpTerm extends Term {
  const BinaryOpTerm(this.lhs, this.op, this.rhs);

  final MyToken<BinOp> op;
  final Term lhs;
  final Term rhs;

  @override
  Iterable<MyToken> get tokens => [op, ...lhs.tokens, ...rhs.tokens];

  @override
  Iterable<String> get symbolDependencies => [
        ...lhs.symbolDependencies,
        ...rhs.symbolDependencies,
      ];

  @override
  String toString() => 'BinOpTerm(op: $op, a: $lhs, b: $rhs)';
}

class UnaryOpTerm extends Term {
  const UnaryOpTerm(this.op, this.child);

  final MyToken<UnaryOp> op;
  final Term child;

  @override
  Iterable<MyToken> get tokens => [op, ...child.tokens];

  @override
  Iterable<String> get symbolDependencies => child.symbolDependencies;

  @override
  String toString() => 'UnaryOpTerm(op: $op, child: $child)';
}

class Dasm16ParserDefinition extends GrammarDefinition {
  Dasm16ParserDefinition._construct();

  factory Dasm16ParserDefinition() {
    return Dasm16ParserDefinition._construct();
  }

  @override
  Parser<AssemblyFile> start() {
    return file;
  }

  Parser<R> seq2PickFirst<R>(Parser<R> first, Parser second) {
    return seq2(first, second).map2((a, b) => a);
  }

  Parser<R> seq2PickSecond<R>(Parser first, Parser<R> second) {
    return seq2(first, second).map2((a, b) => b);
  }

  late final file = seq2PickFirst(
    line.star().map((line) => line.expand((nodes) => nodes).toList()),
    endOfInput() | line,
  ).map((nodes) => AssemblyFile(nodes));

  late final line = ChoiceParser(
    <Parser>[
      labelLine,
      macroDefinitionLine,
      pseudoInstructionLine,
      instructionOrMacroInvocationLine,
      emptyLine,
    ],
    failureJoiner: selectFarthest,
  ).map((value) {
    if (value case TopLevelASTNode node) {
      return [node];
    } else if (value case List<TopLevelASTNode> list) {
      return list;
    } else if (value case null) {
      return <TopLevelASTNode>[];
    } else {
      throw ArgumentError.value(value, 'value');
    }
  }).labeled('line');

  late final macroDefinitionLine = seq6(
    dotToken,
    directiveNameToken.where(
      (value) => value.value.toLowerCase() == 'macro',
    ),
    identifier,
    equalsToken,
    newline().neg().plus().flatten().dasmToken(),
    newline(),
  ).map6((_, __, name, equals, contents, ___) {
    return MacroDefinition(name, equals, contents);
  }).labeled('macro definition line');

  late final pseudoInstructionLine = seq3(
    labelDeclaration.optional(),
    pseudoInstruction,
    newline('Unexpected character'),
  ).map((values) {
    return [
      if (values.first != null) values.first!,
      values.second,
    ];
  }).labeled('pseudo instruction line');

  late final pseudoInstruction = seq3(
    dotToken,
    directiveNameToken,
    pseudoInstructionArgs,
  ).map((values) {
    return DotInstruction(values.first, values.second, values.third);
  });

  late final pseudoInstructionArgs = pseudoInstructionArg.plusSeparated(commaToken);

  late final pseudoInstructionArg = ChoiceParser([
    packedString,
    SomeOfParser([
      identifier,
      term,
    ]).map((values) {
      return DotInstrArg.nameOrTerm(
        values[0] as MyToken<String>?,
        values[1] as Term?,
      );
    })
  ]);

  late final packedString = seq3(
    ChoiceParser([
      anyOf('kK').map((_) => StringPackingFlag.packed).dasmToken(),
      anyOf('sS').map((_) => StringPackingFlag.swapped).dasmToken(),
      anyOf('zZ').map((_) => StringPackingFlag.zeroZerminate).dasmToken(),
      anyOf('xX').map((_) => StringPackingFlag.wordZeroTerminate).dasmToken(),
      anyOf('aA').map((_) => StringPackingFlag.octetPascalLength).dasmToken(),
      anyOf('pP').map((_) => StringPackingFlag.wordPascalLength).dasmToken(),
    ]).star(),
    ((hexNumber | decimalNumber).flatten().map(int.parse)).dasmToken().optional(),
    seq3(
      char('"'),
      (char('\\').not() & char('"')).neg().star().flatten(),
      char('"'),
    ).map3((_, str, __) => str).dasmToken(),
  ).map3(DotInstrArg.string).trimPreserve(space);

  late final labelLine = seq2PickFirst(
    labelDeclaration,
    newline('Unexpected character'),
  ).map((value) => [value]);

  late final instructionOrMacroInvocationLine = seq3(
    labelDeclaration.optional(),
    instructionOrMacroInvocation,
    newline('Unexpected character'),
  ).map((values) {
    return [
      if (values.first != null) values.first!,
      values.second,
    ];
  }).labeled('instruction or macro invocation line');

  late final instructionOrMacroInvocation = SomeOfParser(
    <Parser<TopLevelASTNode>>[instruction, macroInvocation],
    failureJoiner: selectFarthest,
  ).map<TopLevelASTNode>((value) {
    final first = value[0] as Instruction?;
    final second = value[1] as MacroInvocation?;

    if (first != null && second != null) {
      return InstructionOrMacroInvocation(first, second);
    } else if (first != null) {
      return first;
    } else if (second != null) {
      return second;
    } else {
      throw ArgumentError.value(value, 'value');
    }
  });

  late final macroInvocation = seq2(
    identifier,
    ChoiceParser([term, arg]).starSeparated(commaToken),
  ).map2((name, args) => MacroInvocation(name));

  late final emptyLine =
      seq2(space.star(), newline('Unexpected character')).map((_) => <TopLevelASTNode>[]).labeled('empty line');

  late final labelDeclaration = ChoiceParser([
    seq2(labelSign, labelName).map2(
      (sign, name) => LabelDeclaration(sign, name),
    ),
    seq2(labelName, labelSign).map2(
      (name, sign) => LabelDeclaration(sign, name),
    )
  ]);

  late final labelSign = colonToken;
  late final labelName = labelNameToken.map((token) => LabelName(token));

  late final instruction = seq2(instructionName, instructionArgs).map2(
    (name, args) {
      return Instruction(
        mnemonic: name,
        argB: args.$1,
        argA: args.$2,
      );
    },
  ).labeled('instruction');

  late final instructionName = mnemonicToken.labeled('instruction name');

  late final instructionArgs = seq2(arg, seq2PickSecond(commaToken, arg).optional()).map2((first, second) {
    if (second == null) {
      return (null, second ?? first);
    } else {
      return (first, second);
    }
  }).labeled('instruction arguments');

  late final indirectArg = seq3(
    openBracketToken,
    ref0(() => arg),
    closeBracketToken,
  ).map3(InstructionArg.indirect).labeled('indirect arg');

  late final Parser<InstructionArg> arg = ChoiceParser<InstructionArg>(
    [
      pushArg,
      minusMinusSpArg,
      popArg,
      spPlusPlusArg,
      peekArg,
      pickArg,
      registerOffsetArg,
      registerArg,
      immediateArg,
      indirectArg
    ],
    failureJoiner: selectFarthest,
  ).labeled('instruction argument');

  late final registerOffsetArg = seq3(registerName, binOp, term).map3(InstructionArg.registerOffset);

  late final registerArg = registerName.map(InstructionArg.register);

  late final pushArg = pushToken.map(InstructionArg.push);

  late final minusMinusSpArg = seq2(minusMinusToken, spToken).map2(InstructionArg.minusMinusSp);

  late final popArg = popToken.map(InstructionArg.pop);

  late final spPlusPlusArg = seq2(spToken, plusPlusToken).map2(InstructionArg.spPlusPlus);

  late final peekArg = peekToken.map(InstructionArg.peek);

  late final pickArg = seq2(pickToken, term).map2(InstructionArg.pick);

  late final immediateArg = term;

  static const _registerNames = {
    'A': Register.a,
    'B': Register.b,
    'C': Register.c,
    'X': Register.x,
    'Y': Register.y,
    'Z': Register.z,
    'I': Register.i,
    'J': Register.j,
    'PC': Register.pc,
    'SP': Register.sp,
    'EX': Register.ex
  };

  late final registerName = identifier.where((token) {
    return _registerNames.containsKey(token.value.toUpperCase());
  }).mapToken(
    (value) => _registerNames[value.toUpperCase()]!,
  );

  late final Parser<Term> term = ChoiceParser([
    seq3(
      atomicTerm,
      binOp,
      ref0(() => term),
    ).map3(Term.binOp),
    seq2(
      unaryOp,
      ref0(() => term),
    ).map2(Term.unaryOp),
    atomicTerm,
  ]);
  late final atomicTerm = ChoiceParser([numberTerm, labelTerm]);
  late final numberTerm = numberToken.map(Term.literal);
  late final labelTerm = labelName.map(Term.label);

  late final binOp = ChoiceParser([add, sub, bitwiseOr]).labeled('binary operation');
  late final add = plusToken.mapToken((value) => BinOp.add);
  late final sub = minusToken.mapToken((value) => BinOp.sub);
  late final bitwiseOr = pipeToken.mapToken((value) => BinOp.bitwiseOr);

  late final unaryOp = unaryMinus;
  late final unaryMinus = minusToken.mapToken((_) => UnaryOp.minus);

  late final space = char(' ') | char('\t') | commentSingle;
  late final commentSingle = char(';') & newline().neg().star();

  Parser<MyToken<R>> nonFlattenToken<R>(
    Parser<R> parser, {
    String? failureMessage,
    String? label,
  }) {
    if (failureMessage != null) {
      parser = parser.callCC((continuation, context) {
        var result = continuation(context);

        // map the error message
        if (result is Failure) {
          result = result.failure(failureMessage, result.position);
        }

        return result;
      });
    }

    var tokenParser = parser.dasmToken().trimPreserve(space);

    if (label != null) {
      tokenParser = tokenParser.labeled(label);
    }

    return tokenParser;
  }

  Parser<MyToken<String>> token(
    Parser parser, {
    String? failureMessage,
    String? label,
  }) {
    var stringParser = parser.flatten();

    if (failureMessage != null) {
      stringParser = stringParser.callCC((continuation, context) {
        var result = continuation(context);

        // map the error message
        if (result is Failure) {
          result = result.failure(failureMessage, result.position);
        }

        return result;
      });
    }

    var tokenParser = stringParser.dasmToken().trimPreserve(space);

    if (label != null) {
      tokenParser = tokenParser.labeled(label);
    }

    return tokenParser;
  }

  Parser<MyToken<String>> patternToken(
    String pattern, {
    String? failureMessage,
    String? label,
  }) {
    var stringParser = pattern.toParser().flatten();

    if (failureMessage != null) {
      stringParser = stringParser.callCC((continuation, context) {
        var result = continuation(context);

        // map the error message
        if (result is Failure) {
          result = result.failure(failureMessage, result.position);
        }

        return result;
      });
    }

    var tokenParser = stringParser.dasmToken().trimPreserve(space);

    if (label != null) {
      tokenParser = tokenParser.labeled(label);
    }

    return tokenParser;
  }

  late final numberToken = token(
    hexNumber | decimalNumber,
    failureMessage: 'Number expected',
    label: 'number',
  ).mapToken(int.parse);

  late final hexNumber = string('0x') & pattern('0-9a-fA-F').plus();
  late final decimalNumber = digit().plus();

  late final mnemonicToken = token(
    pattern('a-zA-Z').star() & pattern('0-9._').not('Invalid opcode character'),
    failureMessage: 'Opcode mnemonic expected',
  );

  late final identifierStartChar = pattern('0-9.')
      .not('Identifiers can\'t start with a dot, underscore or decimal digit.')
      .and()
      .seq(identifierMidChar);

  late final identifierMidChar = pattern('a-zA-Z0-9._');

  late final identifierEndChar = char('.').not('Identifiers cant end with a dot.').and().seq(identifierMidChar);

  late final identifier = token(
    identifierStartChar.and() &
        identifierMidChar.starLazy(
          identifierMidChar.optional() & identifierMidChar.not(),
        ) &
        identifierEndChar,
    label: 'identifier token',
  );

  late final labelNameToken = identifier;

  late final directiveNameToken = token(
    pattern('a-zA-Z')
            .plus()
            .flatten('Invalid character in pseudo instruction. Pseudo instructions must be alphabetic.') &
        pattern('0-9_.').not('Invalid character in pseudo instruction. Pseudo instructions must be alphabetic.'),
  );

  late final spToken = token(
    stringIgnoreCase('SP') & pattern('0-9a-zA-Z_.').not(),
    failureMessage: 'SP expected',
    label: 'SP',
  );

  late final openBracketToken = patternToken('[');

  late final closeBracketToken = patternToken(']');

  late final commaToken = patternToken(',');

  late final plusPlusToken = patternToken('++');
  late final minusMinusToken = patternToken('--');

  late final plusToken = token(char('+') & char('+').not());
  late final minusToken = token(char('-') & char('-').not());
  late final pipeToken = token(char('|') & char('|').not());

  late final dotToken = patternToken('.');
  late final numberSignToken = patternToken('#');

  late final colonToken = patternToken(':');

  late final stringToken = nonFlattenToken(
    seq3(char('"'), char('"').neg().star().flatten(), char('"')).map3((_, str, __) => str),
    failureMessage: 'String expected',
    label: 'string',
  );

  late final peekToken = token(
    stringIgnoreCase('PEEK'),
    failureMessage: 'PEEK expected',
    label: 'PEEK',
  );

  late final pickToken = token(
    stringIgnoreCase('PICK'),
    failureMessage: 'PICK expected',
    label: 'PICK',
  );

  late final pushToken = token(
    stringIgnoreCase('PUSH'),
    failureMessage: 'PUSH expected',
    label: 'PUSH',
  );

  late final popToken = token(
    stringIgnoreCase('POP'),
    failureMessage: 'POP expected',
    label: 'POP',
  );

  late final equalsToken = token(
    char('=') & char('=').not(),
  );
}

const test1 =
    '''
#include "AtlasOS 0.6.2"

#include "../include/kernel.inc"

SET PC, kernel_boot

; Kernel
#include "drivers.dasm16"
#include "filesystem.dasm16"
#include "graphics.dasm16"
#include "interrupts.dasm16"
#include "library.dasm16"
#include "memory.dasm16"
#include "messages.dasm16"
#include "process.dasm16"

:kernel_boot
JSR bios_boot

; Set the interrupt handler first
IAS kernel_interrupt_handler

; clear screen (for emulator)
JSR clear

; Display the logo
SET A, text_logo
JSR text_out

; Bootmessage
SET A, text_start
JSR text_out

; Reserve kernel-memory
SET X, 0
:kernel_mem
IFG X, kernel_end
    SET PC, kernel_mem_end
SET A, X
JSR page_reserve
ADD X, 1024
SET PC, kernel_mem
:kernel_mem_end

; Reserve misc-memory
SET X, os_content
:os_content_mem
IFG X, os_content_end
    SET PC, os_content_mem_end
SET A, X
JSR page_reserve
ADD X, 1024
SET PC, os_content_mem
:os_content_mem_end

; Reserve stack-memory
SET A, 0xFFFF
JSR page_reserve

; Reserve the API space
SET A, 0x1000
JSR page_reserve

SET X, 0

; Copy the API.
SET B, 0x1000
SET A, api_start
SET C, api_end
SUB C, A
JSR mem_copy

; Clear out a few things
SET [keyboard_buffers_exclusive], 0
SET [keyboard_oldvalue], 0
JSR keyboard_unregister_all

; OS ready message
SET A, text_start_ok
JSR text_out

; Main kernel loop
:kernel_loop

	; Call the keyboard driver
	JSR driver_keyboard
	
	; Check if the kernel is the only running process, if so start the shell
	JSR kernel_watchdog_checkalone

	; Release back to other running processes
	INT 0xFEDC
	;JSR proc_suspend
	
    SET PC, kernel_loop

; Watchdog to ensure the shell is always running even if in the background
:kernel_watchdog_checkalone
	SET PUSH, C
	SET PUSH, B
	SET PUSH, A

	SET C, kernel_watchdog_proc_list_buffer
	SET A, kernel_watchdog_helper
	JSR proc_callback_list
	SET C, kernel_watchdog_proc_list_buffer
	ADD C, 1
	IFE [C], 0
		JSR kernel_watchdog_loadshell

	; Clear the proc buffer
	SET C, kernel_watchdog_proc_list_buffer
	SET [C], 0
	ADD C, 1
	SET [C], 0

	SET A, POP
	SET B, POP
	SET C, POP
	SET PC, POP
:kernel_watchdog_helper
	IFE C, kernel_watchdog_proc_list_buffer_end
		SET PC, POP
	SET [C], A
	ADD C, 1
	SET PC, POP
:kernel_watchdog_loadshell
	; This is a workaround so the shell doesn't freak out
	; when there is no data in the keyboard buffer
	SET [keyboard_oldvalue], 0xFFFF
	; Now start the shell
	SET A, AtlasShell
	SET B, AtlasShell_end
	SUB B, AtlasShell
	JSR proc_load
	SET PC, POP
	
:kernel_end
	SET PC, kernel_end
	
:api_padding
.dat "                                                                                                                                "
.dat "                                                                                                                                "
.dat "                                                                                                                                "
.dat "                                                                                                                                "
.dat "                                                                                                                                "
.dat "                                                                                                                                "
.dat "                                                                                                                                "
.dat "                                                                                                                                "
.dat "                                                                                                                                "
.dat "                                                                                                                                "
.dat "                                                                                                                                "
.dat "                                                                                                                                "
.dat "                                                                                                                                "
.dat "                                                                                                                                "
.dat "                                                                                                                                "
:api_padding_end
	
; Apps
:os_content
#include "../apps/AtlasShell.dasm16"
#include "../apps/AtlasText.dasm16"
#include "../apps/apps.dasm16"

; Virtual Filesystem
#include "../misc/vfs.dasm16"
:os_content_end

''';

class Location {
  Location(this.sourceFile, this.buffer, this.start, this.end);

  Location.fromToken(MyToken token)
      : sourceFile = token.fileName,
        buffer = token.buffer,
        start = token.start,
        end = token.stop;

  Location.coverLocations(Iterable<Location> locations)
      : assert(locations.isNotEmpty),
        assert(
          locations.skip(1).every(
                (token) => token.buffer == locations.first.buffer && token.sourceFile == locations.first.sourceFile,
              ),
        ),
        sourceFile = locations.first.sourceFile,
        buffer = locations.first.buffer,
        start = locations.map((token) => token.start).reduce(min),
        end = locations.map((token) => token.end).reduce(max);

  Location.coverTokens(Iterable<MyToken> tokens)
      : assert(tokens.isNotEmpty),
        assert(
          tokens
              .skip(1)
              .every((token) => token.buffer == tokens.first.buffer && token.fileName == tokens.first.fileName),
        ),
        sourceFile = tokens.first.fileName,
        buffer = tokens.first.buffer,
        start = tokens.map((token) => token.start).reduce(min),
        end = tokens.map((token) => token.stop).reduce(max);

  final String sourceFile;
  final String buffer;
  final int start;
  final int end;
  late final String text = buffer.substring(start, end);

  static (int, int) lineAndColumnOf(String buffer, int position) {
    final [first, second] = MyToken.lineAndColumnOf(buffer, position);
    return (first, second);
  }

  static String positionString(String buffer, int position) {
    final (line, column) = lineAndColumnOf(buffer, position);
    return '$line:$column';
  }

  @override
  String toString() => '$sourceFile:${positionString(buffer, start)}';
}

class SemanticException implements Exception {
  SemanticException(this.subject, this.message);

  final Location subject;
  final String message;

  @override
  String toString() {
    return '$subject: Semantic Error: $message: \'${subject.text}\'';
  }
}

class SyntaxError implements Exception {
  SyntaxError(this.subject, this.message);

  final Location subject;
  final String message;

  @override
  String toString() {
    return '$subject: Syntax error: $message: \'${subject.text}\'';
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
    return symbolDependencies.where((symbol) => context.symbolDefined(symbol));
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

  Assembled<T> assembledWithDeps(AssemblyContext context, Iterable<Assembled<D>> resolvedDeps);

  @override
  Assembled<T> assemble(AssemblyContext context) {
    final resolved = dependencies.map((dep) {
      return switch (dep) {
        Unassembled<D>() => dep.assemble(context),
        Assembled<D> dep => dep,
      };
    }).toList();

    return assembledWithDeps(context, resolved);
  }
}

class UnassembledSymbol extends Unassembled<int> {
  const UnassembledSymbol(this.name);

  final String name;

  @override
  int get substitute => 0;

  @override
  Iterable<String> get symbolDependencies => [name];

  @override
  bool canAssemble(AssemblyContext context) {
    return context.lookupSymbol(name) != null;
  }

  @override
  Assembled<int> assemble(AssemblyContext context) {
    return Assembled(context.lookupSymbol(name)!, [name]);
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

  int evaluateTerm(Term ast, AssemblyContext context) {
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
  Assembled<dcpu.IndirectRegisterImmediateArg> assembledWithDeps(
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
  Assembled<dcpu.ImmediateArg> assembledWithDeps(
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
  Assembled<dcpu.IndirectImmediateArg> assembledWithDeps(
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
  Assembled<dcpu.Instruction> assembledWithDeps(AssemblyContext context, Iterable<Assembled<dcpu.Arg>> resolvedDeps) {
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
  Assembled<dcpu.Instruction> assembledWithDeps(AssemblyContext context, Iterable<Assembled<dcpu.Arg>> resolvedDeps) {
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
  Assembled<Iterable<int>> assembledWithDeps(
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
    orElse: () => throw SemanticException(
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
      throw SemanticException(
        arg.location,
        'Direct Register + Immediate arguments are not supported by DCPU-16.',
      );

    case IndirectArg(child: RegisterOffsetArg(:final register, :final offsetOp, :final offset)):
      final summand = switch (offsetOp.value) {
        BinOp.add => offset,
        BinOp.sub => Term.unaryOp(
            MyToken(
              UnaryOp.minus,
              offsetOp.buffer,
              offsetOp.stop,
              offsetOp.stop,
              fileName: offsetOp.fileName,
            ),
            offset,
          ),
        _ => throw SemanticException(
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
      throw SemanticException(
        location,
        'SP++ is only supported in indirect addressing ([SP++])',
      );

    case IndirectArg(child: SpPlusPlusArg(), :final location):
      return switch (isA) {
        true => const Assembled(dcpu.PushPopArg()),
        false => throw SemanticException(
            location,
            'POP / [SP++] arg is not supported in B.',
          )
      };

    case PopArg(:final location):
      return switch (isA) {
        true => const Assembled(dcpu.PushPopArg()),
        false => throw SemanticException(
            location,
            'POP / [SP++] arg is not supported in B.',
          )
      };

    case IndirectArg(child: PopArg(:final location)):
      throw SemanticException(
        location,
        'POP is only supported with direct addressing.',
      );

    case MinusMinusSpArg(:final location):
      throw SemanticException(
        location,
        '--SP is only supported in indirect addressing ([--SP])',
      );

    case IndirectArg(child: MinusMinusSpArg(:final location)):
      return switch (isA) {
        true => throw SemanticException(
            location,
            'PUSH / [--SP] arg not supported in A.',
          ),
        false => const Assembled(dcpu.PushPopArg()),
      };

    case PushArg(:final location):
      return switch (isA) {
        true => throw SemanticException(
            location,
            'PUSH / [--SP] arg not supported in A.',
          ),
        false => const Assembled(dcpu.PushPopArg()),
      };

    case IndirectArg(child: PushArg(:final location)):
      throw SemanticException(
        location,
        'PUSH / [--SP] is only supported with direct addressing.',
      );

    case PeekArg():
      return const Assembled(
        dcpu.IndirectRegisterArg(Register.sp),
      );

    case IndirectArg(child: PeekArg(:final location)):
      throw SemanticException(
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
      throw SemanticException(
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
      throw SemanticException(
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
    orElse: () => throw SemanticException(
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
    (dcpu.BasicOp(), null, _) => throw SemanticException(
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
    (dcpu.SpecialOp(), _, _) => throw SemanticException(
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

class Assembler {
  final logger = Logger.root;

  final parser = Dasm16ParserDefinition().buildFrom(Dasm16ParserDefinition().start());

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
      Unassembled<int> unassembled => throw SemanticException(
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
                _ => throw SemanticException(
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
                _ => throw SemanticException(
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
                _ => throw SemanticException(
                    node.location,
                    '.reserve directive expects exactly one name/literal/term argument',
                  )
              };

              logger.info('ORG += ${hexstring(value)}');
              writer.reserve(value);

            case 'include':
              final path = switch (args) {
                [PackedString(flags: [], orValue: null, string: MyToken<String>(value: final path))] => path,
                _ => throw SemanticException(
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
                      _ => throw SemanticException(
                          name.location,
                          '.$directiveName expects an identifier as it\'s first argument',
                        ),
                    },
                    switch (value) {
                      NameOrTerm(term: final Term term) => evaluateTerm(term, context: context),
                      _ => throw SemanticException(
                          value.location,
                          '.$directiveName expects an identifier/number/term as it\'s second argument',
                        ),
                    }
                  ),
                _ => throw SemanticException(
                    node.location,
                    '$directiveName expects exactly two arguments.',
                  ),
              };

              logger.info('LET CONST $name := $value');
              context.defineConstant(name, value);

            case 'undef':
              final name = switch (args) {
                [NameOrTerm(name: MyToken<String>(value: final name))] => name,
                _ => throw SemanticException(
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
              throw SemanticException(Location.fromToken(node.name), 'Unknown pseudo-instruction');
          }

        case MacroDefinition(name: MyToken<String>(value: final name)):
          logger.info('LET MACRO $name := $node');
          context.defineMacro(name, node);

        case MacroInvocation(name: MyToken<String>(value: final name), :final location):
          if (!context.macroDefined(name)) {
            throw SemanticException(location, 'Invocation of undefined macro $name');
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

void main(List<String> args) {
  final logger = Logger.root;
  logger.level = Level.FINE;

  logger.onRecord.forEach((record) {
    // ignore: avoid_print
    print(record);
  });

  final assembler = Assembler();

  final bytes = assembler.assemble(
    args.first,
    File(args.first),
    [Directory.current],
  );

  final output = File('a.out');
  output.writeAsBytesSync(bytes);
}
