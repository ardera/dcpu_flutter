import 'package:dcpu_flutter/core/cpu.dart';
import 'package:dcpu_flutter/core/math.dart';

abstract class Instruction {
  const Instruction({required this.op});

  static Instruction decode(int Function() readWord) {
    final firstWord = readWord();

    final opcode = firstWord & 0x1f;
    final bEncoded = (firstWord >> 5) & 0x1f;
    final aEncoded = (firstWord >> 10) & 0x3f;

    if (opcode == 0) {
      // special opcode
      final op = Op.decodeSpecial(bEncoded);
      final a = Arg.decode(aEncoded, readWord);
      return SpecialInstruction(op: op, a: a);
    } else {
      // basic opcode
      final op = Op.decodeBasic(opcode);
      final a = Arg.decode(aEncoded, readWord);
      final b = Arg.decode(bEncoded, readWord);
      return BasicInstruction(op: op, a: a, b: b);
    }
  }

  final Op op;

  int get decodeCycleCount;
  int get cycles;

  void perform(Dcpu state);

  String disassemble();
}

class BasicInstruction implements Instruction {
  BasicInstruction({required this.op, required this.a, required this.b});

  @override
  final BasicOp op;

  final Arg a;
  final Arg b;

  @override
  int get decodeCycleCount => a.decodeCycleCount + b.decodeCycleCount;

  @override
  int get cycles => op.cycles;

  @override
  void perform(Dcpu state) {
    op.perform(state, a, b);
  }

  @override
  String disassemble() {
    return '${op.mnemonic} ${b.disassemble(false)}, ${a.disassemble(true)}';
  }
}

class SpecialInstruction implements Instruction {
  SpecialInstruction({required this.op, required this.a});

  @override
  final SpecialOp op;

  final Arg a;

  @override
  int get decodeCycleCount => a.decodeCycleCount;

  @override
  int get cycles => op.cycles;

  @override
  void perform(Dcpu state) {
    op.perform(state, a);
  }

  @override
  String disassemble() {
    return '${op.mnemonic} ${a.disassemble(true)}';
  }
}

class DecoderException implements Exception {}

class IllegalOpcodeException implements DecoderException {
  final int opcode;
  final bool special;

  const IllegalOpcodeException(this.opcode, {required this.special});
}

class IllegalBasicOpcodeException extends IllegalOpcodeException {
  IllegalBasicOpcodeException(super.opcode) : super(special: false);

  @override
  String toString() {
    return 'Illegal basic opcode: 0x${opcode.toRadixString(16).padLeft(2, '0')}';
  }
}

class IllegalSpecialOpcodeException extends IllegalOpcodeException {
  IllegalSpecialOpcodeException(super.opcode) : super(special: true);

  @override
  String toString() {
    return 'Illegal special opcode: 0x${opcode.toRadixString(16).padLeft(2, '0')}';
  }
}

class IllegalArgumentEncodingException extends DecoderException {
  final int encoding;

  IllegalArgumentEncodingException(this.encoding);

  @override
  String toString() {
    return 'Illegal argument encoding: 0x${encoding.toRadixString(16).padLeft(2, '0')}';
  }
}

abstract class Op {
  String get mnemonic;

  const Op();

