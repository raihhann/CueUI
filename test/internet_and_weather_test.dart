import 'package:cueui_flutter/services/internet_search_service.dart';
import 'package:cueui_flutter/services/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InternetSearchService', () {
    test('parses Google News RSS XML headlines cleanly', () {
      const sampleXml = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
  <item>
    <title>Breakthrough in Solid-State Batteries Announced - Techwire</title>
    <link>https://example.com/news/1</link>
    <source>Techwire</source>
  </item>
  <item>
    <title>City Transit Expands Night Lines - Metro Daily</title>
    <link>https://example.com/news/2</link>
    <source>Metro Daily</source>
  </item>
</channel></rss>''';

      final items = InternetSearchService.parseRssHeadlines(sampleXml, maxItems: 4);
      expect(items.length, 2);
      expect(items[0].title, 'Breakthrough in Solid-State Batteries Announced');
      expect(items[0].source, 'Techwire');
      expect(items[1].link, 'https://example.com/news/2');
    });

    test('parses Free Dictionary, DuckDuckGo Instant, and Wikipedia summaries', () {
      const dictJson =
          '[{"word":"ephemeral","meanings":[{"partOfSpeech":"adjective","definitions":[{"definition":"Lasting for a very short time."}]}]}]';
      expect(
        InternetSearchService.parseDictionaryDefinition(dictJson),
        'ephemeral (adjective): Lasting for a very short time.',
      );

      const ddgJson = '{"Heading":"Rust","AbstractText":"Rust is a systems programming language.","AbstractURL":"https://rust-lang.org"}';
      final ddg = InternetSearchService.parseDuckDuckGoInstant(ddgJson)!;
      expect(ddg.$1, contains('systems programming language'));
      expect(ddg.$2, 'https://rust-lang.org');

      const wikiJson =
          '{"title":"Flutter (software)","type":"standard","extract":"Flutter is an open-source UI SDK.","content_urls":{"desktop":{"page":"https://en.wikipedia.org/wiki/Flutter_(software)"}}}';
      final wiki = InternetSearchService.parseWikipediaSummary(wikiJson)!;
      expect(wiki.$1, contains('open-source UI SDK'));
    });
  });

  group('WeatherService', () {
    test('parses Open-Meteo geocoding and forecast payloads', () {
      const geoJson = '{"results":[{"name":"Berlin","country":"Germany","latitude":52.52,"longitude":13.405}]}';
      final city = WeatherService.parseGeocodingResponse(geoJson)!;
      expect(city.name, 'Berlin');
      expect(city.country, 'Germany');

      const forecastJson =
          '{"current":{"temperature_2m":18.6,"apparent_temperature":17.9,"relative_humidity_2m":55,"weather_code":1,"wind_speed_10m":12.4},"daily":{"temperature_2m_max":[21.2],"temperature_2m_min":[11.0]}}';
      final formatted = WeatherService.formatWeatherResponse(city, forecastJson)!;
      expect(formatted, contains('Berlin, Germany: 19°C, Mainly clear'));
      expect(formatted, contains('Humidity 55%'));
    });
  });
}
