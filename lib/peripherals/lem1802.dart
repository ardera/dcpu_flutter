import 'dart:async';

import 'package:dcpu_flutter/core/cpu.dart';
import 'package:dcpu_flutter/core/hardware.dart';
import 'package:dcpu_flutter/core/math.dart';
import 'package:dcpu_flutter/core/memory.dart';
import 'package:flutter/material.dart';

class Glyph {
  const Glyph({required this.first, required this.second})
      : value = first << 16 | second;

  static const width = 4;
  static const height = 8;
  final int value;
  final int first;
  final int second;

  bool bitFor(int x, int y) {
    assert(0 <= x && x < width);
    assert(0 <= y && y < height);

    // (0|7) (0|6) (0|5) (0|4) (0|3) (0|2) (0|1) (0|0)
    // (1|7) (1|6) (1|5) (1|4) (1|3) (1|2) (0|1) (1|0)
    // (2|7) (2|6) (2|5) (2|4) (2|3) (2|2) (0|1) (2|0)
    // (3|7) (3|6) (3|5) (3|4) (3|3) (3|2) (0|1) (3|0)

    return (value >> ((width - 1 - x) * height + y)) & 1 == 1;
  }

  bool isForeground(int x, int y) {
    return bitFor(x, y);
  }

  bool isBackground(int x, int y) {
    return !bitFor(x, y);
  }

  Glyph copyWith({int? first, int? second}) {
    return Glyph(
      first: first ?? this.first,
      second: second ?? this.second,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is Glyph && value == other.value;
  }

  @override
  int get hashCode => value.hashCode;
}

class Cell {
  const Cell(this.value);

  static const blank = Cell(0);

  final int value;

  int foregroundColorIndex() {
    return value >> 12;
  }

  int backgroundColorIndex() {
    return (value >> 8) & 0xF;
  }

  bool blink() {
    return value & 0x80 != 0;
  }

  int character() {
    return value & 0x7F;
  }

  @override
  bool operator ==(Object other) {
    return other is Cell && value == other.value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() {
    return 'Cell('
        'value: ${hexstring(value)}, '
        'foregroundColorIndex: ${foregroundColorIndex()}, '
        'backgroundColorIndex: ${backgroundColorIndex()}, '
        'blink: ${blink()}, '
        'character: ${character()}'
        ')';
  }
}

class LemColor {
  const LemColor(this.value);

  final int value;

  static const black = LemColor(0);
  static const white = LemColor(0x0FFF);

  int getBlue() {
    return value & 0x0F;
  }

  int getGreen() {
    return (value >> 4) & 0xF;
  }

  int getRed() {
    return (value >> 8) & 0xF;
  }

  Color getColor() {
    return Color.fromARGB(
      255,
      getRed() << 4,
      getGreen() << 4,
      getBlue() << 4,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LemColor && value == other.value;
  }

  @override
  int get hashCode => value.hashCode;
}

class Framebuffer extends Memory with ChangeNotifier {
  static const width = 32;
  static const height = 12;
  static const length = 386;

  final pixels = List.generate(length, (_) => Cell.blank);

  @override
  bool addrValid(int address) {
    return 0 <= address && address < length;
  }

  @override
  int read(int addr) {
    return pixels[addr].value;
  }

  @override
  void write(int addr, int value) {
    final pixel = Cell(value);

    if (pixels[addr] != pixel) {
      pixels[addr] = pixel;
      notifyListeners();
    }
  }

  Cell getCell(int x, int y) {
    assert(0 <= x && x <= width);
    assert(0 <= y && y <= height);
    return pixels[y * width + x];
  }
}

class Font extends Memory with ChangeNotifier {
  static const maxCharCode = 255;
  static const length = 256;

