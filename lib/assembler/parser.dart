import 'package:dcpu_flutter/assembler/assembler.dart';
import 'package:dcpu_flutter/assembler/ast.dart';
import 'package:dcpu_flutter/assembler/mypetitparser.dart';
import 'package:dcpu_flutter/core/cpu.dart';
import 'package:petitparser/petitparser.dart';

class Dasm16ParserDefinition extends GrammarDefinition {
  Dasm16ParserDefinition({this.features = FeatureFlags.def});

  final FeatureFlags features;

  @override
  Parser<AssemblyFile> start() {
    return file;
  }

  Parser<R> seq2PickFirst<R>(Parser<R> first, Parser second) {
    return seq2(first, second).map2((a, b) => a);
  }

  Parser<R> seq2PickSecond<R>(Parser first, Parser<R> second) {
    return seq2(first, second).map2((a, b) => b);
  }

  late final file = seq2PickFirst(
    line.star().map((line) => line.expand((nodes) => nodes).toList()),
    endOfInput() | line,
  ).map((nodes) => AssemblyFile(nodes));

  late final line = ChoiceParser(
    <Parser>[
      labelLine,
      macroDefinitionLine,
      pseudoInstructionLine,
      instructionOrMacroInvocationLine,
      emptyLine,
    ],
    failureJoiner: selectFarthest,
  ).map((value) {
    if (value case TopLevelASTNode node) {
      return [node];
    } else if (value case List<TopLevelASTNode> list) {
      return list;
    } else if (value case null) {
      return <TopLevelASTNode>[];
    } else {
      throw ArgumentError.value(value, 'value');
    }
  }).labeled('line');

  late final macroDefinitionLine = seq6(
    dotToken,
    directiveNameToken.where(
      (value) => value.value.toLowerCase() == 'macro',
    ),
    identifier,
    equalsToken,
    newline().neg().plus().flatten().dasmToken(),
    newline(),
  ).map6((_, __, name, equals, contents, ___) {
    return MacroDefinition(name, equals, contents);
  }).labeled('macro definition line');

  late final pseudoInstructionLine = seq3(
    labelDeclaration.optional(),
    pseudoInstruction,
    newline('Unexpected character'),
  ).map((values) {
    return [
      if (values.first != null) values.first!,
      values.second,
    ];
  }).labeled('pseudo instruction line');

  late final pseudoInstruction = seq3(
    dotToken,
    directiveNameToken,
    pseudoInstructionArgs,
  ).map((values) {
    return DotInstruction(values.first, values.second, values.third);
  });

  late final pseudoInstructionArgs = pseudoInstructionArg.plusSeparated(commaToken);

  late final pseudoInstructionArg = ChoiceParser([
    packedString,
    SomeOfParser([
      identifier,
      term,
    ]).map((values) {
      return DotInstrArg.nameOrTerm(
        values[0] as MyToken<String>?,
        values[1] as Term?,
      );
    })
  ]);

  late final packedString = seq3(
    ChoiceParser([
      anyOf('kK').map((_) => StringPackingFlag.packed).dasmToken(),
      anyOf('sS').map((_) => StringPackingFlag.swapped).dasmToken(),
      anyOf('zZ').map((_) => StringPackingFlag.zeroZerminate).dasmToken(),
      anyOf('xX').map((_) => StringPackingFlag.wordZeroTerminate).dasmToken(),
      anyOf('aA').map((_) => StringPackingFlag.octetPascalLength).dasmToken(),
      anyOf('pP').map((_) => StringPackingFlag.wordPascalLength).dasmToken(),
    ]).star(),
    ((hexNumber | decimalNumber).flatten().map(int.parse)).dasmToken().optional(),
    seq3(
      char('"'),
      (char('\\').not() & char('"')).neg().star().flatten(),
      char('"'),
    ).map3((_, str, __) => str).dasmToken(),
  ).map3(DotInstrArg.string).trimPreserve(space);

  late final labelLine = seq2PickFirst(
    labelDeclaration,
    newline('Unexpected character'),
  ).map((value) => [value]);

  late final instructionOrMacroInvocationLine = seq3(
    labelDeclaration.optional(),
    instructionOrMacroInvocation,
    newline('Unexpected character'),
  ).map((values) {
    return [
      if (values.first != null) values.first!,
      values.second,
    ];
  }).labeled('instruction or macro invocation line');