  static BasicOp decodeBasic(int opcode) {
    if (SetOp.matches(opcode, false)) {
      return const SetOp();
    } else if (AddOp.matches(opcode, false)) {
      return const AddOp();
    } else if (SubOp.matches(opcode, false)) {
      return const SubOp();
    } else if (MulOp.matches(opcode, false)) {
      return const MulOp();
    } else if (MliOp.matches(opcode, false)) {
      return const MliOp();
    } else if (DivOp.matches(opcode, false)) {
      return const DivOp();
    } else if (DviOp.matches(opcode, false)) {
      return const DviOp();
    } else if (ModOp.matches(opcode, false)) {
      return const ModOp();
    } else if (MdiOp.matches(opcode, false)) {
      return const MdiOp();
    } else if (AndOp.matches(opcode, false)) {
      return const AndOp();
    } else if (BorOp.matches(opcode, false)) {
      return const BorOp();
    } else if (XorOp.matches(opcode, false)) {
      return const XorOp();
    } else if (ShrOp.matches(opcode, false)) {
      return const ShrOp();
    } else if (AsrOp.matches(opcode, false)) {
      return const AsrOp();
    } else if (ShlOp.matches(opcode, false)) {
      return const ShlOp();
    } else if (IfbOp.matches(opcode, false)) {
      return const IfbOp();
    } else if (IfcOp.matches(opcode, false)) {
      return const IfcOp();
    } else if (IfeOp.matches(opcode, false)) {
      return const IfeOp();
    } else if (IfnOp.matches(opcode, false)) {
      return const IfnOp();
    } else if (IfgOp.matches(opcode, false)) {
      return const IfgOp();
    } else if (IfaOp.matches(opcode, false)) {
      return const IfaOp();
    } else if (IflOp.matches(opcode, false)) {
      return const IflOp();
    } else if (IfuOp.matches(opcode, false)) {
      return const IfuOp();
    } else if (AdxOp.matches(opcode, false)) {
      return const AdxOp();
    } else if (SbxOp.matches(opcode, false)) {
      return const SbxOp();
    } else if (StiOp.matches(opcode, false)) {
      return const StiOp();
    } else if (StdOp.matches(opcode, false)) {
      return const StdOp();
    } else {
      throw IllegalBasicOpcodeException(opcode);
    }
  }

  static SpecialOp decodeSpecial(int opcode) {
    if (JsrOp.matches(opcode, true)) {
      return const JsrOp();
    } else if (IntOp.matches(opcode, true)) {
      return const IntOp();
    } else if (IagOp.matches(opcode, true)) {
      return const IagOp();
    } else if (IasOp.matches(opcode, true)) {
      return const IasOp();
    } else if (RfiOp.matches(opcode, true)) {
      return const RfiOp();
    } else if (IaqOp.matches(opcode, true)) {
      return const IaqOp();
    } else if (HwnOp.matches(opcode, true)) {
      return const HwnOp();
    } else if (HwqOp.matches(opcode, true)) {
      return const HwqOp();
    } else if (HwiOp.matches(opcode, true)) {
      return const HwiOp();
    } else {
      throw IllegalSpecialOpcodeException(opcode);
    }
  }

  int get cycles;

  bool get skipAgain => false;

  void readAWriteB(
    Dcpu state,
    Arg a,
    Arg b, {
    required int Function(int a) compute,
  }) {
    final aCaptured = a.read(state);

    final result = compute(aCaptured);

    b.write(state, result);
  }

  void readBreadAwriteB(
    Dcpu state,
    Arg a,
    Arg b, {
    required int Function(int a, int b) compute,
  }) {
    final bCaptured = b.read(state);
    final aCaptured = a.read(state);

    final result = compute(aCaptured, bCaptured);

    b.write(state, result);
  }

  void readBreadAwriteBwriteEx(
    Dcpu state,
    Arg a,
    Arg b, {
    required ({int b, int ex}) Function(int a, int b) compute,
  }) {
    final bCaptured = b.read(state);
    final aCaptured = a.read(state);

    final result = compute(aCaptured, bCaptured);

    b.write(state, result.b);
    state.regs.ex = result.ex;
  }

  void readBreadA(
    Dcpu state,
    Arg a,
    Arg b, {
    required void Function(int a, int b) compute,
  }) {
    final bCaptured = b.read(state);
    final aCaptured = a.read(state);

    compute(aCaptured, bCaptured);
  }

  void readBreadAwriteSkip(
    Dcpu state,
    Arg a,
    Arg b, {
    required bool Function(int a, int b) compute,
  }) {
    final bCaptured = b.read(state);
    final aCaptured = a.read(state);

    final skip = compute(aCaptured, bCaptured);

    state.skip = skip;
  }

  void readBreadAreadExwriteBwriteEx(
    Dcpu state,
    Arg a,
    Arg b, {
    required ({int b, int ex}) Function(int a, int b, int ex) compute,
  }) {
    final bCaptured = b.read(state);
    final aCaptured = a.read(state);
    final exCaptured = state.regs.ex;

    final result = compute(aCaptured, bCaptured, exCaptured);

    b.write(state, result.b);
    state.regs.ex = result.ex;
  }
}

abstract class BasicOp extends Op {
  const BasicOp();

