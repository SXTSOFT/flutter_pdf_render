import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../html.dart' as html;
import '../js_util.dart' as js_util;
import '../../web/pdf_render_web_plugin.dart';

class PdfTexture extends StatefulWidget {
  final int textureId;
  const PdfTexture({required this.textureId, Key? key}) : super(key: key);
  @override
  _PdfTextureState createState() => _PdfTextureState();

  RgbaData? get data => js_util.getProperty(html.window, 'pdf_render_texture_$textureId') as RgbaData?;

  /// Flutter Web changes [ImageDescriptor.raw](https://api.flutter.dev/flutter/dart-ui/ImageDescriptor/ImageDescriptor.raw.html)'s behavior. For more info, see the following issues:
  /// - [espresso3389/flutter_pdf_render: Web: PDF rendering distorted since Flutter Master 2.6.0-12.0.pre.674 #60](https://github.com/espresso3389/flutter_pdf_render/issues/60)
  /// - [flutter/flutter: [Web] Regression in Master - PDF display distorted due to change in BMP Encoder #93615](https://github.com/flutter/flutter/issues/93615)
  static bool get shouldEnableNewBehavior =>
      js_util.getProperty(html.window, 'workaround_for_flutter_93615') as bool? ?? false;
}

class _PdfTextureState extends State<PdfTexture> {
  ui.Image? _image;
  bool _firstBuild = true;

  @override
  void initState() {
    super.initState();
    _WebTextureManager.instance.register(widget.textureId, this);
  }

  @override
  void dispose() {
    _WebTextureManager.instance.unregister(widget.textureId, this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PdfTexture oldWidget) {
    if (oldWidget.textureId != widget.textureId) {
      _WebTextureManager.instance.unregister(oldWidget.textureId, this);
      _WebTextureManager.instance.register(widget.textureId, this);
      _image = null;
      _requestUpdate();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    if (_firstBuild) {
      _firstBuild = false;
      Future.delayed(Duration.zero, () => _requestUpdate());
    }
    return RawImage(
      image: _image,
      alignment: Alignment.topLeft,
      fit: BoxFit.fill,
    );
  }

  Future<void> _requestUpdate() async {
    final data = widget.data;
    if (data != null) {
      final descriptor = ui.ImageDescriptor.raw(
        await ui.ImmutableBuffer.fromUint8List(data.data),
        width: data.width,
        height: data.height,
        pixelFormat: PdfTexture.shouldEnableNewBehavior ? ui.PixelFormat.rgba8888 : ui.PixelFormat.bgra8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      _image = frame.image;
    } else {
      _image = null;
    }
    if (mounted) setState(() {});
  }
}

/// Receiving WebTexture update event from JS side.
class _WebTextureManager {
  static final instance = _WebTextureManager._();

  final _id2states = <int, List<_PdfTextureState>>{};
  final _events = const EventChannel('jp.espresso3389.pdf_render/web_texture_events');

  _WebTextureManager._() {
    _events.receiveBroadcastStream().listen((event) {
      if (event is int) {
        notify(event);
      }
    });
  }

  void register(int id, _PdfTextureState state) => _id2states.putIfAbsent(id, () => []).add(state);

  void unregister(int id, _PdfTextureState state) {
    final states = _id2states[id];
    if (states != null) {
      if (states.remove(state)) {
        if (states.isEmpty) {
          _id2states.remove(id);
        }
      }
    }
  }

  void notify(int id) {
    final list = _id2states[id];
    if (list != null) {
      for (final s in list) {
        s._requestUpdate();
      }
    }
  }
}
