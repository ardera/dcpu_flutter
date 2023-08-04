import 'dart:io';
import 'dart:typed_data';

import 'package:dcpu_flutter/core/math.dart';

abstract class Memory {
  bool addrValid(int address);

  void checkAddr(int address) {
    assert(addrValid(address));
  }

  bool valueValid(int value) {
    return is16bit(value);
  }

  void checkValue(int value) {
    assert(valueValid(value));
  }

  int read(int addr);

  void write(int addr, int value);
}

class BusErrorException implements Exception {
  final int addr;

  BusErrorException(this.addr);

  @override
  String toString() {
    return 'BusError: Address $addr is not mapped to anything.';
  }
}

class VirtualMemoryRegion {
  VirtualMemoryRegion({
    required this.offset,
    required this.length,
    required this.destinationOffset,
    required this.memory,
  });

  final int offset;
  final int length;
  final int destinationOffset;
  final Memory memory;

  bool contains(int addr) {
    return offset <= addr && addr < offset + length;
  }

  bool overlaps(int offset, int length) {
    final otherEnd = offset + length;
    final thisEnd = this.offset + this.length;

    return !((this.offset < offset && thisEnd <= offset) ||
        (this.offset >= otherEnd && thisEnd > otherEnd));
  }

  @override
  String toString() {
    return '${hexstring(offset)} .. ${hexstring(offset + length - 1)} (${hexstring(destinationOffset)}, $memory)';
  }
}

class VirtualMemory extends Memory {
  VirtualMemory({this.start = 0, this.length = 65536});

  final int start;
  final int length;

  var regions = <VirtualMemoryRegion>[];

  void debugPrintRegions() {
    // debugPrint('regions: ${regions.join(', ')}');
  }

  bool canCombine(VirtualMemoryRegion left, VirtualMemoryRegion right) {
    return left.memory == right.memory &&
        left.offset + left.length == right.offset &&
        left.destinationOffset + left.length == right.destinationOffset;
  }

  VirtualMemoryRegion combine(
    VirtualMemoryRegion left,
    VirtualMemoryRegion right,
  ) {
    assert(canCombine(left, right));
    return VirtualMemoryRegion(
      offset: left.offset,
      length: left.length + right.length,
      destinationOffset: left.destinationOffset,
      memory: left.memory,
    );
  }

  void map(int offset, int length, int destinationOffset, Memory memory) {
    checkAddr(offset);
    checkAddr(offset + length - 1);

    memory.checkAddr(destinationOffset);
    memory.checkAddr(destinationOffset + length - 1);

    //debugPrint(
    //  'mapping ${hexstring(offset)} .. ${hexstring(offset + length - 1)} to ${hexstring(destinationOffset)} of $memory',
    //);

    final overlap = regions.any((region) => region.overlaps(offset, length));
    if (overlap) {
      throw StateError(
        'Can\'t map region to this address range because another region is already mapped there.',
      );
    }

    var region = VirtualMemoryRegion(
      offset: offset,
      length: length,
      destinationOffset: destinationOffset,
      memory: memory,
    );

    final before = regions.cast<VirtualMemoryRegion?>().lastWhere(
          (region) => region!.offset < offset,
          orElse: () => null,
        );

    final after = regions.cast<VirtualMemoryRegion?>().firstWhere(
          (region) => region!.offset >= offset + length,
          orElse: () => null,
        );

    if (before != null &&
        canCombine(before, region) &&
        after != null &&
        canCombine(region, after)) {
      region = VirtualMemoryRegion(
        offset: before.offset,
        length: before.length + length + after.length,
        destinationOffset: before.destinationOffset,
        memory: memory,
      );
      regions.remove(before);
      regions.remove(after);
      regions.add(region);
    } else if (before != null && canCombine(before, region)) {
      region = VirtualMemoryRegion(
        offset: before.offset,
        length: before.length + length,
        destinationOffset: before.destinationOffset,
        memory: memory,
      );
      regions.remove(before);
      regions.add(region);
    } else if (after != null && canCombine(region, after)) {
      region = VirtualMemoryRegion(
        offset: offset,
        length: length + after.length,
        destinationOffset: destinationOffset,
        memory: memory,
      );
      regions.remove(after);
      regions.add(region);
    } else {
      regions.add(region);
    }

    regions.sort((lhs, rhs) => lhs.offset.compareTo(rhs.offset));

    debugPrintRegions();
  }

