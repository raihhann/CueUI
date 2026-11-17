import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/cue_models.dart';

class NewsHeadline {
  const NewsHeadline({
    required this.title,
    required this.source,
    required this.link,
  });

  final String title;
  final String source;
  final String link;
}

class InternetSearchService {
  InternetSearchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static final RegExp _definitionPrefixRe = RegExp(
    r'^(?:what\s+does\s+.+?\s+mean|define\s+|meaning\s+of\s+|definition\s+of\s+)',
    caseSensitive: false,
  );

  Future<ToolExecutionResult> fetchNews({String topic = ''}) async {
    final cleanTopic = topic.trim();
    final rssUrl = cleanTopic.isEmpty
        ? 'https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en'
        : 'https://news.google.com/rss/search?q=${Uri.encodeQueryComponent(cleanTopic)}&hl=en-US&gl=US&ceid=US:en';
    final webUrl = cleanTopic.isEmpty
        ? 'https://news.google.com'
        : 'https://news.google.com/search?q=${Uri.encodeQueryComponent(cleanTopic)}';

    try {
      final xmlText = await _httpGet(rssUrl);
      final items = parseRssHeadlines(xmlText, maxItems: 4);
      if (items.isEmpty) {
        return ToolExecutionResult(
          ok: true,
          summary: 'No headlines returned right now — tap Open in Browser to view Google News.',
          data: {'openUrl': webUrl},
        );
      }
      final heading = cleanTopic.isEmpty ? 'Top news right now:' : 'Latest news on "$cleanTopic":';
      final body = items
          .map((item) => item.source.isNotEmpty ? '• ${item.title} (${item.source})' : '• ${item.title}')
          .join('\n');
      final firstLink = items.first.link.trim();
      return ToolExecutionResult(
        ok: true,
        summary: '$heading\n$body',
        data: {'openUrl': firstLink.isNotEmpty ? firstLink : webUrl},
      );
    } catch (e) {
      return ToolExecutionResult(
        ok: false,
        summary: "Could not load news ($e). Tap Open in Browser if you're online.",
        data: {'openUrl': webUrl},
      );
    }
  }

  Future<ToolExecutionResult> answerQuestion(String rawQuery) async {
    final cleaned = rawQuery.trim();
    if (cleaned.isEmpty) {
      return const ToolExecutionResult(ok: false, summary: 'Ask a question or give a search term.');
    }
    final subject = extractLookupSubject(cleaned);
    final searchUrl = 'https://www.google.com/search?q=${Uri.encodeQueryComponent(cleaned)}';

    try {
      // 1. Dictionary API for word meanings
      final wordTokens = subject.split(RegExp(r'\s+'));
      final looksLikeWordDef = _definitionPrefixRe.hasMatch(cleaned) &&
          wordTokens.length <= 2 &&
          RegExp(r'^[a-zA-Z-\s]+$').hasMatch(subject);
      if (looksLikeWordDef) {
        try {
          final wordEnc = Uri.encodeComponent(subject.toLowerCase());
          final dictBody = await _httpGet('https://api.dictionaryapi.dev/api/v2/entries/en/$wordEnc');
          final def = parseDictionaryDefinition(dictBody);
          if (def != null && def.isNotEmpty) {
            return ToolExecutionResult(ok: true, summary: def, data: {'openUrl': searchUrl});
          }
        } catch (_) {}
      }

      // 2. DuckDuckGo Instant Answer API
      try {
        final ddgEnc = Uri.encodeQueryComponent(subject.isEmpty ? cleaned : subject);
        final ddgBody = await _httpGet(
          'https://api.duckduckgo.com/?q=$ddgEnc&format=json&no_html=1&skip_disambig=1',
        );
        final ddg = parseDuckDuckGoInstant(ddgBody);
        if (ddg != null) {
          return ToolExecutionResult(
            ok: true,
            summary: ddg.$1,
            data: {'openUrl': ddg.$2.isNotEmpty ? ddg.$2 : searchUrl},
          );
        }
      } catch (_) {}

      // 3. Wikipedia Search + Summary API
      try {
        final wikiEnc = Uri.encodeQueryComponent(subject.isEmpty ? cleaned : subject);
        final wikiSearchBody = await _httpGet(
          'https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=$wikiEnc&srlimit=1&format=json',
        );
        final wikiTitle = parseWikipediaSearchTitle(wikiSearchBody);
        if (wikiTitle != null && wikiTitle.isNotEmpty) {
          final slug = Uri.encodeComponent(wikiTitle.replaceAll(' ', '_'));
          final summaryBody = await _httpGet('https://en.wikipedia.org/api/rest_v1/page/summary/$slug');
          final summary = parseWikipediaSummary(summaryBody);
          if (summary != null) {
            return ToolExecutionResult(
              ok: true,
              summary: summary.$1,
              data: {'openUrl': summary.$2.isNotEmpty ? summary.$2 : searchUrl},
            );
          }
        }
      } catch (_) {}

      return ToolExecutionResult(
        ok: true,
        summary: 'I couldn\'t find an instant summary for "$cleaned". Tap Open in Browser to view web results.',
        data: {'openUrl': searchUrl},
      );
    } catch (e) {
      return ToolExecutionResult(
        ok: false,
        summary: 'Could not reach the internet ($e).',
        data: {'openUrl': searchUrl},
      );
    }
  }

