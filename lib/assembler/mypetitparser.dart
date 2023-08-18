import 'dart:math';

import 'package:petitparser/petitparser.dart';

class MyContext implements Context {
  const MyContext(
    this.buffer,
    this.position, {
    required this.fileName,
  });

  final String fileName;

  @override
  final String buffer;

  @override
  final int position;

  @override
  MyFailure<R> failure<R>(String message, [int? position]) {
    return MyFailure(
      buffer,
      position ?? this.position,
      message,
      fileName: fileName,
    );
  }

  @override
  MySuccess<R> success<R>(R result, [int? position]) {
    return MySuccess(
      buffer,
      position ?? this.position,
      result,
      fileName: fileName,
    );
  }

  @override
  String toPositionString() => MyToken.positionString(buffer, position);

  @override
  String toString() => 'FileContext[${toPositionString()}]';
}

sealed class MyResult<R> extends MyContext implements Result<R> {
  const MyResult(
    super.buffer,
    super.position, {
    required super.fileName,
  });

  @override
  bool get isFailure => false;

  @override
  bool get isSuccess => false;

  @override
  String get message;

  @override
  R get value;
}

class MySuccess<R> extends MyResult<R> implements Success<R> {
  const MySuccess(
    super.buffer,
    super.position,
    this.value, {
    required super.fileName,
  });

  @override
  bool get isSuccess => true;

  @override
  final R value;

  @override
  String get message => throw UnsupportedError('Successful parse results do not have a message.');

  @override
  String toString() => 'Success[${toPositionString()}]: $value';
}

class MyFailure<R> extends MyResult<R> implements Failure<R> {
  const MyFailure(
    super.buffer,
    super.position,
    this.message, {
    required super.fileName,
  });

  @override
  bool get isFailure => true;

  @override
  R get value => throw ParserException(this);

  @override
  final String message;

  @override
  String toString() => 'Failure[${toPositionString()}]: $message';
}

class ContextPreservingTrimmingParser<R> extends DelegateParser<R, R> implements TrimmingParser<R> {
  ContextPreservingTrimmingParser(super.delegate, this.left, this.right);

  /// Parser that consumes input before the delegate.
  @override
  Parser<void> left;

  /// Parser that consumes input after the delegate.
  @override
  Parser<void> right;

  @override
  Result<R> parseOn(Context context) {
    // Trim the left part:
    context = _trim(left, context);

    // Consume the delegate:
    final result = delegate.parseOn(context);
    if (result.isFailure) {
      return result;
    }

    // Trim the right part:
    final after = _trim(right, result);
    return after == result ? result : result.success(result.value, after.position);
  }

  @override
  int fastParseOn(String buffer, int position) {
    throw UnimplementedError();
  }

  Context _trim(Parser parser, Context context) {
    for (;;) {
      final result = parser.parseOn(context);
      if (result.isFailure) {
        break;
      }

      context = context.success(result.value, result.position);
    }

    return context;
  }

  @override
  ContextPreservingTrimmingParser<R> copy() => ContextPreservingTrimmingParser<R>(delegate, left, right);

  @override
  List<Parser> get children => [delegate, left, right];

  @override
  void replace(covariant Parser source, covariant Parser target) {
    super.replace(source, target);
    if (left == source) {
      left = target;
    }
    if (right == source) {
      right = target;
    }
  }
}

extension ContextPreservingTrimmingParserExtension<R> on Parser<R> {
  Parser<R> trimPreserve([Parser<void>? left, Parser<void>? right]) {
    return ContextPreservingTrimmingParser(
      this,
      left ?? whitespace(),
      right ?? left ?? whitespace(),
    );
  }
}

class MyTokenParser<R> extends DelegateParser<R, MyToken<R>> {
  MyTokenParser(super.delegate);

  @override
  Result<MyToken<R>> parseOn(Context context) {
    final result = delegate.parseOn(context);
    if (result.isSuccess) {
      final token = MyToken<R>(
        result.value,
        buffer: context.buffer,
        start: context.position,
        stop: result.position,
        fileName: (result as MyResult).fileName,
      );
      return result.success(token);
    } else {
      return result.failure(result.message);
    }
  }

  @override
  int fastParseOn(String buffer, int position) => delegate.fastParseOn(buffer, position);

