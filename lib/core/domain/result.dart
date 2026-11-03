/// Resultado explícito de uma operação: sucesso ou falha tipada.
///
/// Evita representar falhas como listas vazias, `null` ou sucesso fictício
/// (docs/guidelines/codigo-e-arquitetura.md, "Erros explícitos").
sealed class Result<T, F> {
  const Result();
}

final class Ok<T, F> extends Result<T, F> {
  const Ok(this.value);
  final T value;
}

final class Err<T, F> extends Result<T, F> {
  const Err(this.failure);
  final F failure;
}