  void unmap(int offset, int length) {
    checkAddr(offset);
    checkAddr(offset + length - 1);

    final newRegions = <VirtualMemoryRegion>[];

    //debugPrint(
    //    'unmapping ${hexstring(offset)} .. ${hexstring(offset + length)}');

    for (final region in regions) {
      if (!region.overlaps(offset, length)) {
        newRegions.add(region);
        continue;
      }

      // unmap the part of this region that overlaps this range.
      if (region.offset < offset) {
        newRegions.add(VirtualMemoryRegion(
          offset: region.offset,
          length: offset - region.offset,
          destinationOffset: region.destinationOffset,
          memory: region.memory,
        ));
      }

      if (region.offset + region.length > offset + length) {
        newRegions.add(VirtualMemoryRegion(
          offset: offset + length,
          length: (region.offset + region.length) - (offset + length),
          destinationOffset:
              (offset + length) - region.offset + region.destinationOffset,
          memory: region.memory,
        ));
      }
    }

    newRegions.sort((lhs, rhs) => lhs.offset.compareTo(rhs.offset));

    regions = newRegions;

    debugPrintRegions();
  }

  VirtualMemoryRegion _findRegion(int addr) {
    return regions.singleWhere(
      (region) => region.contains(addr),
      orElse: () => throw BusErrorException(addr),
    );
  }

  @override
  int read(int addr) {
    checkAddr(addr);

    final region = _findRegion(addr);
    return region.memory.read(addr - region.offset + region.destinationOffset);
  }

  @override
  void write(int addr, int value) {
    checkAddr(addr);
    checkValue(value);

    final region = _findRegion(addr);
    region.memory.write(addr - region.offset + region.destinationOffset, value);
  }

  @override
  bool addrValid(int address) {
    return start <= address && address < start + length;
  }
}

abstract class MemoryOld {
  int read(int address);

  void write(int address, int value);

  static const int addrMin = 0;
  static const int addrMax = 65535;
  static const int valueMin = 0;
  static const int valueMax = 65535;

  static bool addrValid(int address) {
    return address >= addrMin && address <= addrMax;
  }

  static void checkAddr(int address) {
    assert(addrValid(address));
  }

  static bool valueValid(int value) {
    return value >= valueMin && value <= valueMax;
  }

  static void checkValue(int value) {
    assert(valueValid(value));
  }
}

class RAMAccessRecorder extends MemoryOld {
  RAMAccessRecorder(this.original);

  final MemoryOld original;
  final Map<int, int> modified = <int, int>{};

  @override
  int read(int address) {
    MemoryOld.checkAddr(address);
    return modified.containsKey(address)
        ? modified[address]!
        : original.read(address);
  }

  @override
  void write(int address, int value) {
    MemoryOld.checkAddr(address);
    MemoryOld.checkValue(value);

    if (value == original.read(value)) {
      modified.remove(address);
    } else {
      modified[address] = value;
    }
  }

  void apply(MemoryOld memory) {
    modified.forEach((key, value) {
      memory.write(key, value);
    });
  }
}

extension Pairs<T> on Iterable<T> {
  Iterable<(T, T?)> get pairs sync* {
    if (length < 1) throw RangeError.range(length, 1, null, 'length');

    var iterator = this.iterator;
    while (iterator.moveNext()) {
      final first = iterator.current;

      if (iterator.moveNext()) {
        final second = iterator.current;

        yield (first, second);
      } else {
        yield (first, null);
      }
    }
  }
}

class RAM extends Memory {
  final memory = Uint16List(65536);

  int loadBytes(
    Iterable<int> bytes, {
    int offset = 0,
    Endian endian = Endian.little,
  }) {
    final words = bytes.pairs.map((pair) {
      var (first, second) = pair;
      second ??= 0;

      return switch (endian) {
        Endian.little => first | (second << 8),
        Endian.big => (first << 8) | second,
        _ => throw UnsupportedError('Unsupported endianess: $endian'),
      };
    });

    memory.setAll(0, words);

    return words.length;
  }

  int loadFile(
    File file, {
    int offset = 0,
    Endian endian = Endian.little,
  }) {
    final bytes = file.readAsBytesSync();
    assert(bytes.length.isEven);

    return loadBytes(
      bytes,
      offset: offset,
      endian: endian,
    );
  }

  @override
  int read(int addr) {
    checkAddr(addr);
    return memory[addr];
  }

  @override
  void write(int addr, int value) {
    checkAddr(addr);
    checkValue(value);
    memory[addr] = value;
  }

  @override
  bool addrValid(int address) {
    return 0 <= address && address < 65536;
  }
}