  @override
  MyTokenParser<R> copy() => MyTokenParser<R>(delegate);
}

extension MyTokenParserExtension<R> on Parser<R> {
  Parser<MyToken<R>> dasmToken() => MyTokenParser<R>(this);
}

class SomeOfParser<R> extends ListParser<R, List<R?>> {
  SomeOfParser(super.children, {FailureJoiner<R>? failureJoiner}) : failureJoiner = failureJoiner ?? selectFarthest;

  FailureJoiner<R> failureJoiner;

  @override
  SomeOfParser<R> copy() {
    return SomeOfParser(children.toList());
  }

  @override
  Result<List<R?>> parseOn(Context context) {
    final results = [
      for (final child in children) child.parseOn(context),
    ];

    if (results.every((element) => element.isFailure)) {
      final result = results.cast<Failure<R>>().reduce(failureJoiner);
      return result.failure(result.message);
    }

    final succeeded = results.whereType<Success>();

    if (succeeded.skip(1).any((element) => element.position != succeeded.first.position)) {
      return context.failure('Ambigous anyOf continuation');
    }

    final list = results.map((e) {
      if (e case Success(:final value)) {
        return value;
      } else {
        return null;
      }
    }).toList();

    return context.success(list, succeeded.first.position);
  }
}

class MyToken<T> extends Token<T> {
  const MyToken(
    T value, {
    required String buffer,
    required int start,
    required int stop,
    required this.fileName,
  })  : virtual = false,
        super(value, buffer, start, stop);

  const MyToken.virtual(
    T value, {
    required String buffer,
    required int start,
    required int stop,
    required this.fileName,
  })  : virtual = true,
        super(value, buffer, start, stop);

  final bool virtual;
  final String fileName;

  static (int, int) lineAndColumnOf(String buffer, int position) {
    final [line, column] = Token.lineAndColumnOf(buffer, position);
    return (line, column);
  }

  static String positionString(String buffer, int position) {
    return Token.positionString(buffer, position);
  }
}

extension TokenMap<T> on Parser<Token<T>> {
  Parser<Token<R>> mapToken<R>(R Function(T) fn) {
    return map<Token<R>>((token) {
      return Token<R>(
        fn(token.value),
        token.buffer,
        token.start,
        token.stop,
      );
    });
  }
}

extension MyTokenMap<T> on Parser<MyToken<T>> {
  Parser<MyToken<R>> mapToken<R>(R Function(T) fn) {
    return map<MyToken<R>>((token) {
      return MyToken<R>(
        fn(token.value),
        buffer: token.buffer,
        start: token.start,
        stop: token.stop,
        fileName: token.fileName,
      );
    });
  }
}

class Location {
  Location(this.sourceFile, this.buffer, this.start, this.end);

  Location.fromToken(MyToken token)
      : sourceFile = token.fileName,
        buffer = token.buffer,
        start = token.start,
        end = token.stop;

  Location.coverLocations(Iterable<Location> locations)
      : assert(locations.isNotEmpty),
        assert(
          locations.skip(1).every(
                (token) => token.buffer == locations.first.buffer && token.sourceFile == locations.first.sourceFile,
              ),
        ),
        sourceFile = locations.first.sourceFile,
        buffer = locations.first.buffer,
        start = locations.map((token) => token.start).reduce(min),
        end = locations.map((token) => token.end).reduce(max);

  Location.coverTokens(Iterable<MyToken> tokens)
      : assert(tokens.isNotEmpty),
        assert(
          tokens
              .skip(1)
              .every((token) => token.buffer == tokens.first.buffer && token.fileName == tokens.first.fileName),
        ),
        sourceFile = tokens.first.fileName,
        buffer = tokens.first.buffer,
        start = tokens.map((token) => token.start).reduce(min),
        end = tokens.map((token) => token.stop).reduce(max);

  final String sourceFile;
  final String buffer;
  final int start;
  final int end;
  late final String text = buffer.substring(start, end);

  static (int, int) lineAndColumnOf(String buffer, int position) {
    return MyToken.lineAndColumnOf(buffer, position);
  }

  static String positionString(String buffer, int position) {
    final (line, column) = lineAndColumnOf(buffer, position);
    return '$line:$column';
  }

  @override
  String toString() => '$sourceFile:${positionString(buffer, start)}';
}
