// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:developer';
import 'dart:math' show pi;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Interface for drawing an image to warm up Skia shader compilations.
///
/// When Skia first sees a certain type of draw operation on the GPU, it needs
/// to compile the corresponding shader. The compilation can be slow (20ms-
/// 200ms). Having that time as startup latency is often better than having
/// jank in the middle of an animation.
///
/// Therefore, we use this during the [PaintingBinding.initInstances] call to
/// move common shader compilations from animation time to startup time. By
/// default, a [DefaultShaderWarmUp] is used. If needed, app developers can
/// create a custom [ShaderWarmUp] subclass and hand it to
/// [PaintingBinding.shaderWarmUp] (so it replaces [DefaultShaderWarmUp])
/// before [PaintingBinding.initInstances] is called. Usually, that can be
/// done before calling [runApp].
///
/// To determine whether a draw operation is useful for warming up shaders,
/// check the difference in the `worst_frame_rasterizer_time_millis` benchmarks.
/// Also, tracing with `flutter run --profile --trace-skia` may reveal whether
/// there is shader-compilation-related jank. If there is such jank, some long
/// `GrGLProgramBuilder::finalize` calls would appear in the middle of an
/// animation. Their parent calls, which look like `XyzOp` (e.g., `FillRecOp`,
/// `CircularRRectOp`) would suggest Xyz draw operations are causing the shaders
/// to be compiled. A useful shader warm-up draw operation would eliminate such
/// long compilation calls in the animation. To double-check the warm-up, trace
/// with `flutter run --profile --trace-skia --start-paused`. The
/// `GrGLProgramBuilder` with the associated `XyzOp` should appear during
/// startup rather than in the middle of a later animation.
///
/// This warm-up needs to be run on each individual device because the shader
/// compilation depends on the specific GPU hardware and driver a device has. It
/// can't be pre-computed during the Flutter engine compilation as the engine is
/// device-agnostic.
///
/// If no warm-up is desired (e.g., when the startup latency is crucial), set
/// [PaintingBinding.shaderWarmUp] either to a custom ShaderWarmUp with an empty
/// [warmUpOnCanvas] or null.
///
/// See also:
///
///  * [PaintingBinding.shaderWarmUp], the actual instance of [ShaderWarmUp]
///    that's used to warm up the shaders.
abstract class ShaderWarmUp {
  /// Allow const constructors for subclasses.
  const ShaderWarmUp();

  /// The size of the warm up image.
  ///
  /// The exact size shouldn't matter much as long as it's not too far away from
  /// the target device's screen. 1024x1024 is a good choice as it is within an
  /// order of magnitude of most devices.
  ///
  /// A custom shader warm up can override this based on targeted devices.
  ui.Size get size => const ui.Size(1024.0, 1024.0);

  /// Trigger draw operations on a given canvas to warm up GPU shader
  /// compilation cache.
  ///
  /// To decide which draw operations to be added to your custom warm up
  /// process, try capture an skp using `flutter screenshot --observatory-
  /// port=<port> --type=skia` and analyze it with https://debugger.skia.org.
  /// Alternatively, one may run the app with `flutter run --trace-skia` and
  /// then examine the GPU thread in the observatory timeline to see which
  /// Skia draw operations are commonly used, and which shader compilations
  /// are causing janks.
  @protected
  void warmUpOnCanvas(ui.Canvas canvas);

  /// Construct an offscreen image of [size], and execute [warmUpOnCanvas] on a
  /// canvas associated with that image.
  void execute() {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);

    warmUpOnCanvas(canvas);

    final ui.Picture picture = recorder.endRecording();
    final TimelineTask shaderWarmUpTask = TimelineTask();
    shaderWarmUpTask.start('Warm-up shader');
    picture.toImage(size.width.ceil(), size.height.ceil()).then((ui.Image image) {
      shaderWarmUpTask.finish();
    });
  }
}

/// Default way of warming up Skia shader compilations.
///
/// The draw operations being warmed up here are decided according to Flutter
/// engineers' observation and experience based on the apps and the performance
/// issues seen so far.
class DefaultShaderWarmUp extends ShaderWarmUp {
  /// Allow [DefaultShaderWarmUp] to be used as the default value of parameters.
  const DefaultShaderWarmUp();