  void perform(Dcpu state, Arg a, Arg b);
}

abstract class BranchingOp extends BasicOp {
  const BranchingOp();

  @override
  bool get skipAgain => true;
}

abstract class SpecialOp extends Op {
  const SpecialOp();

  void perform(Dcpu state, Arg a);
}

class SetOp extends BasicOp {
  static bool matches(int opcode, bool special) => !special && opcode == 0x01;

  const SetOp();

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readAWriteB(state, a, b, compute: (a) => a);
  }

  @override
  String get mnemonic => 'SET';

  @override
  int get cycles => 1;
}

class AddOp extends BasicOp {
  static bool matches(int opcode, bool special) => !special && opcode == 0x02;

  const AddOp();

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteBwriteEx(
      state,
      a,
      b,
      compute: (a, b) {
        return (
          b: add16bit(a, b),
          ex: add16bitOverflows(a, b) ? 1 : 0,
        );
      },
    );
  }

  @override
  String get mnemonic => 'ADD';

  @override
  int get cycles => 2;
}

class SubOp extends BasicOp {
  static bool matches(int opcode, bool special) => !special && opcode == 0x03;

  const SubOp();

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteBwriteEx(
      state,
      a,
      b,
      compute: (a, b) {
        return (
          b: sub16bit(b, a),
          ex: sub16bitUnderflows(b, a) ? 0xFFFF : 0,
        );
      },
    );
  }

  @override
  String get mnemonic => 'SUB';

  @override
  int get cycles => 2;
}

class MulOp extends BasicOp {
  static bool matches(int opcode, bool special) => !special && opcode == 0x04;

  const MulOp();

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteBwriteEx(
      state,
      a,
      b,
      compute: (a, b) {
        final multiplied = a * b;
        return (
          b: to16bit(multiplied),
          ex: to16bit(multiplied >> 16),
        );
      },
    );
  }

  @override
  String get mnemonic => 'MUL';

  @override
  int get cycles => 2;
}

class MliOp extends BasicOp {
  static bool matches(int opcode, bool special) => !special && opcode == 0x05;

  const MliOp();

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteBwriteEx(
      state,
      a,
      b,
      compute: (a, b) {
        a = from16bitsigned(a);
        b = from16bitsigned(b);

        final multiplied = b * a;

        return (
          b: to16bit(multiplied & 0xffff),
          ex: to16bit(multiplied >> 16),
        );
      },
    );
  }

  @override
  String get mnemonic => 'MLI';

  @override
  int get cycles => 2;
}

class DivOp extends BasicOp {
  static bool matches(int opcode, bool special) => !special && opcode == 0x06;

  const DivOp();

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteBwriteEx(
      state,
      a,
      b,
      compute: (a, b) {
        if (a == 0) {
          return const (b: 0, ex: 0);
        } else {
          return (
            b: to16bit(b ~/ a),
            ex: to16bit((b << 16) ~/ a),
          );
        }
      },
    );
  }

  @override
  String get mnemonic => 'DIV';

  @override
  int get cycles => 3;
}

class DviOp extends BasicOp {
  static bool matches(int opcode, bool special) => !special && opcode == 0x07;

  const DviOp();

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteBwriteEx(
      state,
      a,
      b,
      compute: (a, b) {
        if (a == 0) {
          return const (b: 0, ex: 0);
        } else {
          a = from16bitsigned(a);
          b = from16bitsigned(b);

          return (
            b: to16bit(b ~/ a),
            ex: to16bit((b << 16) ~/ a),
          );
        }
      },
    );
  }

  @override
  String get mnemonic => 'DVI';

  @override
  int get cycles => 3;
}

class ModOp extends BasicOp {
  static bool matches(int opcode, bool special) => !special && opcode == 0x08;

  const ModOp();

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteB(
      state,
      a,
      b,
      compute: (a, b) {
        if (a == 0) {
          return 0;
        } else {
          return b % a;
        }
      },
    );
  }

  @override
  String get mnemonic => 'MOD';

  @override
  int get cycles => 3;
}

class MdiOp extends BasicOp {
  static bool matches(int opcode, bool special) => !special && opcode == 0x09;

