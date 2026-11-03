import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/domain/result.dart';
import '../../../l10n/app_localizations.dart';
import '../../account_sync/application/providers.dart';
import '../domain/availability.dart';
import '../domain/garment.dart';
import '../domain/garment_category.dart';
import '../domain/wardrobe_repository.dart';
import 'labels.dart';

/// Criar (`id == null`) ou editar uma peça.
class GarmentFormScreen extends ConsumerStatefulWidget {
  const GarmentFormScreen({this.id, super.key});

  final GarmentId? id;

  @override
  ConsumerState<GarmentFormScreen> createState() => _GarmentFormScreenState();
}

class _GarmentFormScreenState extends ConsumerState<GarmentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _notes = TextEditingController();
  GarmentCategory? _category;
  bool _loaded = false;
  bool _saving = false;

  WardrobeRepository? _repo;
  Stream<Garment?>? _garment;

  bool get _isNew => widget.id == null;

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _notes.dispose();
    super.dispose();
  }

  Stream<Garment?>? _streamFor(WardrobeRepository? repo) {
    final id = widget.id;
    if (id == null) return null;
    if (repo != _repo) {
      _repo = repo;
      _garment = repo?.watchGarment(id);
    }
    return _garment;
  }

  /// Preenche o formulário uma única vez, para não apagar o que o utilizador
  /// está a escrever quando chega uma atualização sincronizada.
  void _fill(Garment garment) {
    if (_loaded) return;
    _loaded = true;
    _category = garment.category;
    _name.text = garment.name ?? '';
    _brand.text = garment.brand ?? '';
    _notes.text = garment.notes ?? '';
  }

  /// Mantém as cores atuais: o formulário ainda não as edita.
  GarmentDraft _draft(Garment? current) => GarmentDraft(
    category: _category!,
    name: _name.text,
    brand: _brand.text,
    notes: _notes.text,
    colors: current?.colors ?? const [],
  );

  Future<void> _save(WardrobeRepository repo, Garment? current) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final result = current == null
        ? await repo.addGarment(_draft(null))
        : await repo.updateGarment(current.id, _draft(current));
    if (!mounted) return;
    setState(() => _saving = false);
    // Sem snackbar: a lista e o ícone de sincronização já mostram o resultado
    // (e um snackbar no shell tapava o botão de adicionar).
    _report(result, null, onOk: (_) => context.pop());
  }

  Future<void> _run(
    Future<WardrobeResult<Garment>> Function() action, {
    String? done,
    void Function(Garment)? onOk,
  }) async {
    final result = await action();
    if (mounted) _report(result, done, onOk: onOk);
  }

  void _report(
    WardrobeResult<Garment> result,
    String? done, {
    void Function(Garment)? onOk,
  }) {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    switch (result) {
      case Ok(value: final garment):
        if (done != null) {
          messenger.showSnackBar(SnackBar(content: Text(done)));
        }
        onOk?.call(garment);
      case Err(failure: final failure):
        final message = switch (failure) {
          GarmentNotFound() || GarmentDeleted() => l10n.garmentNotFound,
          InvalidDraft() || StorageFailure() => l10n.garmentSaveFailed,
        };
        messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String? Function(String?) _maxLength(int max) =>
      (value) => (value?.trim().length ?? 0) > max
      ? AppLocalizations.of(context).garmentTooLong(max)
      : null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.watch(wardrobeRepositoryProvider);
    final stream = _streamFor(repo);

    if (repo == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (stream == null) return _buildForm(context, repo, null);

    return StreamBuilder<Garment?>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData &&
            !snapshot.hasError &&
            snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final garment = snapshot.data;
        if (garment == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(l10n.garmentNotFound)),
          );
        }
        _fill(garment);
        return _buildForm(context, repo, garment);
      },
    );
  }

  Widget _buildForm(
    BuildContext context,
    WardrobeRepository repo,
    Garment? garment,
  ) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? l10n.garmentNew : l10n.garmentEdit),
        actions: [
          if (garment != null)
            PopupMenuButton<void Function()>(
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: () => _run(
                    () => repo.duplicateGarment(garment.id),
                    done: l10n.garmentDuplicated,
                    onOk: (copy) =>
                        context.pushReplacement(AppRoutes.garment(copy.id)),
                  ),
                  child: Text(l10n.garmentDuplicate),
                ),
                PopupMenuItem(
                  value: garment.isArchived
                      ? () => _run(() => repo.unarchiveGarment(garment.id))
                      : () => _run(
                          () => repo.archiveGarment(garment.id),
                          onOk: (_) => context.pop(),
                        ),
                  child: Text(
                    garment.isArchived
                        ? l10n.garmentUnarchive
                        : l10n.garmentArchive,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (garment?.isArchived ?? false)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Chip(
                  avatar: const Icon(Icons.inventory_2_outlined),
                  label: Text(l10n.garmentArchived),
                ),
              ),
            DropdownButtonFormField<GarmentCategory>(
              key: const Key('garment-category'),
              initialValue: _category,
              decoration: InputDecoration(
                labelText: l10n.garmentCategory,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final category in GarmentCategory.values)
                  DropdownMenuItem(
                    value: category,
                    child: Text(l10n.categoryLabel(category.id)),
                  ),
              ],
              validator: (value) =>
                  value == null ? l10n.garmentCategoryRequired : null,
              onChanged: (value) => setState(() => _category = value),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('garment-name'),
              controller: _name,
              decoration: InputDecoration(
                labelText: l10n.garmentName,
                border: const OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: _maxLength(GarmentRules.maxNameLength),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('garment-brand'),
              controller: _brand,
              decoration: InputDecoration(
                labelText: l10n.garmentBrand,
                border: const OutlineInputBorder(),
              ),
              validator: _maxLength(GarmentRules.maxBrandLength),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('garment-notes'),
              controller: _notes,
              decoration: InputDecoration(
                labelText: l10n.garmentNotes,
                border: const OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 5,
              validator: _maxLength(GarmentRules.maxNotesLength),
            ),
            if (garment != null) ...[
              const SizedBox(height: 24),
              Text(
                l10n.garmentAvailability,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              // Aplicada de imediato: é uma transição explícita, não um campo
              // do formulário.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in Availability.values)
                    ChoiceChip(
                      avatar: Icon(availabilityIcon(value)),
                      label: Text(l10n.availabilityLabel(value.id)),
                      selected: garment.availability == value,
                      onSelected: (_) =>
                          _run(() => repo.setAvailability(garment.id, value)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 32),
            FilledButton(
              key: const Key('garment-save'),
              onPressed: _saving ? null : () => _save(repo, garment),
              child: Text(l10n.garmentSave),
            ),
          ],
        ),
      ),
    );
  }
}
