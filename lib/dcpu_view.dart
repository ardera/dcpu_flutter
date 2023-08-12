import 'package:flutter/material.dart';

import 'core/cpu.dart';
import 'peripherals/lem1802.dart' as lem;

class LEM1802Painter extends CustomPainter {
  LEM1802Painter({
    required this.framebuffer,
    required this.font,
    required this.palette,
    required this.borderColorIndex,
    required this.enabled,
    required this.blinkOn,
    required this.showSplash,
    super.repaint,
  });

  final lem.Framebuffer framebuffer;
  final lem.Font font;
  final lem.Palette palette;
  final int borderColorIndex;
  final bool enabled;
  final bool blinkOn;
  final bool showSplash;

  static const lemSize = Size(
    lem.Framebuffer.width * lem.Glyph.width + borderWidth * 2,
    lem.Framebuffer.height * lem.Glyph.height + borderWidth * 2,
  );

  static const lemVideoSize = Size(
    lem.Framebuffer.width * lem.Glyph.width + 0.0,
    lem.Framebuffer.height * lem.Glyph.height + 0.0,
  );

  static const cellSize = Size(
    lem.Glyph.width + 0.0,
    lem.Glyph.height + 0.0,
  );

  static const pixelSize = Size(1, 1);

  static const borderWidth = 5.0;

  void paintScaled(Canvas canvas) {
    final borderPath = Path()
      ..addRect(Offset.zero & lemSize)
      ..addRect(const Offset(borderWidth, borderWidth) & lemVideoSize);

    final borderColor = palette.getColor(borderColorIndex).getColor();

    canvas.drawPath(
      borderPath,
      Paint()..color = borderColor,
    );

    canvas.save();
    canvas.translate(borderWidth, borderWidth);

    for (var cellY = 0; cellY < lem.Framebuffer.height; cellY++) {
      for (var cellX = 0; cellX < lem.Framebuffer.width; cellX++) {
        final cellOffset = Offset(
          cellSize.width * cellX,
          cellSize.height * cellY,
        );

        final cell = framebuffer.getCell(cellX, cellY);

        for (var pixelY = 0; pixelY < lem.Glyph.height; pixelY++) {
          for (var pixelX = 0; pixelX < lem.Glyph.width; pixelX++) {
            final pixelOffset = cellOffset +
                Offset(
                  pixelSize.width * pixelX,
                  pixelSize.height * pixelY,
                );

            final character = cell.character();
            final glyph = font.glyphFor(character);

            late int colorIndex;
            if (glyph.isForeground(pixelX, pixelY) &&
                (!cell.blink() || blinkOn)) {
              colorIndex = cell.foregroundColorIndex();
            } else {
              colorIndex = cell.backgroundColorIndex();
            }

            final color = palette.getColor(colorIndex).getColor();

            final paint = Paint()
              ..color = color
              ..style = PaintingStyle.fill
              ..isAntiAlias = false;

            canvas.drawRect(pixelOffset & pixelSize, paint);
          }
        }
      }
    }

    canvas.restore();
  }

  void paintOfflineScaled(Canvas canvas) {
    final rect = Offset.zero & lemSize;

    canvas.drawRect(
      rect,
      Paint()..color = Colors.black,
    );
  }

  void paintSplashScaled(Canvas canvas) {
    final rect = Offset.zero & lemSize;

    canvas.drawRect(
      rect,
      Paint()..color = const Color.fromARGB(255, 0, 0, 255),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.transform(
      Matrix4.diagonal3Values(
        size.width / lemSize.width,
        size.height / lemSize.height,
        1,
      ).storage,
    );

    if (!enabled) {
      paintOfflineScaled(canvas);
    } else if (showSplash) {
      paintSplashScaled(canvas);
    } else {
      paintScaled(canvas);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LEM1802Painter oldDelegate) {
    return oldDelegate.framebuffer != framebuffer ||
        oldDelegate.font != font ||
        oldDelegate.palette != palette ||
        oldDelegate.borderColorIndex != borderColorIndex ||
        oldDelegate.enabled != enabled ||
        oldDelegate.blinkOn != blinkOn ||
        oldDelegate.showSplash != showSplash;
  }
}

class LEM1802View extends StatefulWidget {
  const LEM1802View({
    required this.lem1802,
    Key? key,
  }) : super(key: key);

  final lem.Lem1802Device lem1802;

  @override
  State<LEM1802View> createState() => _LEM1802ViewState();
}

class _LEM1802ViewState extends State<LEM1802View> {
  late Listenable mergedListenable;

  @override
  void initState() {
    super.initState();

    mergedListenable = Listenable.merge([
      widget.lem1802.framebuffer,
      widget.lem1802.font,
      widget.lem1802.palette
    ]);
  }

  @override
  void didUpdateWidget(covariant LEM1802View oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.lem1802 != oldWidget.lem1802) {
      mergedListenable = Listenable.merge([
        widget.lem1802.framebuffer,
        widget.lem1802.font,
        widget.lem1802.palette
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: LEM1802Painter.lemSize.aspectRatio,
      child: AnimatedBuilder(
        animation: widget.lem1802,
        builder: (context, child) {
          return CustomPaint(
            painter: LEM1802Painter(
              framebuffer: widget.lem1802.framebuffer,
              font: widget.lem1802.font,
              palette: widget.lem1802.palette,
              borderColorIndex: widget.lem1802.borderColorIndex,
              enabled: widget.lem1802.enabled,
              blinkOn: widget.lem1802.blinkOn,
              showSplash: widget.lem1802.showSplash,
              repaint: mergedListenable,
            ),
          );
        },
      ),
    );
  }
}

class DcpuView extends StatelessWidget {
  const DcpuView({required this.cpu, Key? key}) : super(key: key);

  final Dcpu cpu;

  @override
  Widget build(BuildContext context) {
    final dev = cpu.hardwareController.findDevice<lem.Lem1802Device>();
    if (dev == null) {
      return Container();
    }

    return LEM1802View(lem1802: dev);
  }
}
