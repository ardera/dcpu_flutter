import 'package:dcpu_flutter/core/cpu.dart';
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

class HardwareController {
  final _devices = <HardwareDevice>[];

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
}
