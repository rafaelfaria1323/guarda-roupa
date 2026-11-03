import 'package:powersync/powersync.dart';

/// Schema local (SQLite gerido pelo PowerSync).
///
/// - `garments`: sincronizada a partir do servidor (só leitura no servidor).
///   As escritas locais são otimistas e substituídas pelo estado do servidor
///   depois de as operações serem aceites.
/// - `garment_operations`: insert-only. Cada linha é uma operação de domínio
///   (ADR-008) enviada para `apply_garment_operation`. O `id` é o `op_id`.
/// - `wear_events` / `wear_operations`: o mesmo par para as utilizações
///   reais (`apply_wear_operation`); o `event_id` identifica a utilização.
/// - `cleaning_events` / `care_policies`: limpezas e valores escolhidos
///   (lavagem, rotatividade); as operações vão também em `wear_operations`.
/// - `outfits` / `outfit_operations`: conjuntos guardados
///   (`apply_outfit_operation`); o `outfit_id` identifica o conjunto.
/// - `inspirations` / `style_operations`: inspirações
///   (`apply_style_operation`); o `entity_id` identifica a entidade.
/// - `sync_conflicts`: local-only. Resultados `merged`/`conflict`/`rejected`
///   que o utilizador tem de ver.
const localSchema = Schema([
  Table('garments', [
    Column.text('owner_id'),
    Column.text('category'),
    Column.text('name'),
    Column.text('brand'),
    Column.text('notes'),
    Column.text('colors'),
    Column.text('photos'),
    Column.text('pattern'),
    Column.text('texture'),
    Column.text('warmth'),
    Column.integer('rain_ok'),
    Column.integer('wind_ok'),
    Column.text('occasions'),
    Column.text('material'),
    Column.text('care'),
    Column.text('availability'),
    Column.text('archived_at'),
    Column.text('created_at'),
    Column.text('updated_at'),
    Column.integer('version'),
    Column.text('deleted_at'),
  ]),
  Table.insertOnly('garment_operations', [
    Column.text('garment_id'),
    Column.text('kind'),
    Column.text('data'),
    Column.text('created_at'),
  ]),
  Table('wear_events', [
    Column.text('owner_id'),
    Column.text('worn_on'),
    Column.text('garment_ids'),
    Column.text('plan_entry_id'),
    Column.text('created_at'),
    Column.text('updated_at'),
    Column.text('voided_at'),
  ]),
  Table('cleaning_events', [
    Column.text('owner_id'),
    Column.text('garment_id'),
    Column.text('cleaned_on'),
    Column.text('created_at'),
    Column.text('updated_at'),
    Column.text('voided_at'),
  ]),
  Table('care_policies', [
    Column.text('owner_id'),
    Column.text('scope'),
    Column.text('target'),
    Column.integer('laundry_after'),
    Column.integer('rotation_days'),
    Column.text('updated_at'),
  ]),
  Table.insertOnly('wear_operations', [
    Column.text('event_id'),
    Column.text('kind'),
    Column.text('data'),
    Column.text('created_at'),
  ]),
  Table('outfits', [
    Column.text('owner_id'),
    Column.text('name'),
    Column.text('occasions'),
    Column.text('items'),
    Column.text('created_at'),
    Column.text('updated_at'),
    Column.text('deleted_at'),
  ]),
  Table.insertOnly('outfit_operations', [
    Column.text('outfit_id'),
    Column.text('kind'),
    Column.text('data'),
    Column.text('created_at'),
  ]),
  Table('inspirations', [
    Column.text('owner_id'),
    Column.text('title'),
    Column.text('source_url'),
    Column.text('notes'),
    Column.text('palette'),
    Column.text('formality'),
    Column.text('patterns'),
    Column.text('textures'),
    Column.text('occasions'),
    Column.text('created_at'),
    Column.text('updated_at'),
    Column.text('deleted_at'),
  ]),
  Table.insertOnly('style_operations', [
    Column.text('entity_id'),
    Column.text('kind'),
    Column.text('data'),
    Column.text('created_at'),
  ]),
  Table.localOnly('sync_conflicts', [
    Column.text('op_id'),
    Column.text('garment_id'),
    Column.text('kind'),
    Column.text('result'),
    Column.text('reason'),
    Column.text('details'),
    Column.text('created_at'),
  ]),
]);
