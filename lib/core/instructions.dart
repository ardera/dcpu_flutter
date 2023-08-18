import 'package:dcpu_flutter/core/cpu.dart';
import 'package:dcpu_flutter/core/math.dart';

sealed class Instruction {
  const Instruction({required this.op});

  static Instruction decode(int Function() readWord) {
    final firstWord = readWord();

    final opcode = firstWord & 0x1f;
    final bEncoded = (firstWord >> 5) & 0x1f;
    final aEncoded = (firstWord >> 10) & 0x3f;

    if (opcode == 0) {
      // special opcode
      final op = SpecialOp.decode(bEncoded);
      final a = Arg.decode(aEncoded, readWord);
      return SpecialInstruction(op: op, a: a);
    } else {
      // basic opcode
      final op = BasicOp.decode(opcode);
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

  List<int> encode();
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

  @override
  List<int> encode() {
    final opcode = op.opcode;
    final (bEncoded, bWord) = b.encode();
    final (aEncoded, aWord) = a.encode();

    assert(opcode & ~0x1f == 0);
    assert(bEncoded & ~0x1f == 0);
    assert(aEncoded & ~0x3f == 0);

    var word = 0;
    word |= opcode;
    word |= (bEncoded << 5);
    word |= (aEncoded << 10);

    return [
      word,
      if (aWord != null) aWord,
      if (bWord != null) bWord,
    ];
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

  @override
  List<int> encode() {
    final opcode = op.opcode;
    final (aEncoded, aWord) = a.encode();

    assert(opcode & ~0x1f == 0);
    assert(aEncoded & ~0x3f == 0);

    var word = 0;
    word |= (opcode << 5);
    word |= (aEncoded << 10);

    return [
      word,
      if (aWord != null) aWord,
    ];
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

sealed class Op {
  String get mnemonic;

  const Op();

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

  static const values = [
    ...BasicOp.values,
    ...SpecialOp.values,
  ];
}

abstract class BasicOp extends Op {
  const BasicOp();

  static BasicOp decode(int opcode) {
    return values.singleWhere(
      (op) => op.matches(opcode),
      orElse: () => throw throw IllegalBasicOpcodeException(opcode),
    );
  }

  void perform(Dcpu state, Arg a, Arg b);

  bool matches(int opcode) => opcode == this.opcode;

  int get opcode;

  static const values = [
    SetOp(),
    AddOp(),
    SubOp(),
    MulOp(),
    MliOp(),
    DivOp(),
    DviOp(),
    ModOp(),
    MdiOp(),
    AndOp(),
    BorOp(),
    XorOp(),
    ShrOp(),
    AsrOp(),
    ShlOp(),
    IfbOp(),
    IfcOp(),
    IfeOp(),
    IfnOp(),
    IfgOp(),
    IfaOp(),
    IflOp(),
    IfuOp(),
    AdxOp(),
    SbxOp(),
    StiOp(),
    StdOp(),
  ];
}

abstract class BranchingOp extends BasicOp {
  const BranchingOp();

  @override
  bool get skipAgain => true;
}

abstract class SpecialOp extends Op {
  const SpecialOp();

  static SpecialOp decode(int opcode) {
    return values.singleWhere(
      (op) => op.matches(opcode),
      orElse: () => throw throw IllegalBasicOpcodeException(opcode),
    );
  }

  void perform(Dcpu state, Arg a);

  bool matches(int opcode) => opcode == this.opcode;

  int get opcode;

  static const values = [
    JsrOp(),
    IntOp(),
    IagOp(),
    IasOp(),
    RfiOp(),
    IaqOp(),
    HwnOp(),
    HwqOp(),
    HwiOp(),
    HltOp(),
  ];
}

class SetOp extends BasicOp {
  const SetOp();

  @override
  void perform(Dcpu state, Arg a, Arg b) {
    readAWriteB(state, a, b, compute: (a) => a);
  }

  @override
  String get mnemonic => 'SET';

  @override
  int get cycles => 1;

  @override
  final opcode = 0x01;
}

class AddOp extends BasicOp {
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

  @override
  final opcode = 0x02;
}

class SubOp extends BasicOp {
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

  @override
  final opcode = 0x03;
}

class MulOp extends BasicOp {
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

  @override
  final opcode = 0x04;
}

class MliOp extends BasicOp {
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

  @override
  final opcode = 0x05;
}

class DivOp extends BasicOp {
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

  @override
  final opcode = 0x06;
}

class DviOp extends BasicOp {
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

  @override
  final opcode = 0x07;
}

class ModOp extends BasicOp {
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

  @override
  final opcode = 0x08;
}

class MdiOp extends BasicOp {
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

  @override
  final opcode = 0x09;
}

class AndOp extends BasicOp {
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

  @override
  final opcode = 0x0a;
}

class BorOp extends BasicOp {
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

  @override
  final opcode = 0x0b;
}

class XorOp extends BasicOp {
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

  @override
  final opcode = 0x0c;
}

class ShrOp extends BasicOp {
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

  @override
  final opcode = 0x0d;
}

class AsrOp extends BasicOp {
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

  @override
  final opcode = 0x0e;
}

class ShlOp extends BasicOp {
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

  @override
  final opcode = 0x0f;
}

class IfbOp extends BranchingOp {
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

  @override
  final opcode = 0x10;
}

class IfcOp extends BranchingOp {
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

  @override
  final opcode = 0x11;
}

class IfeOp extends BranchingOp {
  const IfeOp();

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

  @override
  final opcode = 0x12;
}

class IfnOp extends BranchingOp {
  const IfnOp();

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

  @override
  final opcode = 0x13;
}

class IfgOp extends BranchingOp {
  const IfgOp();

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

  @override
  final opcode = 0x14;
}

class IfaOp extends BranchingOp {
  const IfaOp();

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

  @override
  final opcode = 0x15;
}

class IflOp extends BranchingOp {
  const IflOp();

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

  @override
  final opcode = 0x16;
}

class IfuOp extends BranchingOp {
  const IfuOp();

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

  @override
  final opcode = 0x17;
}

class AdxOp extends BasicOp {
  const AdxOp();

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

  @override
  final opcode = 0x1a;
}

class SbxOp extends BasicOp {
  const SbxOp();

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

  @override
  final opcode = 0x1b;
}

class StiOp extends BasicOp {
  const StiOp();

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

  @override
  final opcode = 0x1e;
}

class StdOp extends BasicOp {
  const StdOp();

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

  @override
  final opcode = 0x1f;
}

class JsrOp extends SpecialOp {
  const JsrOp();

  @override
  void perform(Dcpu state, Arg a) {
    state.pushStack(state.regs.pc);
    state.regs.pc = a.read(state);
  }

  @override
  String get mnemonic => 'JSR';

  @override
  int get cycles => 3;

  @override
  final opcode = 0x01;
}

class IntOp extends SpecialOp {
  const IntOp();

  @override
  void perform(Dcpu state, Arg a) {
    final aCaptured = a.read(state);

    state.interruptController.request(aCaptured);
  }

  @override
  String get mnemonic => 'INT';

  @override
  int get cycles => 4;

  @override
  final opcode = 0x08;
}

class IagOp extends SpecialOp {
  const IagOp();

  @override
  void perform(Dcpu state, Arg a) {
    a.write(state, state.regs.ia);
  }

  @override
  String get mnemonic => 'IAG';

  @override
  int get cycles => 1;

  @override
  final opcode = 0x09;
}

class IasOp extends SpecialOp {
  const IasOp();

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

  @override
  final opcode = 0x0a;
}

class RfiOp extends SpecialOp {
  const RfiOp();

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

  @override
  final opcode = 0x0b;
}

class IaqOp extends SpecialOp {
  const IaqOp();

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

  @override
  final opcode = 0x0c;
}

class HwnOp extends SpecialOp {
  const HwnOp();

  @override
  void perform(Dcpu state, Arg a) {
    a.write(state, state.hardwareController.getCountDevices());
  }

  @override
  String get mnemonic => 'HWN';

  @override
  int get cycles => 2;

  @override
  final opcode = 0x10;
}

class HwqOp extends SpecialOp {
  const HwqOp();

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

  @override
  final opcode = 0x11;
}

class HwiOp extends SpecialOp {
  const HwiOp();

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

  @override
  final opcode = 0x12;
}

class LogOp extends SpecialOp {
  @override
  int get cycles => 1;

  @override
  String get mnemonic => 'LOG';

  @override
  int get opcode => 0x13;

  @override
  void perform(Dcpu state, Arg a) {
    // TODO: implement perform
    throw UnimplementedError();
  }
}

class BrkOp extends SpecialOp {
  @override
  int get cycles => 1;

  @override
  String get mnemonic => 'BRK';

  @override
  int get opcode => 0x14;

  @override
  void perform(Dcpu state, Arg a) {
    // TODO: implement perform
    throw UnimplementedError();
  }
}

class HltOp extends SpecialOp {
  const HltOp();

  @override
  int get cycles => 1;

  @override
  String get mnemonic => 'HLT';

  @override
  int get opcode => 0x15;

  @override
  void perform(Dcpu state, Arg a) {
    // TODO: Implement
    throw UnimplementedError();
  }
}

sealed class Arg {
  const Arg();

  static Arg decode(int encoded, int Function() readNextWord) {
    if (DirectRegisterArg.matches(encoded)) {
      return DirectRegisterArg.fromEncoded(encoded);
    } else if (IndirectRegisterArg.matches(encoded)) {
      return IndirectRegisterArg.fromEncoded(encoded);
    } else if (IndirectRegisterImmediateArg.matches(encoded)) {
      return IndirectRegisterImmediateArg.fromEncoded(encoded, readNextWord());
    } else if (PushPopArg.matches(encoded)) {
      return const PushPopArg();
    } else if (IndirectImmediateArg.matches(encoded)) {
      return IndirectImmediateArg(readNextWord());
    } else if (ImmediateArg.matches(encoded)) {
      return ImmediateArg(readNextWord());
    } else if (SmallImmediateArg.matches(encoded)) {
      return SmallImmediateArg.fromEncoded(encoded);
    } else {
      throw IllegalArgumentEncodingException(encoded);
    }
  }

  int get decodeCycleCount => 0;

  int read(Dcpu state);
  void write(Dcpu state, int value);

  String disassemble(bool isA);

  (int, int?) encode();
}

class DirectRegisterArg extends Arg {
  const DirectRegisterArg(this.register);

  factory DirectRegisterArg.fromEncoded(int encoded) {
    return switch (encoded) {
      0 => const DirectRegisterArg(Register.a),
      1 => const DirectRegisterArg(Register.b),
      2 => const DirectRegisterArg(Register.c),
      3 => const DirectRegisterArg(Register.x),
      4 => const DirectRegisterArg(Register.y),
      5 => const DirectRegisterArg(Register.z),
      6 => const DirectRegisterArg(Register.i),
      7 => const DirectRegisterArg(Register.j),
      0x1b => const DirectRegisterArg(Register.sp),
      0x1c => const DirectRegisterArg(Register.pc),
      0x1d => const DirectRegisterArg(Register.ex),
      _ => throw ArgumentError('Invalid register encoding: $encoded'),
    };
  }

  static const allowedRegisters = {
    Register.a,
    Register.b,
    Register.c,
    Register.x,
    Register.y,
    Register.z,
    Register.i,
    Register.j,
    Register.sp,
    Register.pc,
    Register.ex,
  };

  final Register register;

  static bool matches(int encoded) =>
      (0 <= encoded && encoded <= 0x07) || encoded == 0x1b || encoded == 0x1c || encoded == 0x1d;

  @override
  int read(Dcpu state) {
    return state.regs.read(register);
  }

  @override
  void write(Dcpu state, int value) {
    return state.regs.write(register, value);
  }

  @override
  String disassemble(bool isA) {
    return register.name;
  }

  @override
  (int, int?) encode() {
    return (
      switch (register) {
        Register.a => 0,
        Register.b => 1,
        Register.c => 2,
        Register.x => 3,
        Register.y => 4,
        Register.z => 5,
        Register.i => 6,
        Register.j => 7,
        Register.sp => 0x1b,
        Register.pc => 0x1c,
        Register.ex => 0x1d,
        _ => throw StateError('Invalid register: $register'),
      },
      null
    );
  }
}

class IndirectRegisterArg extends Arg {
  const IndirectRegisterArg(this.register) : super();

  factory IndirectRegisterArg.fromEncoded(int encoded) {
    return switch (encoded) {
      0x08 => const IndirectRegisterArg(Register.a),
      0x09 => const IndirectRegisterArg(Register.b),
      0x0a => const IndirectRegisterArg(Register.c),
      0x0b => const IndirectRegisterArg(Register.x),
      0x0c => const IndirectRegisterArg(Register.y),
      0x0d => const IndirectRegisterArg(Register.z),
      0x0e => const IndirectRegisterArg(Register.i),
      0x0f => const IndirectRegisterArg(Register.j),
      0x19 => const IndirectRegisterArg(Register.sp),
      _ => throw ArgumentError('Invalid indirect register encoding: $encoded'),
    };
  }

  final Register register;

  static const allowedRegisters = {
    Register.a,
    Register.b,
    Register.c,
    Register.x,
    Register.y,
    Register.z,
    Register.i,
    Register.j,
    Register.sp,
  };

  static bool matches(int encoded) => (0x08 <= encoded && encoded <= 0x0f) || encoded == 0x19;

  @override
  int read(Dcpu state) {
    return state.memory.read(state.regs.read(register));
  }

  @override
  void write(Dcpu state, int value) {
    return state.memory.write(state.regs.read(register), value);
  }

  @override
  String disassemble(bool isA) {
    if (register == Register.sp) {
      return 'PEEK';
    } else {
      return '[$register]';
    }
  }

  @override
  (int, int?) encode() {
    return (
      switch (register) {
        Register.a => 0x08,
        Register.b => 0x09,
        Register.c => 0x0a,
        Register.x => 0x0b,
        Register.y => 0x0c,
        Register.z => 0x0d,
        Register.i => 0x0e,
        Register.j => 0x0f,
        Register.sp => 0x19,
        _ => throw StateError('Invalid register: $register'),
      },
      null
    );
  }
}

class IndirectRegisterImmediateArg extends Arg {
  const IndirectRegisterImmediateArg(this.register, this.immediate);

  factory IndirectRegisterImmediateArg.fromEncoded(int encoded, int nextWord) {
    return switch (encoded) {
      0x10 => IndirectRegisterImmediateArg(Register.a, nextWord),
      0x11 => IndirectRegisterImmediateArg(Register.b, nextWord),
      0x12 => IndirectRegisterImmediateArg(Register.c, nextWord),
      0x13 => IndirectRegisterImmediateArg(Register.x, nextWord),
      0x14 => IndirectRegisterImmediateArg(Register.y, nextWord),
      0x15 => IndirectRegisterImmediateArg(Register.z, nextWord),
      0x16 => IndirectRegisterImmediateArg(Register.i, nextWord),
      0x17 => IndirectRegisterImmediateArg(Register.j, nextWord),
      0x1a => IndirectRegisterImmediateArg(Register.sp, nextWord),
      _ => throw ArgumentError('Invalid indirect offset register encoding: $encoded'),
    };
  }

  final Register register;
  final int immediate;

  static bool matches(int encoded) => (0x10 <= encoded && encoded <= 0x17) || encoded == 0x1a;

  static const allowedRegisters = {
    Register.a,
    Register.b,
    Register.c,
    Register.x,
    Register.y,
    Register.z,
    Register.i,
    Register.j,
    Register.sp,
  };

  @override
  int get decodeCycleCount => 1;

  @override
  int read(Dcpu state) {
    final addr = add16bit(state.regs.read(register), immediate);
    return state.memory.read(addr);
  }

  @override
  void write(Dcpu state, int value) {
    final addr = add16bit(state.regs.read(register), immediate);
    return state.memory.write(addr, value);
  }

  @override
  String disassemble(bool isA) {
    if (register == Register.sp) {
      return 'PICK $immediate';
    } else {
      return '[$register+$immediate]';
    }
  }

  @override
  (int, int) encode() {
    return (
      switch (register) {
        Register.a => 0x10,
        Register.b => 0x11,
        Register.c => 0x12,
        Register.x => 0x13,
        Register.y => 0x14,
        Register.z => 0x15,
        Register.i => 0x16,
        Register.j => 0x17,
        Register.sp => 0x1a,
        _ => throw StateError('Invalid register: $register'),
      },
      immediate
    );
  }
}

class PushPopArg extends Arg {
  const PushPopArg();

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

  @override
  (int, int?) encode() {
    return (0x18, null);
  }
}

class IndirectImmediateArg extends Arg {
  const IndirectImmediateArg(this.immediate);

  final int immediate;

  static bool matches(int encoded) => encoded == 0x1e;

  @override
  int get decodeCycleCount => 1;

  @override
  int read(Dcpu state) {
    final addr = immediate;
    return state.memory.read(addr);
  }

  @override
  void write(Dcpu state, int value) {
    return state.memory.write(immediate, value);
  }

  @override
  String disassemble(bool isA) {
    return '[${hexstring(immediate)}]';
  }

  @override
  (int, int) encode() {
    return (0x1e, immediate);
  }
}

class ImmediateArg extends Arg {
  const ImmediateArg(this.value);

  final int value;

  static bool matches(int encoded) => encoded == 0x1f;

  @override
  int get decodeCycleCount => 1;

  @override
  int read(Dcpu state) {
    return value;
  }

  @override
  void write(Dcpu state, int value) {
    // this silently fails.
  }

  @override
  String disassemble(bool isA) {
    return hexstring(value);
  }

  @override
  (int, int) encode() {
    return (0x1f, value);
  }
}

class SmallImmediateArg extends Arg {
  const SmallImmediateArg(this.immediate);

  factory SmallImmediateArg.fromEncoded(int encoded) {
    assert(matches(encoded));
    return SmallImmediateArg(sub16bit(encoded, 0x21));
  }

  final int immediate;

  static bool immediateInRange(int immediate) {
    assert(0 <= immediate && immediate <= 0xFFFF);

    return immediate <= 0x1E || immediate == 0xFFFF;
  }

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
    return '${from16bitsigned(immediate)}';
  }

  @override
  (int, int?) encode() {
    return (add16bit(immediate, 0x21), null);
  }
}
