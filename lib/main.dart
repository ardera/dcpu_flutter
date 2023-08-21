import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:dcpu_flutter/core/cpu.dart';
import 'package:dcpu_flutter/core/hardware.dart';
import 'package:dcpu_flutter/dcpu_view.dart';
import 'package:dcpu_flutter/peripherals/clock.dart';
import 'package:dcpu_flutter/peripherals/keyboard.dart';
import 'package:dcpu_flutter/peripherals/lem1802.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DCPU-16 Emulator',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.green,
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'DCPU-16 Emulator'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class DcpuLoadFileDialog extends StatefulWidget {
  const DcpuLoadFileDialog({super.key});

  @override
  State<DcpuLoadFileDialog> createState() => _DcpuLoadFileDialogState();
}

class _DcpuLoadFileDialogState extends State<DcpuLoadFileDialog> {
  var bigEndian = false;
  var memoryBehaviour = DeviceMemoryBehaviour.syncInOut;
  File? file;

  void selectFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      final file = File(result.files.single.path!);

      setState(() {
        this.file = file;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              title: const Text('Big Endian'),
              value: bigEndian,
              onChanged: (bigEndian) {
                setState(() => this.bigEndian = bigEndian!);
              },
            ),
            ListTile(
              title: const Text('Device Memory Behaviour'),
              trailing: DropdownButton(
                items: const [
                  DropdownMenuItem<DeviceMemoryBehaviour>(
                    value: DeviceMemoryBehaviour.mapped,
                    child: Text('mapped'),
                  ),
                  DropdownMenuItem<DeviceMemoryBehaviour>(
                    value: DeviceMemoryBehaviour.syncInOnly,
                    child: Text('sync-in'),
                  ),
                  DropdownMenuItem<DeviceMemoryBehaviour>(
                    value: DeviceMemoryBehaviour.syncOutOnly,
                    child: Text('sync-out'),
                  ),
                  DropdownMenuItem<DeviceMemoryBehaviour>(
                    value: DeviceMemoryBehaviour.syncInOut,
                    child: Text('sync-in-out'),
                  ),
                ],
                value: memoryBehaviour,
                onChanged: (value) {
                  setState(() => memoryBehaviour = value!);
                },
              ),
            ),
            ElevatedButton(
              onPressed: () => selectFile(),
              child: const Text('Select File'),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 24),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: file != null
                      ? () {
                          final endian = bigEndian ? Endian.big : Endian.little;

                          final result = (
                            file!,
                            DcpuCompatibilityFlags(
                              fileLoadEndian: endian,
                              memoryBehaviour: memoryBehaviour,
                            ),
                          );

                          Navigator.of(context).pop(result);
                        }
                      : null,
                  child: const Text('Ok'),
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _MyHomePageState extends State<MyHomePage> {
  late Dcpu dcpu;

  Timer? timer;

  late int cyclesPerSecond;
  late Duration elapsedRealtime;
  late Duration elapsedCpuTime;
  late int decodedInstructions;
  late int executedInstructions;
  late int cycles;
  late double realtimeFactor;
  var disassemble = false;

  @override
  void initState() {
    super.initState();

    reset();
  }

  @override
  void dispose() {
    timer?.cancel();
    timer = null;

    super.dispose();
  }

  bool isKeyPressed(LogicalKeyboardKey key) {
    return HardwareKeyboard.instance.logicalKeysPressed.contains(key);
  }

  void reset({
    flags = const DcpuCompatibilityFlags(
      memoryBehaviour: DeviceMemoryBehaviour.syncInOut,
    ),
    File? file,
    String? assetKey,
  }) async {
    if (timer != null) pause();

    dcpu = Dcpu(compatibilityFlags: flags);

    dcpu.hardwareController.addDevice(Lem1802Device(flags: flags));
    dcpu.hardwareController.addDevice(GenericClock(flags: flags));
    dcpu.hardwareController.addDevice(GenericKeyboard(isKeyPressed: isKeyPressed, flags: flags));

    fetchStats();

    if (file != null) {
      dcpu.loadFile(file);
    } else if (assetKey != null) {
      final data = await DefaultAssetBundle.of(context).load(assetKey);

      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      dcpu.loadBytes(bytes);
    } else {
      final data = await DefaultAssetBundle.of(context).load('assets/binaries/clock.bin');

      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      dcpu.loadBytes(bytes);
    }
  }

  void loadFile() async {
    final result = await showDialog<(File, DcpuCompatibilityFlags)?>(
      context: context,
      builder: (_) => const DcpuLoadFileDialog(),
    );

    if (result != null) {
      final (file, flags) = result;
      reset(file: file, flags: flags);
    }
  }

  void fetchStats() {
    void inner() {
      cyclesPerSecond = dcpu.cyclesPerSecond;
      elapsedRealtime = dcpu.elapsedRealtime;
      elapsedCpuTime = dcpu.elapsedCpuTime;
      decodedInstructions = dcpu.decodedInstructions;
      executedInstructions = dcpu.executedInstructions;
      cycles = dcpu.cycles;
      realtimeFactor = elapsedRealtime.inMicroseconds / elapsedCpuTime.inMicroseconds;
    }

    if (mounted) {
      setState(inner);
    } else {
      inner();
    }
  }

  void play() {
    assert(this.timer == null);

    const oneFrame = Duration(microseconds: 1000000 ~/ 60);

    final timer = Timer.periodic(
      const Duration(microseconds: 1000000 ~/ 60),
      (timer) {
        dcpu.executeCpuTime(oneFrame, disassemble: disassemble);
        fetchStats();
      },
    );

    setState(() {
      this.timer = timer;
    });
  }

  void pause() {
    assert(timer != null);

    timer!.cancel();

    setState(() {
      timer = null;
    });
  }

  void runOneDcpuSecond() {
    dcpu.executeCpuTime(const Duration(seconds: 1), disassemble: disassemble);
    fetchStats();
  }

  void step() {
    dcpu.executeOne(disassemble: disassemble);
    fetchStats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Row(
        children: [
          Expanded(
            flex: 1,
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              child: Column(
                children: [
                  ListTile(
                    title: const Tooltip(
                      waitDuration: Duration(milliseconds: 500),
                      message: 'How many DCPU-16 cycles should be run per '
                          'realtime second.',
                      child: Text('Cycles Per Second'),
                    ),
                    trailing: Text('$cyclesPerSecond'),
                  ),
                  ListTile(
                    title: const Tooltip(
                      waitDuration: Duration(milliseconds: 500),
                      message: 'The realtime spent executing DCPU-16 '
                          'instructions.',
                      child: Text('Elapsed Realtime'),
                    ),
                    trailing: Text('$elapsedRealtime'),
                  ),
                  ListTile(
                    title: const Tooltip(
                      waitDuration: Duration(milliseconds: 500),
                      message: 'The virtual DCPU-16 time elapsed',
                      child: Text('Elapsed CPU time'),
                    ),
                    trailing: Text('$elapsedCpuTime'),
                  ),
                  ListTile(
                    title: const Tooltip(
                      waitDuration: Duration(milliseconds: 500),
                      message: 'The number of DCPU-16 instructions that have '
                          'been successfully decoded.',
                      child: Text('Decoded Instructions'),
                    ),
                    trailing: Text('$decodedInstructions'),
                  ),
                  ListTile(
                    title: const Tooltip(
                      waitDuration: Duration(milliseconds: 500),
                      message: 'The number of DCPU-16 instructions that have '
                          'been successfully executed.\n'
                          'Lower than the number of decoded instructions because '
                          'some instructions are skipped when an IF* instruction '
                          'fails.',
                      child: Text('Executed Instructions'),
                    ),
                    trailing: Text('$executedInstructions'),
                  ),
                  ListTile(
                    title: const Tooltip(
                      waitDuration: Duration(milliseconds: 500),
                      message: 'The number of DCPU-16 cycles it took to decode '
                          'and execute any instructions up until now.',
                      child: Text('Cycles'),
                    ),
                    trailing: Text('$cycles'),
                  ),
                  ListTile(
                    title: const Tooltip(
                      waitDuration: Duration(milliseconds: 500),
                      message: 'The elapsed realtime divided by the elapsed '
                          'DCPU-16 time.\n'
                          'How much of realtime is spent executing DCPU-16 '
                          'instructions',
                      child: Text('Realtime Factor'),
                    ),
                    trailing: Text(realtimeFactor.toStringAsFixed(5)),
                  ),
                  CheckboxListTile(
                    title: const Tooltip(
                      waitDuration: Duration(milliseconds: 500),
                      message: 'Disassemble the instruction and output it '
                          'to console before executing, when single-stepping.',
                      child: Text('Disassemble'),
                    ),
                    value: disassemble,
                    onChanged: (disassemble) {
                      setState(() {
                        this.disassemble = disassemble!;
                      });
                    },
                  ),
                  ButtonBar(
                    alignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: reset,
                        child: const Text('Reset'),
                      ),
                      ElevatedButton(
                        onPressed: loadFile,
                        child: const Text('Load File'),
                      ),
                      if (timer == null)
                        ElevatedButton(
                          onPressed: play,
                          child: const Icon(Icons.play_arrow),
                        ),
                      if (timer != null)
                        ElevatedButton(
                          onPressed: pause,
                          child: const Icon(Icons.pause),
                        ),
                      ElevatedButton(
                        onPressed: runOneDcpuSecond,
                        child: const Text('1s'),
                      ),
                      ElevatedButton(
                        onPressed: step,
                        child: const Text('Step'),
                      )
                    ],
                  )
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Center(
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 12,
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Focus(
                    autofocus: true,
                    child: DcpuView(cpu: dcpu),
                    onKeyEvent: (node, event) {
                      if (event is! KeyDownEvent) {
                        return KeyEventResult.handled;
                      }

                      final keyboard = dcpu.hardwareController.findDevice<GenericKeyboard>();

                      if (keyboard != null) {
                        debugPrint('onKeyEvent: $event');
                        keyboard.onKeyEvent(event, dcpu);
                      }

                      return KeyEventResult.handled;
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
