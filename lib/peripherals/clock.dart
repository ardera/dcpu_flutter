import 'dart:async';

import 'package:dcpu_flutter/core/cpu.dart';
import 'package:dcpu_flutter/core/hardware.dart';
import 'package:dcpu_flutter/core/math.dart';
import 'package:flutter/material.dart';

class GenericClock extends HardwareDevice {
  GenericClock({required this.flags});

  final DcpuCompatibilityFlags flags;

  static const _genericInfo = HardwareInfo(
    hardwareId: 0x12d0b402,
    version: 1,
    manufacturerId: 0x00000000,
  );

  static const _nyaElektriskaInfo = HardwareInfo(
    hardwareId: 0x12d0b402,
    version: 1,
    manufacturerId: 0x1c6c8b36,
  );

  @override
  HardwareInfo get info => flags.clockManufacturedByNyaElektriska ? _nyaElektriskaInfo : _genericInfo;

  Timer? _timer;

  DateTime? _initialTime;

  var _interruptsEnabled = false;
  int _interruptMessage = 0;

  Duration? _tickDuration;

  void setTick(Dcpu cpu) {
    final b = cpu.regs.b;

    debugPrint('CLOCK_SET $b');

    if (b == 0) {
      // if CLOCK_QUERY should report the ticks to the last CLOCK_SET x  (x!=0)
      // we don't clear the tick duration and initial time here.
      // instead we only override it in CLOCK_SET 1 (for example).
      if (flags.clockQueryReportsTicksToLastEnable == false) {
        _tickDuration = null;
        _initialTime = null;
      }

      _timer?.cancel();
      _timer = null;
    } else {
      _timer?.cancel();

      _tickDuration = const Duration(seconds: 1) * (b / 60);

      _initialTime = cpu.getClock().now();

      _timer = cpu.createPeriodicTimer(_tickDuration!, (timer) {
        if (_interruptsEnabled) {
          cpu.interruptController.request(_interruptMessage);
        }
      });
    }
  }

  void queryTicks(Dcpu cpu) {
    late int c;
    if (_initialTime != null && _tickDuration != null) {
      final elapsedMicroseconds = cpu.getClock().now().difference(_initialTime!).inMicroseconds;

      final result = elapsedMicroseconds ~/ _tickDuration!.inMicroseconds;

      c = result;
    } else {
      c = 0;
    }

    debugPrint('CLOCK_QUERY = ${hexstring(c)}');

    cpu.regs.c = c;
  }

  void setInterrupts(Dcpu cpu) {
    final b = cpu.regs.b;

    debugPrint('CLOCK_SET_IRQ ${hexstring(b)}');

    if (b == 0) {
      _interruptsEnabled = false;
      _interruptMessage = 0;
    } else {
      _interruptsEnabled = true;
      _interruptMessage = b;
    }
  }

  @override
  void requestInterrupt(Dcpu cpu) {
    final a = cpu.regs.a;

    switch (a) {
      case 0:
        setTick(cpu);
        break;
      case 1:
        queryTicks(cpu);
        break;
      case 2:
        setInterrupts(cpu);
        break;
      default:
        break;
    }
  }
}
