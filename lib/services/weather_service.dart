import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class GeocodedCity {
  const GeocodedCity({
    required this.name,
    required this.country,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String country;
  final double latitude;
  final double longitude;
}

class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String _cachedCity = '';

  Future<String> savedCity() async {
    if (_cachedCity.isNotEmpty) return _cachedCity;
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/last_weather_city.txt');
      if (await f.exists()) {
        _cachedCity = (await f.readAsString()).trim();
      }
    } catch (_) {}
    return _cachedCity;
  }

  Future<void> saveCity(String city) async {
    final clean = city.trim();
    if (clean.isEmpty) return;
    _cachedCity = clean;
    try {
      final dir = await getApplicationSupportDirectory();
      await File('${dir.path}/last_weather_city.txt').writeAsString(clean);
    } catch (_) {}
  }

  Future<String> fetchWeather(String cityQuery) async {
    final cleanCity = cityQuery.trim();
    if (cleanCity.isEmpty) throw Exception('City name is empty.');

    final geoUrl =
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeQueryComponent(cleanCity)}&count=1&language=en&format=json';
    final geoJson = await _httpGet(geoUrl);
    final city = parseGeocodingResponse(geoJson);
    if (city == null) throw Exception('Could not find weather location "$cleanCity".');

    final forecastUrl =
        'https://api.open-meteo.com/v1/forecast?latitude=${city.latitude.toStringAsFixed(4)}'
        '&longitude=${city.longitude.toStringAsFixed(4)}'
        '&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m'
        '&daily=temperature_2m_max,temperature_2m_min&forecast_days=1&timezone=auto';
    final forecastJson = await _httpGet(forecastUrl);
    final summary = formatWeatherResponse(city, forecastJson);
    if (summary == null) throw Exception('Weather forecast unavailable for ${city.name}.');
    await saveCity(city.name);
    return summary;
  }

  Future<String> _httpGet(String url) async {
    final resp = await _client
        .get(Uri.parse(url), headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 6));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Weather request failed (HTTP ${resp.statusCode})');
    }
    return utf8.decode(resp.bodyBytes);
  }

  static GeocodedCity? parseGeocodingResponse(String jsonStr) {
    try {
      final root = jsonDecode(jsonStr);
      if (root is! Map<String, dynamic>) return null;
      final results = root['results'];
      if (results is! List || results.isEmpty) return null;
      final first = results.first;
      if (first is! Map<String, dynamic>) return null;
      final name = (first['name'] ?? '').toString().trim();
      final lat = (first['latitude'] as num?)?.toDouble();
      final lon = (first['longitude'] as num?)?.toDouble();
      if (name.isEmpty || lat == null || lon == null) return null;
      final country = (first['country'] ?? '').toString().trim();
      return GeocodedCity(name: name, country: country, latitude: lat, longitude: lon);
    } catch (_) {
      return null;
    }
  }

  static String? formatWeatherResponse(GeocodedCity city, String jsonStr) {
    try {
      final root = jsonDecode(jsonStr);
      if (root is! Map<String, dynamic>) return null;
      final current = root['current'];
      if (current is! Map<String, dynamic>) return null;
      final temp = (current['temperature_2m'] as num?)?.toDouble();
      if (temp == null) return null;
      final feelsLike = (current['apparent_temperature'] as num?)?.toDouble();
      final humidity = (current['relative_humidity_2m'] as num?)?.toInt();
      final code = (current['weather_code'] as num?)?.toInt() ?? -1;
      final wind = (current['wind_speed_10m'] as num?)?.toDouble();

      final daily = root['daily'] as Map<String, dynamic>?;
      final highs = daily?['temperature_2m_max'] as List<dynamic>?;
      final lows = daily?['temperature_2m_min'] as List<dynamic>?;
      final high = highs != null && highs.isNotEmpty ? (highs.first as num?)?.toDouble() : null;
      final low = lows != null && lows.isNotEmpty ? (lows.first as num?)?.toDouble() : null;

      final place = city.country.isNotEmpty ? '${city.name}, ${city.country}' : city.name;
      final condition = describeWmoWeatherCode(code);
      final buf = StringBuffer('$place: ${temp.round()}°C, $condition');
      if (feelsLike != null) buf.write(' (feels like ${feelsLike.round()}°C)');
      if (high != null && low != null) buf.write(' · High ${high.round()}° / Low ${low.round()}°');
      if (humidity != null) buf.write(' · Humidity $humidity%');
      if (wind != null) buf.write(' · Wind ${wind.round()} km/h');
      return buf.toString();
    } catch (_) {
      return null;
    }
  }

  static String describeWmoWeatherCode(int code) {
    return switch (code) {
      0 => 'Clear sky',
      1 => 'Mainly clear',
      2 => 'Partly cloudy',
      3 => 'Overcast',
      45 || 48 => 'Foggy',
      51 || 53 || 55 => 'Drizzle',
      56 || 57 => 'Freezing drizzle',
      61 || 63 || 65 => 'Rain',
      66 || 67 => 'Freezing rain',
      71 || 73 || 75 || 77 => 'Snow',
      80 || 81 || 82 => 'Rain showers',
      85 || 86 => 'Snow showers',
      95 || 96 || 99 => 'Thunderstorm',
      _ => 'Conditions clear',
    };
  }
}
