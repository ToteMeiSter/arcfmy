import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/widgets/weather_geocoding.dart';
import 'package:flutter/material.dart';

/// Asks for a city name, shows geocoding matches and returns the chosen one.
/// The saved location stays untouched until the user picks a match.
class WeatherCityDialog extends StatefulWidget {
  final WeatherCitySearch search;

  const WeatherCityDialog({super.key, this.search = _defaultSearch});

  static Future<List<WeatherCity>> _defaultSearch(
    String query,
    String language,
  ) => searchWeatherCities(query, language);

  @override
  State<WeatherCityDialog> createState() => _WeatherCityDialogState();
}

class _WeatherCityDialogState extends State<WeatherCityDialog> {
  final _controller = TextEditingController();
  List<WeatherCity> _results = const [];
  bool _loading = false;
  String? _message;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _loading) return;
    final localizations = AppLocalizations.of(context)!;
    final language = Localizations.localeOf(context).languageCode;
    setState(() {
      _loading = true;
      _message = null;
      _results = const [];
    });
    try {
      final found = await widget.search(query, language);
      if (!mounted) return;
      setState(() {
        _results = found;
        _message = found.isEmpty ? localizations.weatherNoResults : null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message = localizations.weatherSearchFailed);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(localizations.weatherLocation),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: localizations.weatherCityName,
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 8),
            if (_loading) const LinearProgressIndicator(),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_message!),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final city in _results)
                    ListTile(
                      title: Text(city.label),
                      onTap: () => Navigator.pop(context, city),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _search, child: Text(localizations.weatherSearch)),
      ],
    );
  }
}
