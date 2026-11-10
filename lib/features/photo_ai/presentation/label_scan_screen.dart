import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/result.dart';
import '../../../core/platform/status_bar.dart';
import '../../../l10n/app_localizations.dart';
import '../../wardrobe/application/photo_providers.dart';
import '../../wardrobe/data/photo_processor.dart';
import '../../wardrobe/domain/photo_picker.dart';
import '../application/label_camera.dart';
import '../domain/label_auto_shutter.dart';
import '../domain/photo_reader.dart';
import 'photo_read_messages.dart';

/// "Ler etiqueta": a câmara ao vivo no meio, os passos por cima e até 3
/// fotos da mesma etiqueta. Fecha com a leitura (só sugestões; o formulário
/// mostra-as para confirmar). As fotos não ficam guardadas.
class LabelScanScreen extends ConsumerStatefulWidget {
  const LabelScanScreen({required this.reader, super.key});

  final PhotoReader reader;

  @override
  ConsumerState<LabelScanScreen> createState() => _LabelScanScreenState();
}

class _LabelScanScreenState extends ConsumerState<LabelScanScreen> {
  late final LabelCamera _camera = ref.read(labelCameraProvider)();

  /// `null` enquanto abre.
  bool? _cameraReady;
  final _photos = <Uint8List>[];
  bool _busy = false;
  bool _reading = false;
  String? _message;

  /// Disparo automático: a foto tira-se e lê-se sozinha quando a imagem
  /// está nítida e parada. Só existe onde a câmara dá a sonda.
  static const _autoMaxReads = 3;
  final _shutter = LabelAutoShutter();
  Timer? _autoTimer;
  bool _autoAvailable = false;
  bool _autoOn = true;
  bool _autoBusy = false;
  int _autoReads = 0;
  AutoShutterState _autoState = AutoShutterState.searching;

  bool get _autoActive =>
      _autoAvailable && _autoOn && _autoReads < _autoMaxReads;

  @override
  void initState() {
    super.initState();
    setStatusBarOverride(Colors.black);
    _camera.open().then((ok) {
      if (!mounted) return;
      setState(() => _cameraReady = ok);
      if (ok) {
        _autoTimer = Timer.periodic(
          const Duration(milliseconds: 350),
          (_) => _autoTick(),
        );
      }
    });
  }

  @override
  void dispose() {
    setStatusBarOverride(null);
    _autoTimer?.cancel();
    _camera.close();
    super.dispose();
  }

  bool get _full => _photos.length >= maxLabelPhotos;

  Future<void> _autoTick() async {
    if (!mounted || _autoBusy || _busy || _reading) return;
    if (!_autoOn || _autoReads >= _autoMaxReads || _photos.isNotEmpty) return;
    final probe = _camera.probe();
    if (probe == null) return;
    final state = _shutter.add(probe);
    if (!_autoAvailable || state != _autoState) {
      setState(() {
        _autoAvailable = true;
        _autoState = state;
      });
    }
    if (state != AutoShutterState.fire) return;
    _autoBusy = true;
    try {
      _autoReads++;
      await _capture();
      if (!mounted || _photos.isEmpty) return;
      await _read();
      if (!mounted) return;
      // Não serviu: só tenta outra vez depois de a câmara se mexer.
      _shutter.rearmAfterMove();
      setState(() {
        _autoState = AutoShutterState.searching;
        if (_autoReads >= _autoMaxReads && _photos.isEmpty) {
          _message = AppLocalizations.of(context).labelScanAutoGaveUp;
        }
      });
    } finally {
      _autoBusy = false;
    }
  }