  /// Trigger common draw operations on a canvas to warm up GPU shader
  /// compilation cache.
  @override
  void warmUpOnCanvas(ui.Canvas canvas) {
    final ui.Path rectPath = ui.Path()..addRect(ui.Rect.fromLTRB(20.0, 20.0, 60.0, 60.0));

    final ui.RRect rrect = ui.RRect.fromLTRBXY(20.0, 20.0, 60.0, 60.0, 10.0, 10.0);
    final ui.Path rrectPath = ui.Path()..addRRect(rrect);

    final ui.Path circlePath = ui.Path()..addOval(
        ui.Rect.fromCircle(center: const ui.Offset(40.0, 40.0), radius: 20.0)
    );

    // The following path is based on
    // https://skia.org/user/api/SkCanvas_Reference#SkCanvas_drawPath
    final ui.Path path = ui.Path();
    path.moveTo(20.0, 60.0);
    path.quadraticBezierTo(60.0, 20.0, 60.0, 60.0);
    path.close();
    path.moveTo(60.0, 20.0);
    path.quadraticBezierTo(60.0, 60.0, 20.0, 60.0);

    final ui.Path convexPath = ui.Path();
    convexPath.moveTo(20.0, 30.0);
    convexPath.lineTo(40.0, 20.0);
    convexPath.lineTo(60.0, 30.0);
    convexPath.lineTo(60.0, 60.0);
    convexPath.lineTo(20.0, 60.0);
    convexPath.close();

    // Skia uses different shaders based on the kinds of paths being drawn and
    // the associated paint configurations. According to our experience and
    // tracing, drawing the following paths/paints generates various of
    // shaders that are commonly used.
    final List<ui.Path> paths = <ui.Path>[rectPath, rrectPath, circlePath, path, convexPath];

    final List<ui.Paint> paints = <ui.Paint>[
      ui.Paint()
        ..isAntiAlias = true
        ..style = ui.PaintingStyle.fill,
      ui.Paint()
        ..isAntiAlias = false
        ..style = ui.PaintingStyle.fill,
      ui.Paint()
        ..isAntiAlias = true
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 10,
      ui.Paint()
        ..isAntiAlias = true
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 0.1  // hairline
    ];

    // Warm up path stroke and fill shaders.
    for (int i = 0; i < paths.length; i += 1) {
      canvas.save();
      for (ui.Paint paint in paints) {
        canvas.drawPath(paths[i], paint);
        canvas.translate(80.0, 0.0);
      }
      canvas.restore();
      canvas.translate(0.0, 80.0);
    }

    // Warm up shadow shaders.
    const ui.Color black = ui.Color(0xFF000000);
    canvas.save();
    canvas.drawShadow(rectPath, black, 10.0, true);
    canvas.translate(80.0, 0.0);
    canvas.drawShadow(rectPath, black, 10.0, false);
    canvas.translate(80.0, 0.0);
    canvas.drawShadow(rrectPath, black, 10.0, true);
    canvas.translate(80.0, 0.0);
    canvas.drawShadow(rrectPath, black, 10.0, false);
    canvas.restore();

    // [BoxShadow] draws a blurred rect, sometimes at an angle
    canvas.translate(0.0, 80.0);
    canvas.save();
    for (double rotation in <double>[.0, pi / 4]) {
      canvas.save();
      canvas.rotate(rotation);
      final ui.Paint blurPaint = ui.Paint()
        ..color = const ui.Color(0x7F000000)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4.0);
      canvas.drawRect(ui.Rect.fromLTRB(20.0, 20.0, 60.0, 30.0), blurPaint);
      canvas.drawRect(ui.Rect.fromLTRB(20.0, 40.0, 60.0, 50.0), paints[0]);
      canvas.drawRect(ui.Rect.fromLTRB(20.0, 60.0, 50.0, 70.0), paints[1]);
      canvas.restore();
      canvas.translate(80.0, 0.0);
    }
    canvas.restore();

    // Warm up text shaders.
    canvas.translate(0.0, 80.0);
    final ui.ParagraphBuilder paragraphBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(textDirection: ui.TextDirection.ltr),
    )..pushStyle(ui.TextStyle(color: black))..addText('_');
    final ui.Paragraph paragraph = paragraphBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: 60.0));
    canvas.drawParagraph(paragraph, const ui.Offset(20.0, 20.0));
  }
}
