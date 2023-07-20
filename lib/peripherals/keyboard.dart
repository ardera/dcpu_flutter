import 'dart:collection';

import 'package:dcpu_flutter/core/cpu.dart';
import 'package:dcpu_flutter/core/hardware.dart';
import 'package:flutter/services.dart';

int? toDcpuKey(
  LogicalKeyboardKey key,
  String? character, {
  bool swapArrowLeftRight = false,
}) {
  if (key == LogicalKeyboardKey.backspace) {
    return 0x10;
  } else if (key == LogicalKeyboardKey.enter) {
    return 0x11;
  } else if (key == LogicalKeyboardKey.insert) {
    return 0x12;
  } else if (key == LogicalKeyboardKey.delete) {
    return 0x13;
  } else if (key == LogicalKeyboardKey.arrowUp) {
    return 0x80;
  } else if (key == LogicalKeyboardKey.arrowDown) {
    return 0x81;
  } else if (key == LogicalKeyboardKey.arrowLeft) {
    return swapArrowLeftRight ? 0x83 : 0x82;
  } else if (key == LogicalKeyboardKey.arrowRight) {
    return swapArrowLeftRight ? 0x82 : 0x83;
  } else if (key == LogicalKeyboardKey.shift) {
    return 0x90;
  } else if (key == LogicalKeyboardKey.control) {
    return 0x91;
  } else if (character != null && character.isNotEmpty) {
    final codeUnit = character.codeUnitAt(0);
    if (codeUnit & ~0x7f != 0) {
      // not ascii.
      return null;
    } else if (codeUnit < 0x20) {
      // ascii control character.
      return null;
    } else {
      return codeUnit;
    }
  }

  return null;
}

LogicalKeyboardKey? toLogicalKey(int dcpuKey,
    {bool swapArrowLeftRight = false}) {
  if (dcpuKey == 0x10) {
    return LogicalKeyboardKey.backspace;
  } else if (dcpuKey == 0x11) {
    return LogicalKeyboardKey.enter;
  } else if (dcpuKey == 0x12) {
    return LogicalKeyboardKey.insert;
  } else if (dcpuKey == 0x13) {
    return LogicalKeyboardKey.delete;
  } else if (0x20 <= dcpuKey && dcpuKey <= 0x7f) {
    return null;
  } else if (dcpuKey == 0x80) {
    return LogicalKeyboardKey.arrowUp;
  } else if (dcpuKey == 0x81) {
    return LogicalKeyboardKey.arrowDown;
  } else if (dcpuKey == 0x82) {
    return swapArrowLeftRight
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowRight;
  } else if (dcpuKey == 0x83) {
    return swapArrowLeftRight
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;
  } else if (dcpuKey == 0x90) {
    return LogicalKeyboardKey.shift;
  } else if (dcpuKey == 0x91) {
    return LogicalKeyboardKey.control;
  }

  return null;
}

class GenericKeyboard extends HardwareDevice {
  GenericKeyboard({
    required this.isKeyPressed,
    this.swapArrowLeftRight = false,
  });

  final bool Function(LogicalKeyboardKey) isKeyPressed;
  final bool swapArrowLeftRight;

  @override
  HardwareInfo get info {
    return const HardwareInfo(
      hardwareId: 0x30cf7406,
      version: 0x0001,
      manufacturerId: 0x00000000,
    );
  }

  final _keyQueue = Queue<int>();
  var _interruptMessage = 0;

  void onKeyEvent(KeyEvent event, Dcpu cpu) {
    final key = toDcpuKey(
      event.logicalKey,
      event.character,
      swapArrowLeftRight: swapArrowLeftRight,
    );
    if (key != null) {
      _keyQueue.add(key);

      if (_interruptMessage != 0) {
        cpu.interruptController.request(_interruptMessage);
      }
    }
  }

  void clearBuffer(Dcpu cpu) {
    _keyQueue.clear();
  }

  void readKey(Dcpu cpu) {
    late int c;
    if (_keyQueue.isNotEmpty) {
      c = _keyQueue.removeFirst();
    } else {
      c = 0;
    }

    cpu.regs.c = c;
  }

  void isDown(Dcpu cpu) {
    final b = cpu.regs.b;

    late int c;
    final logicalKey = toLogicalKey(
      b,
      swapArrowLeftRight: swapArrowLeftRight,
    );

    if (logicalKey != null && isKeyPressed(logicalKey)) {
      c = 1;
    } else {
      c = 0;
    }

    cpu.regs.c = c;
  }

  void setInterrupts(Dcpu cpu) {
    _interruptMessage = cpu.regs.b;
  }

  @override
  void requestInterrupt(Dcpu cpu) {
    final a = cpu.regs.a;

    switch (a) {
      case 0:
        clearBuffer(cpu);
        break;
      case 1:
        readKey(cpu);
        break;
      case 2:
        isDown(cpu);
        break;
      case 3:
        setInterrupts(cpu);
        break;
    }
  }
}