  Future<String> _httpGet(String url) async {
    final resp = await _client
        .get(
          Uri.parse(url),
          headers: const {
            'Accept': 'application/json, application/rss+xml, application/xml, text/xml',
            'User-Agent': 'CueUI-Flutter/1.0',
          },
        )
        .timeout(const Duration(seconds: 6));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    return utf8.decode(resp.bodyBytes);
  }

  static String extractLookupSubject(String rawQuery) {
    var q = rawQuery.trim().replaceAll(RegExp(r'[?!.]+$'), '').trim();
    final patterns = [
      RegExp(r'^what\s+does\s+(.+?)\s+mean$', caseSensitive: false),
      RegExp(r'^(?:what\s+is\s+(?:the\s+)?meaning\s+of|meaning\s+of|definition\s+of|define)\s+(.+)$', caseSensitive: false),
      RegExp(r'^(?:search(?:\s+(?:google|the\s+web|online))?\s+for|look\s+up|google)\s+(.+)$', caseSensitive: false),
      RegExp(r'^(?:tell\s+me\s+about|explain)\s+(.+)$', caseSensitive: false),
      RegExp(r'^(?:who|what)\s+(?:is|was|are|were)\s+(.+)$', caseSensitive: false),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(q);
      if (m != null) {
        final captured = (m.group(1) ?? '').trim();
        if (captured.isNotEmpty) {
          return captured
              .replaceFirst(RegExp(r'^(?:a|an|the)\s+', caseSensitive: false), '')
              .trim();
        }
      }
    }
    return q;
  }

  static String? parseDictionaryDefinition(String jsonStr) {
    try {
      final arr = jsonDecode(jsonStr);
      if (arr is! List || arr.isEmpty) return null;
      final firstEntry = arr.first;
      if (firstEntry is! Map<String, dynamic>) return null;
      final word = (firstEntry['word'] ?? '').toString().trim();
      final meanings = firstEntry['meanings'];
      if (meanings is! List || meanings.isEmpty) return null;
      final firstMeaning = meanings.first;
      if (firstMeaning is! Map<String, dynamic>) return null;
      final pos = (firstMeaning['partOfSpeech'] ?? '').toString().trim();
      final defs = firstMeaning['definitions'];
      if (defs is! List || defs.isEmpty) return null;
      final firstDef = defs.first;
      if (firstDef is! Map<String, dynamic>) return null;
      final definition = (firstDef['definition'] ?? '').toString().trim();
      if (word.isEmpty || definition.isEmpty) return null;
      final example = (firstDef['example'] ?? '').toString().trim();
      final buf = StringBuffer(word);
      if (pos.isNotEmpty) buf.write(' ($pos)');
      buf.write(': $definition');
      if (example.isNotEmpty) buf.write(' Example: "$example"');
      return buf.toString();
    } catch (_) {
      return null;
    }
  }

