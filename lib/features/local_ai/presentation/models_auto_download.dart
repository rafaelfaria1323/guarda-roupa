import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../care/application/care_providers.dart';
import '../application/local_ai_providers.dart';
import '../domain/local_model.dart';

/// Modelos de IA local descarregados sozinhos (decisão do utilizador a
/// 2026-11-06): com a primeira peça com foto, primeiro o recorte (pequeno)
/// e depois o FashionCLIP, em segundo plano. Uma tentativa por sessão; se
/// o utilizador remover um modelo, só volta a pedido (Definições).
class ModelsAutoDownload extends ConsumerStatefulWidget {
  const ModelsAutoDownload({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ModelsAutoDownload> createState() => _ModelsAutoDownloadState();
}

class _ModelsAutoDownloadState extends ConsumerState<ModelsAutoDownload> {
  var _started = false;

  @override
  void initState() {
    super.initState();
    void check() => WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_maybeDownload());
    });
    ref.listenManual(allGarmentsProvider, (_, _) => check());
    ref.listenManual(localAiAutoOptOutProvider, (_, _) => check());
    for (final model in _models) {
      ref.listenManual(localModelProvider(model), (_, _) => check());
    }
    check();
  }

  static final _models = [LocalModels.background, LocalModels.category];

  Future<void> _maybeDownload() async {
    if (_started || !ref.read(localAiAutoDownloadEnabledProvider)) return;
    if (ref.read(localAiAutoOptOutProvider).value != false) return;
    final garments = ref.read(allGarmentsProvider).value ?? const [];
    if (!garments.any((g) => g.photos.isNotEmpty)) return;
    final states = [for (final m in _models) ref.read(localModelProvider(m))];
    if (states.any((s) => s is ModelChecking)) return;
    _started = true;
    for (final (i, model) in _models.indexed) {
      // Uma falha anterior nesta sessão não se repete sozinha.
      if (states[i] case ModelAbsent(failed: false)) {
        await ref.read(localModelProvider(model).notifier).download();
        if (!mounted) return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