  static const rom = [
    0xb79e,
    0x388e,
    0x722c,
    0x75f4,
    0x19bb,
    0x7f8f,
    0x85f9,
    0xb158,
    0x242e,
    0x2400,
    0x082a,
    0x0800,
    0x0008,
    0x0000,
    0x0808,
    0x0808,
    0x00ff,
    0x0000,
    0x00f8,
    0x0808,
    0x08f8,
    0x0000,
    0x080f,
    0x0000,
    0x000f,
    0x0808,
    0x00ff,
    0x0808,
    0x08f8,
    0x0808,
    0x08ff,
    0x0000,
    0x080f,
    0x0808,
    0x08ff,
    0x0808,
    0x6633,
    0x99cc,
    0x9933,
    0x66cc,
    0xfef8,
    0xe080,
    0x7f1f,
    0x0701,
    0x0107,
    0x1f7f,
    0x80e0,
    0xf8fe,
    0x5500,
    0xaa00,
    0x55aa,
    0x55aa,
    0xffaa,
    0xff55,
    0x0f0f,
    0x0f0f,
    0xf0f0,
    0xf0f0,
    0x0000,
    0xffff,
    0xffff,
    0x0000,
    0xffff,
    0xffff,
    0x0000,
    0x0000,
    0x005f,
    0x0000,
    0x0300,
    0x0300,
    0x3e14,
    0x3e00,
    0x266b,
    0x3200,
    0x611c,
    0x4300,
    0x3629,
    0x7650,
    0x0002,
    0x0100,
    0x1c22,
    0x4100,
    0x4122,
    0x1c00,
    0x1408,
    0x1400,
    0x081c,
    0x0800,
    0x4020,
    0x0000,
    0x0808,
    0x0800,
    0x0040,
    0x0000,
    0x601c,
    0x0300,
    0x3e49,
    0x3e00,
    0x427f,
    0x4000,
    0x6259,
    0x4600,
    0x2249,
    0x3600,
    0x0f08,
    0x7f00,
    0x2745,
    0x3900,
    0x3e49,
    0x3200,
    0x6119,
    0x0700,
    0x3649,
    0x3600,
    0x2649,
    0x3e00,
    0x0024,
    0x0000,
    0x4024,
    0x0000,
    0x0814,
    0x2241,
    0x1414,
    0x1400,
    0x4122,
    0x1408,
    0x0259,
    0x0600,
    0x3e59,
    0x5e00,
    0x7e09,
    0x7e00,
    0x7f49,
    0x3600,
    0x3e41,
    0x2200,
    0x7f41,
    0x3e00,
    0x7f49,
    0x4100,
    0x7f09,
    0x0100,
    0x3e41,
    0x7a00,
    0x7f08,
    0x7f00,
    0x417f,
    0x4100,
    0x2040,
    0x3f00,
    0x7f08,
    0x7700,
    0x7f40,
    0x4000,
    0x7f06,
    0x7f00,
    0x7f01,
    0x7e00,
    0x3e41,
    0x3e00,
    0x7f09,
    0x0600,
    0x3e41,
    0xbe00,
    0x7f09,
    0x7600,
    0x2649,
    0x3200,
    0x017f,
    0x0100,
    0x3f40,
    0x3f00,
    0x1f60,
    0x1f00,
    0x7f30,
    0x7f00,
    0x7708,
    0x7700,
    0x0778,
    0x0700,
    0x7149,
    0x4700,
    0x007f,
    0x4100,
    0x031c,
    0x6000,
    0x0041,
    0x7f00,
    0x0201,
    0x0200,
    0x8080,
    0x8000,
    0x0001,
    0x0200,
    0x2454,
    0x7800,
    0x7f44,
    0x3800,
    0x3844,
    0x2800,
    0x3844,
    0x7f00,
    0x3854,
    0x5800,
    0x087e,
    0x0900,
    0x4854,
    0x3c00,
    0x7f04,
    0x7800,
    0x447d,
    0x4000,
    0x2040,
    0x3d00,
    0x7f10,
    0x6c00,
    0x417f,
    0x4000,
    0x7c18,
    0x7c00,
    0x7c04,
    0x7800,
    0x3844,
    0x3800,
    0x7c14,
    0x0800,
    0x0814,
    0x7c00,
    0x7c04,
    0x0800,
    0x4854,
    0x2400,
    0x043e,
    0x4400,
    0x3c40,
    0x7c00,
    0x1c60,
    0x1c00,
    0x7c30,
    0x7c00,
    0x6c10,
    0x6c00,
    0x4c50,
    0x3c00,
    0x6454,
    0x4c00,
    0x0836,
    0x4100,
    0x0077,
    0x0000,
    0x4136,
    0x0800,
    0x0201,
    0x0201,
    0x0205,
    0x0200
  ];

