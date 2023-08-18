import 'package:petitparser/petitparser.dart';
import 'package:dcpu_flutter/assembler/mypetitparser.dart';
import 'package:dcpu_flutter/core/cpu.dart' show Register;

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
