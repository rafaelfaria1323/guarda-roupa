/// Preferências deste aparelho, fora da conta. Fora do browser (testes)
/// ficam só em memória.
abstract interface class DevicePrefs {
  String? get(String key);
  void set(String key, String value);
}

final class _MemoryPrefs implements DevicePrefs {
  final _values = <String, String>{};

  @override
  String? get(String key) => _values[key];

  @override
  void set(String key, String value) => _values[key] = value;
}

final DevicePrefs devicePrefs = _MemoryPrefs();