  final glyphs = [
    for (var i = 0; i < rom.length; i += 2)
      Glyph(first: rom[i], second: rom[i + 1])
  ];

  Glyph glyphFor(int characterCode) {
    assert(0 <= characterCode && characterCode <= maxCharCode);
    return glyphs[characterCode];
  }

  @override
  bool addrValid(int address) {
    return 0 <= address && address < length;
  }

  @override
  int read(int addr) {
    final glyphIndex = addr ~/ 2;
    final first = (addr & 1) == 0;

    return first ? glyphs[glyphIndex].first : glyphs[glyphIndex].second;
  }

  @override
  void write(int addr, int value) {
    final glyphIndex = addr ~/ 2;
    final first = (addr & 1) == 0;

    final glyph = glyphs[glyphIndex].copyWith(
      first: first ? value : null,
      second: first ? null : value,
    );

    if (glyph != glyphs[glyphIndex]) {
      glyphs[glyphIndex] = glyph;
      notifyListeners();
    }
  }
}

class Palette extends Memory with ChangeNotifier {
  static const length = 16;

  static const rom = [
    0x0000,
    0x000a,
    0x00a0,
    0x00aa,
    0x0a00,
    0x0a0a,
    0x0a50,
    0x0aaa,
    0x0555,
    0x055f,
    0x05f5,
    0x05ff,
    0x0f55,
    0x0f5f,
    0x0ff5,
    0x0fff
  ];

  final colors = rom.map((word) => LemColor(word)).toList(growable: false);

  @override
  bool addrValid(int address) {
    return 0 <= address && address < length;
  }

  @override
  int read(int addr) {
    return colors[addr].value;
  }

  @override
  void write(int addr, int value) {
    final color = LemColor(value);
    if (colors[addr] != color) {
      colors[addr] = color;
      notifyListeners();
    }
  }

  LemColor getColor(int index) {
    assert(0 <= index && index < length);
    return colors[index];
  }
}

class Lem1802Device extends HardwareDevice with ChangeNotifier {
  @override
  HardwareInfo get info => const HardwareInfo(
        hardwareId: 0x7349f615,
        version: 0x1802,
        manufacturerId: 0x1c6c8b36,
      );

  static const _splashDuration = Duration(seconds: 2);

  Timer? _blinkTimer;
  Timer? _splashTimer;
  var _screenMapStart = 0;
  var _fontMapStart = 0;
  var _paletteMapStart = 0;

  var borderColorIndex = 0;
  var blinkOn = true;
  var enabled = false;
  var showSplash = false;

  final framebuffer = Framebuffer();
  final font = Font();
  final palette = Palette();

  void unmap(Dcpu cpu, int start, int length, Memory memory) {
    cpu.hardwareController.unmapDeviceMemory(
      cpu: cpu,
      start: start,
      length: length,
      memory: memory,
    );
  }

  void map(Dcpu cpu, int start, int length, Memory memory) {
    cpu.hardwareController.mapDeviceMemory(
      cpu: cpu,
      start: start,
      length: length,
      memory: memory,
    );
  }