  const MdiOp();

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteB(
      state,
      a,
      b,
      compute: (a, b) {
        if (a == 0) {
          return 0;
        } else {
          a = from16bitsigned(a);
          b = from16bitsigned(b);

          return to16bit(b % a);
        }
      },
    );
  }

  @override
  String get mnemonic => 'MDI';

  @override
  int get cycles => 3;
}

class AndOp extends BasicOp {
  static bool matches(int opcode, bool special) => !special && opcode == 0x0a;

  const AndOp();

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteB(
      state,
      a,
      b,
      compute: (a, b) {
        return b & a;
      },
    );
  }

  @override
  String get mnemonic => 'AND';

  @override
  int get cycles => 1;
}

class BorOp extends BasicOp {
  static bool matches(int opcode, bool special) => !special && opcode == 0x0b;

  const BorOp();

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteB(
      state,
      a,
      b,
      compute: (a, b) {
        return b | a;
      },
    );
  }

  @override
  String get mnemonic => 'BOR';

  @override
  int get cycles => 1;
}

class XorOp extends BasicOp {
  static bool matches(int opcode, bool special) => !special && opcode == 0x0c;

  const XorOp();

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteB(
      state,
      a,
      b,
      compute: (a, b) {
        return b ^ a;
      },
    );
  }

  @override
  String get mnemonic => 'XOR';

  @override
  int get cycles => 1;
}

class ShrOp extends BasicOp {
  static bool matches(int opcode, bool special) => !special && opcode == 0x0d;

  const ShrOp();

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteBwriteEx(
      state,
      a,
      b,
      compute: (a, b) {
        return (
          b: to16bit(b >>> a),
          ex: to16bit((b << 16) >> a),
        );
      },
    );
  }

  @override
  String get mnemonic => 'SHR';

  @override
  int get cycles => 1;
}

class AsrOp extends BasicOp {
  static bool matches(int opcode, bool special) => !special && opcode == 0x0e;

  const AsrOp();

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteBwriteEx(
      state,
      a,
      b,
      compute: (a, b) {
        b = from16bitsigned(b);

        return (
          b: to16bit(b >> a),
          ex: to16bit((b << 16) >>> a),
        );
      },
    );
  }

  @override
  String get mnemonic => 'ASR';

  @override
  int get cycles => 1;
}

class ShlOp extends BasicOp {
  static bool matches(int opcode, bool special) => !special && opcode == 0x0f;

  const ShlOp();

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteBwriteEx(
      state,
      a,
      b,
      compute: (a, b) {
        return (
          b: to16bit(b << a),
          ex: to16bit((b << a) >> 16),
        );
      },
    );
  }

  @override
  String get mnemonic => 'SHL';

  @override
  int get cycles => 1;
}

class IfbOp extends BranchingOp {
  static bool matches(int opcode, bool special) => !special && opcode == 0x10;

  const IfbOp();

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteSkip(
      state,
      a,
      b,
      compute: (a, b) {
        return !(b & a != 0);
      },
    );
  }

  @override
  String get mnemonic => 'IFB';

  @override
  int get cycles => 2;
}

class IfcOp extends BranchingOp {
  static bool matches(int opcode, bool special) => !special && opcode == 0x11;

  const IfcOp();

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteSkip(
      state,
      a,
      b,
      compute: (a, b) {
        return !(b & a == 0);
      },
    );
  }

  @override
  String get mnemonic => 'IFC';

  @override
  int get cycles => 2;
}

class IfeOp extends BranchingOp {
  const IfeOp();

  static bool matches(int opcode, bool special) => !special && opcode == 0x12;

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteSkip(
      state,
      a,
      b,
      compute: (a, b) {
        return !(b == a);
      },
    );
  }

  @override
  String get mnemonic => 'IFE';

  @override
  int get cycles => 2;
}

class IfnOp extends BranchingOp {
  const IfnOp();

  static bool matches(int opcode, bool special) => !special && opcode == 0x13;

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteSkip(
      state,
      a,
      b,
      compute: (a, b) {
        return !(b != a);
      },
    );
  }

  @override
  String get mnemonic => 'IFN';

  @override
  int get cycles => 2;
}

class IfgOp extends BranchingOp {
  const IfgOp();

