import 'package:dcpu_flutter/core/cpu.dart';
import 'package:dcpu_flutter/core/memory.dart';
import 'package:dcpu_flutter/peripherals/keyboard.dart';
import 'package:dcpu_flutter/peripherals/lem1802.dart';

class HardwareInfo {
  const HardwareInfo({
    required this.hardwareId,
    required this.version,
    required this.manufacturerId,
  })  : assert(0 <= hardwareId && hardwareId <= 0xFFFFFFFF),
        assert(0 <= version && version <= 0xFFFF),
        assert(0 <= manufacturerId && manufacturerId <= 0xFFFFFFFF);

  final int hardwareId;
  final int version;
  final int manufacturerId;
}

abstract class HardwareDevice {
  HardwareInfo get info;

  void requestInterrupt(Dcpu cpu);
}

enum DeviceMemoryBehaviour {
  mapped,
  syncInOnly,
  syncOutOnly,
  syncInOut,
}

class HardwareController {
  final _devices = <HardwareDevice>[];

  DeviceMemoryBehaviour memoryBehaviour;

  HardwareController({this.memoryBehaviour = DeviceMemoryBehaviour.mapped});

  void addDevice(HardwareDevice device) {
    _devices.add(device);
  }

  void removeDevice(HardwareDevice device) {
    final found = _devices.remove(device);
    if (!found) {
      throw StateError(
          'Device $device couldn\'t be removed because it was never added.');
    }
  }

  bool hasDeviceWithNumber(int device) {
    return device < _devices.length;
  }

  int getCountDevices() {
    return _devices.length;
  }

  HardwareInfo getHardwareInfo(int device) {
    return _devices[device].info;
  }

  void requestInterrupt(Dcpu cpu, int device) {
    return _devices[device].requestInterrupt(cpu);
  }

  Lem1802Device? findLem1802() {
    return _devices.cast<HardwareDevice?>().singleWhere(
          (device) => device is Lem1802Device,
          orElse: () => null,
        ) as Lem1802Device?;
  }

  GenericKeyboard? findKeyboard() {
    return _devices.cast<HardwareDevice?>().singleWhere(
          (device) => device is GenericKeyboard,
          orElse: () => null,
        ) as GenericKeyboard?;
  }

  void mapDeviceMemory({
    required Dcpu cpu,
    required int start,
    required int length,
    int destinationOffset = 0,
    required Memory memory,
  }) {
    cpu.memory.unmap(start, length);
    cpu.memory.map(start, length, destinationOffset, memory);

    if (memoryBehaviour == DeviceMemoryBehaviour.syncInOnly ||
        memoryBehaviour == DeviceMemoryBehaviour.syncInOut) {
      for (var offset = 0; offset < length; offset++) {
        memory.write(offset + destinationOffset, cpu.ram.read(offset + start));
      }
    }
  }

  void unmapDeviceMemory({
    required Dcpu cpu,
    required int start,
    required int length,
    int destinationOffset = 0,
    required Memory memory,
  }) {
    cpu.memory.unmap(start, length);
    cpu.memory.map(start, length, start, cpu.ram);

    if (memoryBehaviour == DeviceMemoryBehaviour.syncOutOnly ||
        memoryBehaviour == DeviceMemoryBehaviour.syncInOut) {
      for (var offset = 0; offset < length; offset++) {
        cpu.ram.write(offset + start, memory.read(offset + destinationOffset));
      }
    }
  }
}