  late final instructionOrMacroInvocation = SomeOfParser(
    <Parser<TopLevelASTNode>>[instruction, macroInvocation],
    failureJoiner: selectFarthest,
  ).map<TopLevelASTNode>((value) {
    final first = value[0] as Instruction?;
    final second = value[1] as MacroInvocation?;

    if (first != null && second != null) {
      return InstructionOrMacroInvocation(first, second);
    } else if (first != null) {
      return first;
    } else if (second != null) {
      return second;
    } else {
      throw ArgumentError.value(value, 'value');
    }
  });

  late final macroInvocation = seq2(
    identifier,
    ChoiceParser([term, arg]).starSeparated(commaToken),
  ).map2((name, args) => MacroInvocation(name));

  late final emptyLine =
      seq2(space.star(), newline('Unexpected character')).map((_) => <TopLevelASTNode>[]).labeled('empty line');

  late final labelDeclaration = ChoiceParser([
    seq2(labelSign, labelName).map2(
      (sign, name) => LabelDeclaration(sign, name),
    ),
    seq2(labelName, labelSign).map2(
      (name, sign) => LabelDeclaration(sign, name),
    )
  ]);

  late final labelSign = colonToken;
  late final labelName = labelNameToken.map((token) => LabelName(token));

  late final instruction = seq2(instructionName, instructionArgs).map2(
    (name, args) {
      return Instruction(
        mnemonic: name,
        argB: args.$1,
        argA: args.$2,
      );
    },
  ).labeled('instruction');

  late final instructionName = mnemonicToken.labeled('instruction name');

  late final instructionArgs = seq2(arg, seq2PickSecond(commaToken, arg).optional()).map2((first, second) {
    if (second == null) {
      return (null, second ?? first);
    } else {
      return (first, second);
    }
  }).labeled('instruction arguments');

  late final indirectArg = seq3(
    openBracketToken,
    ref0(() => arg),
    closeBracketToken,
  ).map3(InstructionArg.indirect).labeled('indirect arg');

  late final Parser<InstructionArg> arg = ChoiceParser<InstructionArg>(
    [
      pushArg,
      minusMinusSpArg,
      popArg,
      spPlusPlusArg,
      peekArg,
      pickArg,
      registerOffsetArg,
      registerArg,
      immediateArg,
      indirectArg
    ],
    failureJoiner: selectFarthest,
  ).labeled('instruction argument');

  late final registerOffsetArg = seq3(registerName, binOp, term).map3(InstructionArg.registerOffset);

  late final registerArg = registerName.map(InstructionArg.register);

  late final pushArg = pushToken.map(InstructionArg.push);

  late final minusMinusSpArg = seq2(minusMinusToken, spToken).map2(InstructionArg.minusMinusSp);

  late final popArg = popToken.map(InstructionArg.pop);

  late final spPlusPlusArg = seq2(spToken, plusPlusToken).map2(InstructionArg.spPlusPlus);

  late final peekArg = peekToken.map(InstructionArg.peek);

  late final pickArg = seq2(pickToken, term).map2(InstructionArg.pick);

  late final immediateArg = term;

  static const _registerNames = {
    'A': Register.a,
    'B': Register.b,
    'C': Register.c,
    'X': Register.x,
    'Y': Register.y,
    'Z': Register.z,
    'I': Register.i,
    'J': Register.j,
    'PC': Register.pc,
    'SP': Register.sp,
    'EX': Register.ex
  };

  late final registerName = identifier.where((token) {
    return _registerNames.containsKey(token.value.toUpperCase());
  }).mapToken(
    (value) => _registerNames[value.toUpperCase()]!,
  );

  late final Parser<Term> term = ChoiceParser([
    seq3(
      atomicTerm,
      binOp,
      ref0(() => term),
    ).map3(Term.binOp),
    seq2(
      unaryOp,
      ref0(() => term),
    ).map2(Term.unaryOp),
    atomicTerm,
  ]);
  late final atomicTerm = ChoiceParser([numberTerm, labelTerm]);
  late final numberTerm = numberToken.map(Term.literal);
  late final labelTerm = labelName.map(Term.label);

  late final binOp = ChoiceParser([add, sub, bitwiseOr]).labeled('binary operation');
  late final add = plusToken.mapToken((value) => BinOp.add);
  late final sub = minusToken.mapToken((value) => BinOp.sub);
  late final bitwiseOr = pipeToken.mapToken((value) => BinOp.bitwiseOr);

  late final unaryOp = unaryMinus;
  late final unaryMinus = minusToken.mapToken((_) => UnaryOp.minus);

  late final space = char(' ') | char('\t') | commentSingle;
  late final commentSingle = char(';') & newline().neg().star();