  static bool matches(int opcode, bool special) => !special && opcode == 0x14;

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteSkip(
      state,
      a,
      b,
      compute: (a, b) {
        return !(b > a);
      },
    );
  }

  @override
  String get mnemonic => 'IFG';

  @override
  int get cycles => 2;
}

class IfaOp extends BranchingOp {
  const IfaOp();

  static bool matches(int opcode, bool special) => !special && opcode == 0x15;

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteSkip(
      state,
      a,
      b,
      compute: (a, b) {
        a = from16bitsigned(a);
        b = from16bitsigned(b);

        return !(b > a);
      },
    );
  }

  @override
  String get mnemonic => 'IFA';

  @override
  int get cycles => 2;
}

class IflOp extends BranchingOp {
  const IflOp();

  static bool matches(int opcode, bool special) => !special && opcode == 0x16;

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteSkip(
      state,
      a,
      b,
      compute: (a, b) {
        return !(b < a);
      },
    );
  }

  @override
  String get mnemonic => 'IFL';

  @override
  int get cycles => 2;
}

class IfuOp extends BranchingOp {
  const IfuOp();

  static bool matches(int opcode, bool special) => !special && opcode == 0x17;

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAwriteSkip(
      state,
      a,
      b,
      compute: (a, b) {
        a = from16bitsigned(a);
        b = from16bitsigned(b);

        return !(b < a);
      },
    );
  }

  @override
  String get mnemonic => 'IFU';

  @override
  int get cycles => 2;
}

class AdxOp extends BasicOp {
  const AdxOp();

  static bool matches(int opcode, bool special) => !special && opcode == 0x1a;

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAreadExwriteBwriteEx(
      state,
      a,
      b,
      compute: (a, b, ex) {
        final sum = a + b + ex;
        return (
          b: to16bit(sum),
          ex: sum > 0xFFFF ? 1 : 0,
        );
      },
    );
  }

  @override
  String get mnemonic => 'ADX';

  @override
  int get cycles => 3;
}

class SbxOp extends BasicOp {
  const SbxOp();

  static bool matches(int opcode, bool special) => !special && opcode == 0x1b;

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readBreadAreadExwriteBwriteEx(
      state,
      a,
      b,
      compute: (a, b, ex) {
        final sum = a - b + ex;
        return (
          b: to16bit(sum),
          ex: sum < 0 ? 0xFFFF : 0,
        );
      },
    );
  }

  @override
  String get mnemonic => 'SBX';

  @override
  int get cycles => 3;
}

class StiOp extends BasicOp {
  const StiOp();

  static bool matches(int opcode, bool special) => !special && opcode == 0x1e;

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readAWriteB(state, a, b, compute: (a) => a);
    state.regs.i = add16bit(state.regs.i, 1);
    state.regs.j = add16bit(state.regs.j, 1);
  }

  @override
  String get mnemonic => 'STI';

  @override
  int get cycles => 2;
}

class StdOp extends BasicOp {
  const StdOp();

  static bool matches(int opcode, bool special) => !special && opcode == 0x1f;

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readAWriteB(state, a, b, compute: (a) => a);
    state.regs.i = sub16bit(state.regs.i, 1);
    state.regs.j = sub16bit(state.regs.j, 1);
  }

  @override
  String get mnemonic => 'STD';

  @override
  int get cycles => 2;
}

class JsrOp extends SpecialOp {
  const JsrOp();

  static bool matches(int opcode, bool special) => special && opcode == 0x01;

  @override
  void perform(Dcpu state, Arg a) {
    state.pushStack(state.regs.pc);
    state.regs.pc = a.read(state);
  }

  @override
  String get mnemonic => 'JSR';

  @override
  int get cycles => 3;
}

class IntOp extends SpecialOp {
  const IntOp();

  static bool matches(int opcode, bool special) => special && opcode == 0x08;

  @override
  void perform(Dcpu state, Arg a) {
    final aCaptured = a.read(state);

    state.interruptController.request(aCaptured);
  }

  @override
  String get mnemonic => 'INT';

  @override
  int get cycles => 4;
}

class IagOp extends SpecialOp {
  const IagOp();

  static bool matches(int opcode, bool special) => special && opcode == 0x09;

  @override
  void perform(Dcpu state, Arg a) {
    a.write(state, state.regs.ia);
  }