  static (String, String)? parseDuckDuckGoInstant(String jsonStr) {
    try {
      final root = jsonDecode(jsonStr);
      if (root is! Map<String, dynamic>) return null;
      final url = (root['AbstractURL'] ?? '').toString().trim();
      final answer = (root['Answer'] ?? '').toString().trim();
      if (answer.isNotEmpty) return (trimToConciseSentences(answer), url);

      final abs = (root['AbstractText'] ?? '').toString().trim();
      if (abs.isNotEmpty) {
        final heading = (root['Heading'] ?? '').toString().trim();
        final text = trimToConciseSentences(abs);
        final formatted = heading.isNotEmpty && !text.toLowerCase().startsWith(heading.toLowerCase())
            ? '$heading: $text'
            : text;
        return (formatted, url);
      }

      final def = (root['Definition'] ?? '').toString().trim();
      if (def.isNotEmpty) return (trimToConciseSentences(def), url);
      return null;
    } catch (_) {
      return null;
    }
  }

  static String? parseWikipediaSearchTitle(String jsonStr) {
    try {
      final root = jsonDecode(jsonStr);
      if (root is! Map<String, dynamic>) return null;
      final query = root['query'];
      if (query is! Map<String, dynamic>) return null;
      final results = query['search'];
      if (results is! List || results.isEmpty) return null;
      final first = results.first;
      if (first is! Map<String, dynamic>) return null;
      final title = (first['title'] ?? '').toString().trim();
      return title.isNotEmpty ? title : null;
    } catch (_) {
      return null;
    }
  }

  static (String, String)? parseWikipediaSummary(String jsonStr) {
    try {
      final root = jsonDecode(jsonStr);
      if (root is! Map<String, dynamic>) return null;
      if (root['type']?.toString().trim() == 'disambiguation') return null;
      final extract = (root['extract'] ?? '').toString().trim();
      if (extract.isEmpty) return null;
      final title = (root['title'] ?? '').toString().trim();
      final contentUrls = root['content_urls'];
      final desktop = contentUrls is Map ? contentUrls['desktop'] : null;
      final pageUrl = desktop is Map ? (desktop['page'] ?? '').toString().trim() : '';
      final concise = trimToConciseSentences(extract);
      final text = title.isNotEmpty && !concise.toLowerCase().startsWith(title.toLowerCase())
          ? '$title: $concise'
          : concise;
      return (text, pageUrl);
    } catch (_) {
      return null;
    }
  }

  static List<NewsHeadline> parseRssHeadlines(String xmlText, {int maxItems = 5}) {
    try {
      final doc = XmlDocument.parse(xmlText);
      final items = doc.findAllElements('item');
      final out = <NewsHeadline>[];
      for (final item in items) {
        if (out.length >= maxItems) break;
        final rawTitle = item.getElement('title')?.innerText.trim() ?? '';
        if (rawTitle.isEmpty) continue;
        final source = item.getElement('source')?.innerText.trim() ?? '';
        final link = item.getElement('link')?.innerText.trim() ?? '';
        final cleanTitle = source.isNotEmpty && rawTitle.endsWith(' - $source')
            ? rawTitle.substring(0, rawTitle.length - source.length - 3).trim()
            : rawTitle;
        out.add(NewsHeadline(title: cleanTitle, source: source, link: link));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static String trimToConciseSentences(String text, {int maxChars = 300}) {
    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= maxChars) return collapsed;
    final cut = collapsed.substring(0, maxChars);
    final lastDot = cut.lastIndexOf('. ');
    return lastDot >= 80 ? cut.substring(0, lastDot + 1) : '$cut...';
  }
}
