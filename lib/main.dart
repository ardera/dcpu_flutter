import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui';

import 'package:dcpu_flutter/core/cpu.dart';
import 'package:dcpu_flutter/dcpu_view.dart';
import 'package:dcpu_flutter/peripherals/clock.dart';
import 'package:dcpu_flutter/peripherals/lem1802.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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

    dcpu = Dcpu();

    dcpu.ram.loadFile(
      //File(r'C:\Users\hanne\Desktop\DCPU-emulator by MrSmith33 v0.2\clock.bin'),
      File(
          r'C:\Users\hanne\Desktop\DCPU-emulator by MrSmith33 v0.2\hwtest2.bin'),
    );

    dcpu.hardwareController.addDevice(Lem1802Device());
    dcpu.hardwareController.addDevice(GenericClock());

    fetchStats();
  }

  @override
  void dispose() {
    timer?.cancel();
    timer = null;

    super.dispose();
  }

  void reset() {
    if (timer != null) pause();

    dcpu = Dcpu();

    dcpu.hardwareController.addDevice(Lem1802Device());
    dcpu.hardwareController.addDevice(GenericClock());

    fetchStats();
  }

  void loadFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      dcpu.ram.loadFile(File(result.files.single.path!));
    } else {
      // User canceled the picker
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
      realtimeFactor =
          elapsedRealtime.inMicroseconds / elapsedCpuTime.inMicroseconds;
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
        dcpu.executeCpuTime(oneFrame);
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
    dcpu.executeCpuTime(const Duration(seconds: 1));
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
                  child: DcpuView(cpu: dcpu),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
