// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:dcpu_flutter/core/hardware.dart';
import 'package:dcpu_flutter/core/instructions.dart';
import 'package:dcpu_flutter/core/memory.dart';
import 'package:fake_async/fake_async.dart';

import 'math.dart';

enum Register {
  a,
  b,
  c,
  x,
  y,
  z,
  i,
  j,
  sp,
  pc,
  ex,
  ia;

  @override
  String toString() {
    return name.toUpperCase();
  }
}

class RegisterFile {
  RegisterFile({
    this.a = 0,
    this.b = 0,
    this.c = 0,
    this.x = 0,
    this.y = 0,
    this.z = 0,
    this.i = 0,
    this.j = 0,
    this.sp = 0xffff,
    this.pc = 0,
    this.ex = 0,
    this.ia = 0,
  });

  int a;
  int b;
  int c;
  int x;
  int y;
  int z;
  int i;
  int j;
  int sp;
  int pc;
  int ex;
  int ia;

  int read(Register register) {
    return switch (register) {
      Register.a => a,
      Register.b => b,
      Register.c => c,
      Register.x => x,
      Register.y => y,
      Register.z => z,
      Register.i => i,
      Register.j => j,
      Register.sp => sp,
      Register.pc => pc,
      Register.ex => ex,
      Register.ia => ia
    };
  }

  void write(Register register, int value) {
    final _ = switch (register) {
      Register.a => a = value,
      Register.b => b = value,
      Register.c => c = value,
      Register.x => x = value,
      Register.y => y = value,
      Register.z => z = value,
      Register.i => i = value,
      Register.j => j = value,
      Register.sp => sp = value,
      Register.pc => pc = value,
      Register.ex => ex = value,
      Register.ia => ia = value
    };
  }

  int readByIndex(int index) {
    assert(0 <= index && index <= 11);
    switch (index) {
      case 0:
        return a;
      case 1:
        return b;
      case 2:
        return c;
      case 3:
        return x;
      case 4:
        return y;
      case 5:
        return z;
      case 6:
        return i;
      case 7:
        return j;
      case 8:
        return sp;
      case 9:
        return pc;
      case 10:
        return ex;
      case 11:
        return ia;
    }
    throw Error();
  }

  void writeByIndex(int index, int value) {
    assert(0 <= index && index <= 11);
    assert(0 <= value && value <= 0xFFFF);
    switch (index) {
      case 0:
        a = value;
        break;
      case 1:
        b = value;
        break;
      case 2:
        c = value;
        break;
      case 3:
        x = value;
        break;
      case 4:
        y = value;
        break;
      case 5:
        z = value;
        break;
      case 6:
        i = value;
        break;
      case 7:
        j = value;
        break;
      case 8:
        sp = value;
        break;
      case 9:
        pc = value;
        break;
      case 10:
        ex = value;
        break;
      case 11:
        ia = value;
        break;
    }
  }

  static String registerName(int index) {
    assert(0 <= index && index <= 11);
    switch (index) {
      case 0:
        return 'A';
      case 1:
        return 'B';
      case 2:
        return 'C';
      case 3:
        return 'X';
      case 4:
        return 'Y';
      case 5:
        return 'Z';
      case 6:
        return 'I';
      case 7:
        return 'J';
      case 8:
        return 'SP';
      case 9:
        return 'PC';
      case 10:
        return 'EX';
      case 11:
        return 'IA';
    }
    throw Error();
  }
}

class DcpuCompatibilityFlags {
  const DcpuCompatibilityFlags({
    this.fileLoadEndian = Endian.little,
    this.memoryBehaviour = DeviceMemoryBehaviour.mapped,
    this.clockQueryReportsTicksToLastEnable = true,
    this.enableHlt = true,
    this.enableLog = false,
    this.enableBrk = false,
    this.swapLeftAndRightArrowKeys = true,
    this.lemAlternativeHardwareId = false,
    this.clockManufacturedByNyaElektriska = false,
  });

  /// The endianess to use when loading ROM files, to construct DCPU-16 words
  /// from the raw file bytes.
  ///
  /// Most binaries use [Endian.little], but some files do use [Endian.big].
  final Endian fileLoadEndian;