  Parser<MyToken<R>> nonFlattenToken<R>(
    Parser<R> parser, {
    String? failureMessage,
    String? label,
  }) {
    if (failureMessage != null) {
      parser = parser.callCC((continuation, context) {
        var result = continuation(context);

        // map the error message
        if (result is Failure) {
          result = result.failure(failureMessage, result.position);
        }

        return result;
      });
    }

    var tokenParser = parser.dasmToken().trimPreserve(space);

    if (label != null) {
      tokenParser = tokenParser.labeled(label);
    }

    return tokenParser;
  }

  Parser<MyToken<String>> token(
    Parser parser, {
    String? failureMessage,
    String? label,
  }) {
    var stringParser = parser.flatten();

    if (failureMessage != null) {
      stringParser = stringParser.callCC((continuation, context) {
        var result = continuation(context);

        // map the error message
        if (result is Failure) {
          result = result.failure(failureMessage, result.position);
        }

        return result;
      });
    }

    var tokenParser = stringParser.dasmToken().trimPreserve(space);

    if (label != null) {
      tokenParser = tokenParser.labeled(label);
    }

    return tokenParser;
  }

  Parser<MyToken<String>> patternToken(
    String pattern, {
    String? failureMessage,
    String? label,
  }) {
    var stringParser = pattern.toParser().flatten();

    if (failureMessage != null) {
      stringParser = stringParser.callCC((continuation, context) {
        var result = continuation(context);

        // map the error message
        if (result is Failure) {
          result = result.failure(failureMessage, result.position);
        }

        return result;
      });
    }

    var tokenParser = stringParser.dasmToken().trimPreserve(space);

    if (label != null) {
      tokenParser = tokenParser.labeled(label);
    }

    return tokenParser;
  }

  late final numberToken = token(
    hexNumber | decimalNumber,
    failureMessage: 'Number expected',
    label: 'number',
  ).mapToken(int.parse);

  late final hexNumber = string('0x') & pattern('0-9a-fA-F').plus();
  late final decimalNumber = digit().plus();

  late final mnemonicToken = token(
    pattern('a-zA-Z').star() & pattern('0-9._').not('Invalid opcode character'),
    failureMessage: 'Opcode mnemonic expected',
  );

  late final identifierStartChar = pattern('0-9.')
      .not('Identifiers can\'t start with a dot, underscore or decimal digit.')
      .and()
      .seq(identifierMidChar);

  late final identifierMidChar = pattern('a-zA-Z0-9._');

  late final identifierEndChar = char('.').not('Identifiers cant end with a dot.').and().seq(identifierMidChar);

  late final identifier = token(
    identifierStartChar.and() &
        identifierMidChar.starLazy(
          identifierMidChar.optional() & identifierMidChar.not(),
        ) &
        identifierEndChar,
    label: 'identifier token',
  );

  late final labelNameToken = identifier;

  late final directiveNameToken = token(
    pattern('a-zA-Z')
            .plus()
            .flatten('Invalid character in pseudo instruction. Pseudo instructions must be alphabetic.') &
        pattern('0-9_.').not('Invalid character in pseudo instruction. Pseudo instructions must be alphabetic.'),
  );

  late final spToken = token(
    stringIgnoreCase('SP') & pattern('0-9a-zA-Z_.').not(),
    failureMessage: 'SP expected',
    label: 'SP',
  );

  late final openBracketToken = patternToken('[');

  late final closeBracketToken = patternToken(']');

  late final commaToken = patternToken(',');

  late final plusPlusToken = patternToken('++');
  late final minusMinusToken = patternToken('--');

  late final plusToken = token(char('+') & char('+').not());
  late final minusToken = token(char('-') & char('-').not());
  late final pipeToken = token(char('|') & char('|').not());

  late final dotToken = patternToken('.');
  late final numberSignToken = patternToken('#');

  late final colonToken = patternToken(':');

  late final stringToken = nonFlattenToken(
    seq3(char('"'), char('"').neg().star().flatten(), char('"')).map3((_, str, __) => str),
    failureMessage: 'String expected',
    label: 'string',
  );

  late final peekToken = token(
    stringIgnoreCase('PEEK'),
    failureMessage: 'PEEK expected',
    label: 'PEEK',
  );

  late final pickToken = token(
    stringIgnoreCase('PICK'),
    failureMessage: 'PICK expected',
    label: 'PICK',
  );

  late final pushToken = token(
    stringIgnoreCase('PUSH'),
    failureMessage: 'PUSH expected',
    label: 'PUSH',
  );

  late final popToken = token(
    stringIgnoreCase('POP'),
    failureMessage: 'POP expected',
    label: 'POP',
  );

  late final equalsToken = token(
    char('=') & char('=').not(),
  );
}
