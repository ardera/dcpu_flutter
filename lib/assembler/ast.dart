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

class PseudoInstr extends TopLevelASTNode {
  const PseudoInstr(this.prefix, this.name, this.args);

  final MyToken<String>? prefix;
  final MyToken<String> name;
  final SeparatedList<PseudoInstrArg, MyToken<String>> args;

  @override
  Iterable<MyToken> get tokens => [
        if (prefix != null) prefix!,
        name,
        ...args.sequential.expand((element) {
          if (element case PseudoInstrArg()) {
            return element.tokens;
          } else if (element case MyToken<String>()) {
            return [element];
          } else {
            throw ArgumentError.value(element, 'element');
          }
        })
      ];

  @override
  String toString() => 'PseudoInstr(prefix: $prefix, name: $name, args: $args)';
}

sealed class PseudoInstrArg extends ASTNode {
  const PseudoInstrArg();

  factory PseudoInstrArg.nameOrTerm(MyToken<String>? name, Term? term) {
    return NameOrTerm(name, term);
  }

  factory PseudoInstrArg.string(List<MyToken<StringPackingFlag>> flags, MyToken<int>? orValue, MyToken<String> string) =
      PackedString;
}

class NameOrTerm extends PseudoInstrArg {
  NameOrTerm(this.name, this.term);

  final MyToken<String>? name;
  final Term? term;

  @override
  String toString() => 'NameOrTerm(name: $name, term: $term)';

  @override
  Iterable<MyToken> get tokens => term?.tokens ?? [name!];
}

enum StringPackingFlag {
  packed,
  swapped,
  zeroZerminate,
  wordZeroTerminate,
  octetPascalLength,
  wordPascalLength,
}

class PackedString extends PseudoInstrArg {
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
  String toString() => 'PackedString(flags: $flags, orValue: $orValue, string: $string)';

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

class MacroInvocation extends ASTNode {
  const MacroInvocation(this.name);

  final MyToken<String> name;

  @override
  Iterable<MyToken> get tokens => [name];
}

class InstrOrMacroOrPseudoInstr extends TopLevelASTNode {
  const InstrOrMacroOrPseudoInstr(this.instruction, this.macroInvocation, this.pseudoInstruction);

  final Instruction? instruction;
  final MacroInvocation? macroInvocation;
  final PseudoInstr? pseudoInstruction;

  @override
  Iterable<MyToken> get tokens => instruction?.tokens ?? macroInvocation?.tokens ?? pseudoInstruction!.tokens;
}

class LabelDeclaration extends TopLevelASTNode {
  const LabelDeclaration(this.labelSign, this.name);

  final MyToken<String> labelSign;
  final MyToken<String> name;

  @override
  Iterable<MyToken> get tokens => [labelSign, name];

  @override
  String toString() => 'LabelDeclaration(labelSign: $labelSign, name: $name)';
}

class Instruction extends ASTNode {
  const Instruction({
    required this.mnemonic,
    required this.b,
    required this.a,
  });

  final MyToken<String> mnemonic;

  final InstructionArg? b;
  final InstructionArg a;

  @override
  Iterable<MyToken> get tokens => [
        mnemonic,
        if (b != null) ...b!.tokens,
        ...a.tokens,
      ];

  @override
  String toString() => 'Instruction(mnemonic: $mnemonic, b: $b, a: $a)';
}

sealed class InstructionArg extends ASTNode {
  const InstructionArg();

  const factory InstructionArg.indirect(
      MyToken<String> openBracket, InstructionArg inner, MyToken<String> closeBracket) = IndirectArg;

  const factory InstructionArg.register(MyToken<Register> register) = RegisterArg;

  const factory InstructionArg.registerOffset(MyToken<Register> register, MyToken<BinOp> op, Term offset) =
      RegisterOffset;

  const factory InstructionArg.push(MyToken<String> token) = Push;

  const factory InstructionArg.spPlusPlus(MyToken<String> sp, MyToken<String> plusPlus) = SpPlusPlus;

  const factory InstructionArg.pop(MyToken<String> token) = Pop;

  const factory InstructionArg.minusMinusSp(MyToken<String> minusMinus, MyToken<String> sp) = MinusMinusSp;

  const factory InstructionArg.peek(MyToken<String> token) = Peek;

  const factory InstructionArg.pick(MyToken<String> pick, Term offset) = Pick;
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

class RegisterOffset extends InstructionArg {
  const RegisterOffset(this.register, this.offsetOp, this.offset);

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
  String toString() => 'RegisterOffset(register: $register, offsetOp: $offsetOp, offset: $offset)';
}

class Push extends InstructionArg {
  const Push(this.token);

  final MyToken<String> token;

  @override
  get tokens => [token];

  @override
  String toString() => 'Push(token: $token)';
}

class SpPlusPlus extends InstructionArg {
  const SpPlusPlus(this.spToken, this.plusPlusToken);

  final MyToken<String> spToken;
  final MyToken<String> plusPlusToken;

  @override
  Iterable<MyToken> get tokens => [spToken, plusPlusToken];

  @override
  String toString() => 'SpPlusPlus(spToken: $spToken, plusPlusToken: $plusPlusToken)';
}

class Pop extends InstructionArg {
  const Pop(this.token);

  final MyToken<String> token;

  @override
  Iterable<MyToken> get tokens => [token];

  @override
  String toString() => 'Pop(token: $token)';
}

class MinusMinusSp extends InstructionArg {
  const MinusMinusSp(this.minusMinusToken, this.spToken);

  final MyToken<String> minusMinusToken;
  final MyToken<String> spToken;

  @override
  Iterable<MyToken> get tokens => [minusMinusToken, spToken];

  @override
  String toString() => 'MinusMinusSp(minusMinusToken: $minusMinusToken, spToken: $spToken)';
}

class Peek extends InstructionArg {
  const Peek(this.token);

  final MyToken<String> token;

  @override
  Iterable<MyToken> get tokens => [token];

  @override
  String toString() => 'Peek(token: $token)';
}

class Pick extends InstructionArg {
  const Pick(this.pickToken, this.offset);

  final MyToken<String> pickToken;
  final Term offset;

  @override
  Iterable<MyToken> get tokens => [pickToken, ...offset.tokens];

  @override
  String toString() => 'Pick(pickToken: $pickToken, offset: $offset)';
}

sealed class Term extends ASTNode implements InstructionArg {
  const Term();

  const factory Term.literal(MyToken<int> value) = Literal;
  const factory Term.label(MyToken<String> label) = LabelTerm;
  const factory Term.binOp(Term lhs, MyToken<BinOp> op, Term rhs) = BinaryOpTerm;
  const factory Term.unaryOp(MyToken<UnaryOp> op, Term a) = UnaryOpTerm;

  Iterable<String> get symbolDependencies;
}

class Literal extends Term {
  const Literal(this.value);

  final MyToken<int> value;

  @override
  Iterable<MyToken> get tokens => [value];

  @override
  Iterable<String> get symbolDependencies => [];

  @override
  String toString() => 'Literal(value: $value)';
}

class LabelTerm extends Term {
  const LabelTerm(this.label);

  final MyToken<String> label;

  @override
  Iterable<MyToken> get tokens => [label];

  @override
  Iterable<String> get symbolDependencies => [label.value];

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
  String toString() => 'BinaryOpTerm(op: $op, a: $lhs, b: $rhs)';
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
