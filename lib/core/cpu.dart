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
import 'package:flutter/material.dart';

import 'math.dart';

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
  });

  final Endian fileLoadEndian;
  final DeviceMemoryBehaviour memoryBehaviour;
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

    final instr = Instruction.decode(readWord);

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

    return Instruction.decode(readWord).disassemble();
  }

  int loadFile(
    File file, {
    int offset = 0,
    int? length,
  }) {
    return ram.loadFile(
      file,
      offset: offset,
      length: length,
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
        debugPrint(
          'illegal instruction ${hexstring(memory.read(regs.pc))}: $e',
        );
      }
      fault();
      return;
    }

    if (skip) {
      if (disassemble) {
        debugPrint(' skipping: ${instr.disassemble()}');
      }
      skip = instr.op.skipAgain;

      elapseCycles(instr.decodeCycleCount);
    } else {
      if (disassemble) {
        debugPrint('executing: ${instr.disassemble()}');
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
      executeOne(disassemble: disassemble);
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
  }
}