  @override
  String get mnemonic => 'IAG';

  @override
  int get cycles => 1;
}

class IasOp extends SpecialOp {
  const IasOp();

  static bool matches(int opcode, bool special) => special && opcode == 0x0a;

  @override
  void perform(Dcpu state, Arg a) {
    final aCaptured = a.read(state);

    state.regs.ia = aCaptured;

    if (aCaptured == 0) {
      state.interruptController.disable();
    } else {
      state.interruptController.enable();
    }
  }

  @override
  String get mnemonic => 'IAS';

  @override
  int get cycles => 1;
}

class RfiOp extends SpecialOp {
  const RfiOp();

  static bool matches(int opcode, bool special) => special && opcode == 0x0b;

  @override
  void perform(Dcpu state, Arg a) {
    state.interruptController.disableQueueing();
    state.regs.a = state.popStack();
    state.regs.pc = state.popStack();
  }

  @override
  String get mnemonic => 'RFI';

  @override
  int get cycles => 3;
}

class IaqOp extends SpecialOp {
  const IaqOp();

  static bool matches(int opcode, bool special) => special && opcode == 0x0c;

  @override
  void perform(Dcpu state, Arg a) {
    final aCaptured = a.read(state);

    if (aCaptured == 0) {
      state.interruptController.enableQueueing();
    } else {
      state.interruptController.disableQueueing();
    }
  }

  @override
  String get mnemonic => 'IAQ';

  @override
  int get cycles => 2;
}

class HwnOp extends SpecialOp {
  const HwnOp();

  static bool matches(int opcode, bool special) => special && opcode == 0x10;

  @override
  void perform(Dcpu state, Arg a) {
    a.write(state, state.hardwareController.getCountDevices());
  }

  @override
  String get mnemonic => 'HWN';

  @override
  int get cycles => 2;
}

class HwqOp extends SpecialOp {
  const HwqOp();

  static bool matches(int opcode, bool special) => special && opcode == 0x11;

  @override
  void perform(Dcpu state, Arg a) {
    final aCaptured = a.read(state);

    if (state.hardwareController.hasDeviceWithNumber(aCaptured)) {
      final info = state.hardwareController.getHardwareInfo(aCaptured);

      state.regs.a = info.hardwareId & 0xFFFF;
      state.regs.b = info.hardwareId >> 16;
      state.regs.c = info.version;
      state.regs.x = info.manufacturerId & 0xFFFF;
      state.regs.y = info.manufacturerId >> 16;
    } else {
      state.regs.a = 0;
      state.regs.b = 0;
      state.regs.c = 0;
      state.regs.x = 0;
      state.regs.y = 0;
    }
  }

  @override
  String get mnemonic => 'HWQ';

  @override
  int get cycles => 4;
}

class HwiOp extends SpecialOp {
  const HwiOp();

  static bool matches(int opcode, bool special) => special && opcode == 0x12;

  @override
  void perform(Dcpu state, Arg a) {
    final aCaptured = a.read(state);

    if (state.hardwareController.hasDeviceWithNumber(aCaptured)) {
      state.hardwareController.requestInterrupt(state, aCaptured);
    }
  }

  @override
  String get mnemonic => 'HWI';

  @override
  int get cycles => 4;
}

abstract class Arg {
  const Arg(this.encoded);

  static Arg decode(int encoded, int Function() readNextWord) {
    if (DirectRegisterArg.matches(encoded)) {
      return DirectRegisterArg(encoded);
    } else if (IndirectRegisterArg.matches(encoded)) {
      return IndirectRegisterArg(encoded);
    } else if (IndirectImmediateRegisterArg.matches(encoded)) {
      return IndirectImmediateRegisterArg(encoded, readNextWord());
    } else if (PushPopArg.matches(encoded)) {
      return const PushPopArg();
    } else if (PeekArg.matches(encoded)) {
      return const PeekArg();
    } else if (SpecialRegisterArg.matches(encoded)) {
      return SpecialRegisterArg(encoded);
    } else if (IndirectImmediateArg.matches(encoded)) {
      return IndirectImmediateArg(encoded, readNextWord());
    } else if (ImmediateArg.matches(encoded)) {
      return ImmediateArg(encoded, readNextWord());
    } else if (SmallImmediateArg.matches(encoded)) {
      return SmallImmediateArg(encoded);
    } else {
      throw IllegalArgumentEncodingException(encoded);
    }
  }

