import 'dart:io';

import 'package:dcpu_flutter/assembler/assembler.dart';
import 'package:logging/logging.dart';

void main(List<String> args) {
  final logger = Logger.root;
  logger.level = Level.FINE;

  logger.onRecord.forEach((record) {
    // ignore: avoid_print
    print(record);
  });

  final assembler = Assembler();

  final bytes = assembler.assemble(
    args.first,
    File(args.first),
    [Directory.current],
  );

  final output = File('a.out');
  output.writeAsBytesSync(bytes);
}