  /// It's slightly unclear how exactly device memory should be mapped into
  /// DCPU-16 memory.
  ///
  /// Some binaries assume there's only physical memory, and mapping a hardware
  /// device to memory means that that hardware device will just read from the
  /// given region of DCPU-16 RAM. ([DeviceMemoryBehaviour.syncInOut], kinda)
  ///
  /// Other binaries assume hardware devices have internal RAM as well, and
  /// mapping a device means hardware and DCPU-16 RAM are synchronized for the
  /// duration of the mapping. ([DeviceMemoryBehaviour.syncInOut])
  ///
  /// Other binaries assume hardware devices have internal RAM, but mapping
  /// a device means the mapped memory region will exclusively point to the
  /// hardware device memory only, not DCPU-16 RAM (i.e. they're not
  /// synchronized) for the duration of the mapping.
  /// ([DeviceMemoryBehaviour.mapped])
  final DeviceMemoryBehaviour memoryBehaviour;

  /// If true, CLOCK_QUERY (clock interrupt A=1) reports the number of ticks
  /// passed to the last call to CLOCK_SET (clock interrupt A=1) with an
  /// argument that's not 0.
  /// Otherwise, CLOCK_QUERY reports the number of ticks since to the last
  /// CLOCK_SET with any argument (not just != 0)
  final bool clockQueryReportsTicksToLastEnable;

  /// Enable decoding & execution of HLT instructions.
  final bool enableHlt;

  /// Enable decoding & execution of LOG instructions.
  final bool enableLog;

  /// Enable decoding & execution of BRK instructions.
  final bool enableBrk;

  /// Report right arrow key when left arrow key is pressed, and other way
  /// around.
  final bool swapLeftAndRightArrowKeys;

  /// Make the LEM1802 use 7348 f615 as the hardware id, instead of the normal
  /// 7349 f615.
  final bool lemAlternativeHardwareId;

  /// True of the clock should have the NYA ELEKTRISKA Manufacturer ID instead
  /// of the default 0000 0000 manufacturer id.
  final bool clockManufacturedByNyaElektriska;
}

class Dcpu {
  Dcpu({
    this.compatibilityFlags = const DcpuCompatibilityFlags(),
  }) : hardwareController = HardwareController(
          memoryBehaviour: compatibilityFlags.memoryBehaviour,
        );

  final DcpuCompatibilityFlags compatibilityFlags;

  final regs = RegisterFile();
  final ram = RAM();
  late final memory = VirtualMemory()..map(0, 65536, 0, ram);
  final interruptController = InterruptController();
  final HardwareController hardwareController;
  final _fakeAsync = FakeAsync();
  final _realtimeWatch = Stopwatch();

  var halted = false;
  var skip = false;

  var _cyclesPerSecond = 100000;

  late var _cycleDuration = Duration(microseconds: 1000000 ~/ _cyclesPerSecond);

  set cyclesPerSecond(int cycles) {
    _cyclesPerSecond = cycles;
    _cycleDuration = Duration(microseconds: 1000000 ~/ cycles);
  }

  int get cyclesPerSecond => _cyclesPerSecond;

  Duration get elapsedRealtime => _realtimeWatch.elapsed;

  Duration get elapsedCpuTime => _fakeAsync.elapsed;

  int _decodedInstructions = 0;
  int get decodedInstructions => _decodedInstructions;

  int _executedInstructions = 0;
  int get executedInstructions => _executedInstructions;

  int _cycles = 0;
  int get cycles => _cycles;

  Timer createPeriodicTimer(Duration duration, void Function(Timer) callback) {
    return _fakeAsync.run((self) => Timer.periodic(duration, callback));
  }

  Timer createTimer(Duration duration, void Function() callback) {
    return _fakeAsync.run((self) => Timer(duration, callback));
  }

  Clock getClock() {
    return _fakeAsync.run((self) => clock);
  }

  void _elapse(Duration duration) {
    return _fakeAsync.elapseBlocking(duration);
  }

  void elapseCycles(int cycles) {
    _cycles += cycles;
    return _elapse(_cycleDuration * cycles);
  }

  void _processClockEvents() {
    return _fakeAsync.elapse(Duration.zero);
  }

  int popStack() {
    final addr = regs.sp;
    regs.sp = add16bit(regs.sp, 1);
    return memory.read(addr);
  }

  void pushStack(int value) {
    final addr = regs.sp = sub16bit(regs.sp, 1);
    return memory.write(addr, value);
  }