  final int encoded;

  int get decodeCycleCount => 0;

  int read(Dcpu state);
  void write(Dcpu state, int value);

  String disassemble(bool isA);
}

class DirectRegisterArg extends Arg {
  const DirectRegisterArg.fromEncoded(super.encoded)
      : assert(0 <= encoded && encoded <= 0x07),
        registerIndex = encoded,
        super();

  factory DirectRegisterArg(int encoded) {
    assert(0 <= encoded && encoded <= 0x07);
    switch (encoded) {
      case 0:
        return const DirectRegisterArg.fromEncoded(0);
      case 1:
        return const DirectRegisterArg.fromEncoded(1);
      case 2:
        return const DirectRegisterArg.fromEncoded(2);
      case 3:
        return const DirectRegisterArg.fromEncoded(3);
      case 4:
        return const DirectRegisterArg.fromEncoded(4);
      case 5:
        return const DirectRegisterArg.fromEncoded(5);
      case 6:
        return const DirectRegisterArg.fromEncoded(6);
      case 7:
        return const DirectRegisterArg.fromEncoded(7);
      default:
        throw StateError('Unreachable');
    }
  }

  final int registerIndex;

  static bool matches(int encoded) => 0 <= encoded && encoded <= 0x07;

  @override
  int read(Dcpu state) {
    return state.regs.readByIndex(encoded);
  }

  @override
  void write(Dcpu state, int value) {
    return state.regs.writeByIndex(encoded, value);
  }

  @override
  String disassemble(bool isA) {
    return RegisterFile.registerName(registerIndex);
  }
}

class IndirectRegisterArg extends Arg {
  const IndirectRegisterArg.fromEncoded(super.encoded)
      : assert(0x08 <= encoded && encoded <= 0x0f),
        registerIndex = encoded - 0x08,
        super();

  factory IndirectRegisterArg(int encoded) {
    assert(0x08 <= encoded && encoded <= 0x0f);
    switch (encoded) {
      case 0x08:
        return const IndirectRegisterArg.fromEncoded(0x08);
      case 0x09:
        return const IndirectRegisterArg.fromEncoded(0x09);
      case 0x0a:
        return const IndirectRegisterArg.fromEncoded(0x0a);
      case 0x0b:
        return const IndirectRegisterArg.fromEncoded(0x0b);
      case 0x0c:
        return const IndirectRegisterArg.fromEncoded(0x0c);
      case 0x0d:
        return const IndirectRegisterArg.fromEncoded(0x0d);
      case 0x0e:
        return const IndirectRegisterArg.fromEncoded(0x0e);
      case 0x0f:
        return const IndirectRegisterArg.fromEncoded(0x0f);
      default:
        throw StateError('');
    }
  }

  final int registerIndex;

  static bool matches(int encoded) => 0x08 <= encoded && encoded <= 0x0f;

  @override
  int read(Dcpu state) {
    return state.memory.read(state.regs.readByIndex(registerIndex));
  }

  @override
  void write(Dcpu state, int value) {
    return state.memory.write(state.regs.readByIndex(registerIndex), value);
  }

  @override
  String disassemble(bool isA) {
    return '[${RegisterFile.registerName(registerIndex)}]';
  }
}

class IndirectImmediateRegisterArg extends Arg {
  const IndirectImmediateRegisterArg(super.encoded, this.nextWord)
      : assert(0x10 <= encoded && encoded <= 0x17),
        registerIndex = encoded - 0x10,
        super();

  final int registerIndex;
  final int nextWord;

  static bool matches(int encoded) => 0x10 <= encoded && encoded <= 0x17;

  @override
  int get decodeCycleCount => 1;

  @override
  int read(Dcpu state) {
    final addr = add16bit(state.regs.readByIndex(registerIndex), nextWord);
    return state.memory.read(addr);
  }

  @override
  void write(Dcpu state, int value) {
    final addr = add16bit(state.regs.readByIndex(registerIndex), nextWord);
    return state.memory.write(addr, value);
  }

