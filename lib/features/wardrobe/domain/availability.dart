/// Disponibilidade física de uma peça.
///
/// `cleaning_recommended` não é um estado: é um aviso derivado da política
/// de lavagem e não torna a peça indisponível. Arquivar é independente
/// (ver `Garment.archivedAt`).
enum Availability {
  available('available', 0),
  drying('drying', 1),
  washing('washing', 2),

  /// Na limpeza profissional (lavandaria, limpeza a seco), fora de casa.
  atCleaners('at_cleaners', 3),
  needsCleaning('needs_cleaning', 4);

  const Availability(this.id, this._caution);

  /// Identificador estável; nunca alterar um valor existente.
  final String id;

  /// Quanto maior, menos disponível (ADR-008: ordem conservadora).
  final int _caution;

  bool get isAvailable => this == available;

  static Availability? fromId(String id) {
    for (final value in values) {
      if (value.id == id) return value;
    }
    return null;
  }

  /// Resolve duas alterações concorrentes (ADR-008): prevalece o estado
  /// menos disponível (`needs_cleaning` > `at_cleaners` > `washing` >
  /// `drying` > `available`).
  ///
  /// Uma peça nunca volta a "disponível" por causa de um conflito: isso exige
  /// confirmação explícita do utilizador.
  static Availability resolveConflict(Availability a, Availability b) =>
      a._caution >= b._caution ? a : b;
}