  int readPeek() {
    return memory.read(regs.sp);
  }

  void writePeek(int value) {
    return memory.write(regs.sp, value);
  }

  void fault() {
    elapseCycles(4);
  }

  Instruction _decodeInstruction() {
    var pc = regs.pc;

    int readWord() {
      // [PC++]
      final result = memory.read(pc);
      pc = add16bit(pc, 1);
      return result;
    }

    final instr = Instruction.decode(readWord, flags: compatibilityFlags);

    // Only apply pc once we've actually decoded the instruction.
    regs.pc = pc;

    return instr;
  }

  String disassembleNext() {
    var pc = regs.pc;

    int readWord() {
      // [PC++]
      final result = memory.read(pc);
      pc = add16bit(pc, 1);
      return result;
    }

    return Instruction.decode(readWord, flags: compatibilityFlags).disassemble();
  }

  int loadBytes(
    Iterable<int> bytes, {
    int offset = 0,
  }) {
    return ram.loadBytes(
      bytes,
      offset: offset,
      endian: compatibilityFlags.fileLoadEndian,
    );
  }

  int loadFile(
    File file, {
    int offset = 0,
  }) {
    return ram.loadFile(
      file,
      offset: offset,
      endian: compatibilityFlags.fileLoadEndian,
    );
  }

  /// Execute or skip one instruction and advance processor clock.
  /// Don't handle interrupts or process timer events.
  void stepOne({disassemble = false}) {
    late Instruction instr;
    try {
      instr = _decodeInstruction();
      _decodedInstructions++;
    } on DecoderException catch (e) {
      if (disassemble) {
        print(
          'illegal instruction ${hexstring(memory.read(regs.pc))}: $e',
        );
      }
      fault();
      skip = false;
      return;
    }

    if (skip) {
      if (disassemble) {
        print(' skipping: ${instr.disassemble()}');
      }
      skip = instr.op.skipAgain;

      elapseCycles(instr.decodeCycleCount);
    } else {
      if (disassemble) {
        print('executing: ${instr.disassemble()}');
      }
      instr.perform(this);
      _executedInstructions++;

      elapseCycles(instr.decodeCycleCount + instr.cycles);
    }
  }

  /// Run stepOne until skip is false and advance processor clock.
  /// Then process timer events, then handle interrupts if interrupt handling
  /// is enabled.
  void executeOne({disassemble = false}) {
    do {
      stepOne(disassemble: disassemble);
    } while (skip);

    _processClockEvents();

    if (interruptController.shouldTrigger()) {
      interruptController.trigger(this);
    }
  }

  /// Run executeOne until [duration] of DCPU-time has passed, according
  /// to [cyclesPerSecond] and the cycle cost of the executed instructions.
  void executeCpuTime(Duration duration, {disassemble = false}) {
    _realtimeWatch.start();

    final clock = getClock();

    final start = clock.now();
    final end = start.add(duration);

    while (clock.now().isBefore(end)) {
      if (halted) {
        elapseCycles(1);

        _processClockEvents();

        if (interruptController.shouldTrigger()) {
          interruptController.trigger(this);
        }
      } else {
        executeOne(disassemble: disassemble);
      }
    }

    _realtimeWatch.stop();

    // debugPrint(
    //   'Executing $duration of DCPU time took ${watch.elapsed} of realtime',
    // );
  }
}

class InterruptController {
  final _queue = Queue<int>();
  var _queueing = false;
  var _enabled = false;

  void request(int message) {
    if (_enabled) {
      _queue.add(message);
    }
  }

  void disable() {
    _enabled = false;
    _queue.clear();
  }

  void enable() {
    _enabled = true;
  }

  void enableQueueing() {
    _queueing = true;
  }

  void disableQueueing() {
    _queueing = false;
  }

  bool shouldTrigger() {
    return !_queueing && _queue.isNotEmpty;
  }

  void trigger(Dcpu cpu) {
    assert(cpu.regs.ia != 0);
    assert(shouldTrigger());
    assert(cpu.skip == false);

    final message = _queue.removeFirst();

    enableQueueing();
    cpu.pushStack(cpu.regs.pc);
    cpu.pushStack(cpu.regs.a);
    cpu.regs.pc = cpu.regs.ia;
    cpu.regs.a = message;
    cpu.halted = false;
  }
}