  @override
  String disassemble(bool isA) {
    final registerName = RegisterFile.registerName(registerIndex);
    return '[$registerName+$nextWord]';
  }
}

class PushPopArg extends Arg {
  const PushPopArg() : super(0x18);

  static bool matches(int encoded) => encoded == 0x18;

  @override
  int read(Dcpu state) {
    return state.popStack();
  }

  @override
  void write(Dcpu state, int value) {
    return state.pushStack(value);
  }

  @override
  String disassemble(bool isA) {
    if (isA) {
      return 'POP';
    } else {
      return 'PUSH';
    }
  }
}

class PeekArg extends Arg {
  const PeekArg() : super(0x19);

  static bool matches(int encoded) => encoded == 0x19;

  @override
  int read(Dcpu state) {
    return state.readPeek();
  }

  @override
  void write(Dcpu state, int value) {
    return state.writePeek(value);
  }

  @override
  String disassemble(bool isA) {
    return 'PEEK';
  }
}

class PickArg extends Arg {
  const PickArg(this.nextWord) : super(0x1a);

  final int nextWord;

  static bool matches(int encoded) => encoded == 0x1a;

  @override
  int get decodeCycleCount => 1;

  @override
  int read(Dcpu state) {
    return state.readPeek();
  }

  @override
  void write(Dcpu state, int value) {
    return state.writePeek(value);
  }

  @override
  String disassemble(bool isA) {
    return 'PICK $nextWord';
  }
}

class SpecialRegisterArg extends Arg {
  const SpecialRegisterArg.fromEncoded(super.encoded)
      : assert(0x1b <= encoded && encoded <= 0x1d),
        registerIndex = encoded - 0x1b + 8,
        super();

  factory SpecialRegisterArg(int encoded) {
    assert(matches(encoded));
    switch (encoded) {
      case 0x1b:
        return const SpecialRegisterArg.fromEncoded(0x1b);
      case 0x1c:
        return const SpecialRegisterArg.fromEncoded(0x1c);
      case 0x1d:
        return const SpecialRegisterArg.fromEncoded(0x1d);
      default:
        throw StateError('Unreachable');
    }
  }

  final int registerIndex;

  static bool matches(int encoded) => 0x1b <= encoded && encoded <= 0x1d;

  @override
  int read(Dcpu state) {
    return state.regs.readByIndex(registerIndex);
  }

  @override
  void write(Dcpu state, int value) {
    return state.regs.writeByIndex(registerIndex, value);
  }

  @override
  String disassemble(bool isA) {
    return RegisterFile.registerName(registerIndex);
  }
}

class IndirectImmediateArg extends Arg {
  IndirectImmediateArg(super.encoded, this.nextWord)
      : assert(matches(encoded)),
        super();

  final int nextWord;

  static bool matches(int encoded) => encoded == 0x1e;

  @override
  int get decodeCycleCount => 1;

  @override
  int read(Dcpu state) {
    final addr = nextWord;
    return state.memory.read(addr);
  }

  @override
  void write(Dcpu state, int value) {
    final addr = nextWord;
    return state.memory.write(addr, value);
  }

  @override
  String disassemble(bool isA) {
    return '[${hexstring(nextWord)}]';
  }
}

class ImmediateArg extends Arg {
  ImmediateArg(super.encoded, this.nextWord)
      : assert(matches(encoded)),
        super();

  final int nextWord;

  static bool matches(int encoded) => encoded == 0x1f;

  @override
  int get decodeCycleCount => 1;

  @override
  int read(Dcpu state) {
    return nextWord;
  }

  @override
  void write(Dcpu state, int value) {
    // this silently fails.
  }

  @override
  String disassemble(bool isA) {
    return hexstring(nextWord);
  }
}

class SmallImmediateArg extends Arg {
  SmallImmediateArg(super.encoded)
      : assert(matches(encoded)),
        immediate = to16bit(encoded - 0x21),
        super();

  final int immediate;

  static bool matches(int encoded) => 0x20 <= encoded && encoded <= 0x3f;

  @override
  int read(Dcpu state) {
    return immediate;
  }

  @override
  void write(Dcpu state, int value) {
    // this silently fails.
  }

  @override
  String disassemble(bool isA) {
    return '${encoded - 0x21}';
  }
}