  void mmapScreen(Dcpu cpu) {
    final b = cpu.regs.b;

    debugPrint('MEM_MAP_SCREEN ${hexstring(b)}');

    if (b == _screenMapStart) {
      // nothing to do
      return;
    }

    if (b == 0) {
      cpu.hardwareController.unmapDeviceMemory(
        cpu: cpu,
        start: _screenMapStart,
        length: Framebuffer.length,
        memory: framebuffer,
      );

      if (b == 0) {
        enabled = false;
        showSplash = false;
        notifyListeners();

        _splashTimer?.cancel();
        _splashTimer = null;
      }
    } else {
      cpu.hardwareController.mapDeviceMemory(
        cpu: cpu,
        start: b,
        length: Framebuffer.length,
        memory: framebuffer,
      );

      if (enabled == false) {
        assert(_splashTimer == null);

        // Enable _AND_ show splash screen if we're turning on the display now.
        enabled = true;
        showSplash = true;

        late Timer timer;
        timer = cpu.createTimer(
          _splashDuration,
          () {
            assert(enabled);
            assert(showSplash);
            assert(_splashTimer == timer);

            showSplash = false;
            notifyListeners();

            _splashTimer = null;
          },
        );

        _splashTimer = timer;

        notifyListeners();
      }
    }

    _screenMapStart = b;
  }

  void mmapFont(Dcpu cpu) {
    final b = cpu.regs.b;

    debugPrint('MEM_MAP_FONT ${hexstring(b)}');

    if (b == _fontMapStart) {
      // nothing to do
      return;
    }

    if (b == 0) {
      unmap(cpu, _fontMapStart, Font.length, font);
    } else {
      map(cpu, b, Font.length, font);
    }

    _fontMapStart = b;
  }

  void mmapPalette(Dcpu cpu) {
    final b = cpu.regs.b;

    debugPrint('MEM_MAP_PALETTE ${hexstring(b)}');

    if (b == _paletteMapStart) {
      // nothing to do
      return;
    }

    if (b == 0) {
      unmap(cpu, _paletteMapStart, Palette.length, palette);
    } else {
      map(cpu, b, Palette.length, palette);
    }

    _paletteMapStart = b;
  }

  void setBorderColor(Dcpu cpu) {
    final b = cpu.regs.b & 0xF;

    debugPrint('SET_BORDER_COLOR ${hexstring(b)}');

    if (b == borderColorIndex) {
      // nothing to do
      return;
    }

    borderColorIndex = b;
    notifyListeners();
  }

  void memdumpFont(Dcpu cpu) {
    final b = cpu.regs.b;

    debugPrint('MEM_DUMP_FONT ${hexstring(b)}');

    for (final entry in Font.rom.asMap().entries) {
      final offset = entry.key;
      final word = entry.value;
      cpu.memory.write(add16bit(b, offset), word);
    }

    cpu.elapseCycles(256);
  }

  void memdumpPalette(Dcpu cpu) {
    final b = cpu.regs.b;

    debugPrint('MEM_DUMP_PALETTE ${hexstring(b)}');

    for (final entry in Palette.rom.asMap().entries) {
      final offset = entry.key;
      final word = entry.value;
      cpu.memory.write(add16bit(b, offset), word);
    }

    cpu.elapseCycles(16);
  }

  @override
  void requestInterrupt(Dcpu cpu) {
    final a = cpu.regs.a;

    _blinkTimer ??= cpu.createPeriodicTimer(
      const Duration(milliseconds: 500),
      (_) {
        blinkOn = !blinkOn;
        notifyListeners();
      },
    );

    switch (a) {
      case 0:
        return mmapScreen(cpu);
      case 1:
        return mmapFont(cpu);
      case 2:
        return mmapPalette(cpu);
      case 3:
        return setBorderColor(cpu);
      case 4:
        return memdumpFont(cpu);
      case 5:
        return memdumpPalette(cpu);
      default:
        return;
    }
  }
}
