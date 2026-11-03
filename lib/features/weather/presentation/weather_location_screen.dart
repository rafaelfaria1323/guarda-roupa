import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../application/weather_providers.dart';
import '../data/open_meteo_client.dart';
import '../domain/weather.dart';

/// Escolher a localidade da previsão (P-18): pesquisa por nome, sem GPS.
class WeatherLocationScreen extends ConsumerStatefulWidget {
  const WeatherLocationScreen({super.key});

  @override
  ConsumerState<WeatherLocationScreen> createState() =>
      _WeatherLocationScreenState();
}

class _WeatherLocationScreenState extends ConsumerState<WeatherLocationScreen> {
  final _query = TextEditingController();
  List<WeatherLocation>? _results;
  bool _searching = false;
  bool _failed = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.length < 2) return;
    setState(() {
      _searching = true;
      _failed = false;
    });
    try {
      final results = await ref.read(openMeteoClientProvider).search(query);
      if (!mounted) return;
      setState(() => _results = results);
    } on WeatherFetchFailed {
      if (!mounted) return;
      setState(() {
        _results = null;
        _failed = true;
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _choose(WeatherLocation location) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(weatherLocationProvider.notifier).choose(location);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.weatherLocationChosen(location.name))),
    );
    setState(() {
      _results = null;
      _query.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(weatherLocationProvider).value;
    final results = _results;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.weatherLocationTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (current != null)
            ListTile(
              key: const Key('weather-location-current'),
              leading: const Icon(Icons.place_outlined),
              title: Text(current.name),
              subtitle: current.region == null ? null : Text(current.region!),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(l10n.weatherLocationHint),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const Key('weather-location-search'),
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: l10n.weatherLocationSearch,
                border: const OutlineInputBorder(),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        key: const Key('weather-location-search-go'),
                        icon: const Icon(Icons.search),
                        tooltip: l10n.weatherLocationSearch,
                        onPressed: _search,
                      ),
              ),
            ),
          ),
          if (_failed)
            ListTile(
              key: const Key('weather-location-failed'),
              leading: const Icon(Icons.cloud_off_outlined),
              title: Text(l10n.weatherLocationSearchFailed),
            ),
          if (results != null && results.isEmpty)
            ListTile(
              key: const Key('weather-location-none'),
              title: Text(l10n.weatherLocationNoResults),
            ),
          if (results != null)
            for (final (i, r) in results.indexed)
              ListTile(
                key: Key('weather-location-result-$i'),
                leading: const Icon(Icons.location_city_outlined),
                title: Text(r.name),
                subtitle: Text(
                  [
                    ?r.region,
                    '${r.latitude.toStringAsFixed(2)}, '
                        '${r.longitude.toStringAsFixed(2)}',
                  ].join(' · '),
                ),
                onTap: () => _choose(r),
              ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l10n.weatherAttribution,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