  Future<void> _capture() async {
    final l10n = AppLocalizations.of(context);
    if (_full) {
      setState(() => _message = l10n.labelScanFull);
      return;
    }
    setState(() => _busy = true);
    try {
      final Uint8List? input;
      try {
        input = _cameraReady == true
            ? await _camera.capture()
            : await ref.read(photoPickerProvider).pick(PhotoSource.camera);
      } on Object {
        setState(() => _message = l10n.photoPickFailed);
        return;
      }
      await _add(input);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _gallery() async {
    final l10n = AppLocalizations.of(context);
    if (_full) {
      setState(() => _message = l10n.labelScanFull);
      return;
    }
    setState(() => _busy = true);
    try {
      final List<Uint8List> inputs;
      try {
        inputs = await ref
            .read(photoPickerProvider)
            .pickMany(limit: maxLabelPhotos - _photos.length);
      } on Object {
        setState(() => _message = l10n.photoPickFailed);
        return;
      }
      for (final input in inputs) {
        if (!mounted || !await _add(input)) break;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Reduz como as outras fotos (sem metadados) e junta à lista.
  Future<bool> _add(Uint8List? input) async {
    if (input == null || !mounted) return false;
    final l10n = AppLocalizations.of(context);
    final processed = await ref.read(photoProcessorProvider)(input);
    if (!mounted) return false;
    switch (processed) {
      case Err(failure: final problem):
        setState(
          () => _message = switch (problem) {
            PhotoProblem.heic => l10n.photoHeic,
            PhotoProblem.unsupportedFormat => l10n.photoUnsupported,
            PhotoProblem.tooLarge => l10n.photoTooLarge,
          },
        );
        return false;
      case Ok(value: final photo):
        setState(() {
          if (!_full) _photos.add(photo.main);
          _message = null;
        });
        return true;
    }
  }

  Future<void> _read() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _reading = true;
      _message = null;
    });
    Result<LabelReading, PhotoReadFailure> result;
    try {
      result = await widget.reader.readLabel(List.of(_photos));
    } on Object {
      result = const Err(PhotoReadFailure.failed);
    }
    if (!mounted) return;
    setState(() => _reading = false);
    switch (result) {
      case Err(:final failure):
        setState(() => _message = photoReadMessage(l10n, failure));
      case Ok(value: final label) when label.found == LabelFound.otherLabel:
        // Fotos da coisa errada: começa de novo.
        setState(() {
          _photos.clear();
          _message = l10n.labelScanOther;
        });
      case Ok(value: final label) when label.found == LabelFound.notLabel:
        setState(() {
          _photos.clear();
          _message = l10n.labelScanNotLabel;
        });
      case Ok(value: final label) when label.isEmpty:
        setState(
          () => _message = label.found == LabelFound.careLabel
              ? l10n.labelScanUnreadable
              : l10n.garmentLabelEmpty,
        );
      case Ok(value: final label):
        Navigator.of(context).pop(label);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    const onDark = Colors.white;
    final locked = _busy || _reading;
    return Theme(
      // Ecrã de câmara: sempre escuro, com as cores da app.
      data: theme.copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: theme.colorScheme.primary,
          brightness: Brightness.dark,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: onDark,
          iconTheme: const IconThemeData(color: onDark),
          titleTextStyle:
              (theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge)
                  ?.copyWith(color: onDark),
          title: Text(l10n.labelScanTitle),
          actions: [
            if (_autoAvailable)
              IconButton(
                key: const Key('label-scan-auto'),
                tooltip: _autoOn ? l10n.labelScanAutoOn : l10n.labelScanAutoOff,
                isSelected: _autoOn,
                color: onDark,
                icon: const Icon(Icons.motion_photos_off_outlined),
                selectedIcon: const Icon(Icons.motion_photos_auto_outlined),
                onPressed: () => setState(() {
                  _autoOn = !_autoOn;
                  _autoReads = 0;
                  _shutter.reset();
                  _autoState = AutoShutterState.searching;
                }),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  key: const Key('label-scan-steps'),
                  children: [
                    _Step(number: 1, text: l10n.labelScanStep1),
                    _Step(number: 2, text: l10n.labelScanStep2),
                    _Step(number: 3, text: l10n.labelScanStep3),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: ColoredBox(
                      color: const Color(0xFF1C1C1C),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          switch (_cameraReady) {
                            true => KeyedSubtree(
                              key: const Key('label-scan-preview'),
                              child: _camera.preview(),
                            ),
                            false => _NoCamera(text: l10n.labelScanNoCamera),
                            null => const Center(
                              child: CircularProgressIndicator(color: onDark),
                            ),
                          },
                          if (_cameraReady == true)
                            _GuideFrame(
                              label: !_autoActive || _photos.isNotEmpty
                                  ? l10n.labelScanFrame
                                  : _autoState == AutoShutterState.searching
                                  ? l10n.labelScanAutoSearching
                                  : l10n.labelScanAutoHolding,
                            ),
                          if (_reading)
                            ColoredBox(
                              color: Colors.black54,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(
                                      color: onDark,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      l10n.labelScanReading,
                                      style: const TextStyle(color: onDark),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    _message!,
                    key: const Key('label-scan-message'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFFFD27A),
                    ),
                  ),
                ),
              if (_photos.isNotEmpty)
                SizedBox(
                  height: 76,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    children: [
                      for (final (i, photo) in _photos.indexed)
                        _Thumb(
                          key: Key('label-scan-photo-$i'),
                          photo: photo,
                          tooltip: l10n.labelScanRemove,
                          onRemove: locked
                              ? null
                              : () => setState(() => _photos.removeAt(i)),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          key: const Key('label-scan-gallery'),
                          style: TextButton.styleFrom(foregroundColor: onDark),
                          onPressed: locked ? null : _gallery,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(l10n.labelScanGallery),
                        ),
                      ),
                    ),
                    _Shutter(
                      tooltip: l10n.labelScanCapture,
                      busy: _busy,
                      onPressed: locked || _cameraReady == null
                          ? null
                          : _capture,
                    ),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FilledButton(
                          key: const Key('label-scan-read'),
                          onPressed: locked || _photos.isEmpty ? null : _read,
                          child: Text(l10n.labelScanRead(_photos.length)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Colors.white.withValues(alpha: 0.85), height: 1.35);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(right: 10, top: 1),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}

/// Um retângulo com cantos marcados, onde pôr a etiqueta.
class _GuideFrame extends StatelessWidget {
  const _GuideFrame({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth * 0.78;
        final height = (box.maxHeight * 0.62).clamp(80.0, width * 1.4);
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: width,
                height: height,
                child: const CustomPaint(painter: _CornersPainter()),
              ),
              const SizedBox(height: 10),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _CornersPainter extends CustomPainter {
  const _CornersPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const arm = 26.0;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, arm)
      ..lineTo(0, 0)
      ..lineTo(arm, 0)
      ..moveTo(w - arm, 0)
      ..lineTo(w, 0)
      ..lineTo(w, arm)
      ..moveTo(w, h - arm)
      ..lineTo(w, h)
      ..lineTo(w - arm, h)
      ..moveTo(arm, h)
      ..lineTo(0, h)
      ..lineTo(0, h - arm);
    canvas.drawPath(path, paint);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_CornersPainter oldDelegate) => false;
}

class _NoCamera extends StatelessWidget {
  const _NoCamera({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    key: const Key('label-scan-no-camera'),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            color: Colors.white70,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    ),
  );
}

class _Shutter extends StatelessWidget {
  const _Shutter({
    required this.tooltip,
    required this.busy,
    required this.onPressed,
  });

  final String tooltip;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      child: InkResponse(
        key: const Key('label-scan-capture'),
        onTap: onPressed,
        radius: 40,
        child: Container(
          width: 72,
          height: 72,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: onPressed == null ? Colors.white38 : Colors.white,
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : null,
          ),
        ),
      ),
    ),
  );
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.photo,
    required this.tooltip,
    required this.onRemove,
    super.key,
  });

  final Uint8List photo;
  final String tooltip;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(photo, width: 64, height: 64, fit: BoxFit.cover),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: IconButton.filled(
            tooltip: tooltip,
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
        ),
      ],
    ),
  );
}
