import 'dart:convert';

import 'package:html/dom.dart';

import 'extensions.dart';
import 'url_utils.dart';

abstract class Hoster {
  String get name;

  bool matchesUrl(String url) => false;

  bool matchesDocument(Document document, String sourceUrl) => matchesUrl(sourceUrl);

  String updateUrl(String url) => url;

  Future<Document> redirect(Document document, String sourceUrl, Future<Document> Function(String url) fetchDocument) async => document;

  Set<String> resolveStreams(Document document, String sourceUrl);

  static Hoster? autoFromUrl(String url) {
    for (final hoster in _allHosters) {
      if (hoster.matchesUrl(url)) return hoster;
    }
    return fromName(url);
  }

  static Hoster? autoFromDocument(Document document, String sourceUrl) {
    for (final hoster in _allHosters) {
      if (hoster.matchesDocument(document, sourceUrl)) return hoster;
    }
    return null;
  }

  static Hoster? fromName(String name) {
    final lowered = name.toLowerCase();
    for (final hoster in _allHosters) {
      if (hoster.name.toLowerCase() == lowered) return hoster;
    }
    if (lowered == 'lulustream') return LuluVdoHoster.instance;
    return null;
  }

  static final List<Hoster> _allHosters = [
    LuluVdoHoster.instance,
    MixDropHoster.instance,
    SpeedfilesHoster.instance,
    StreamtapeHoster.instance,
    VidmolyHoster.instance,
    VoeHoster.instance,
  ];
}

class LuluVdoHoster extends Hoster {
  LuluVdoHoster._();
  static final instance = LuluVdoHoster._();

  final _urlRegex = RegExp(r'(lulu(vdo|stream)\.(com))/(\w+)', caseSensitive: false);
  final _fileMatcher = RegExp(r'file:\s*"([^"]+)"', multiLine: true, caseSensitive: false);

  @override
  String get name => 'LuluVDO';

  @override
  bool matchesUrl(String url) => _urlRegex.hasMatch(url);

  @override
  String updateUrl(String url) {
    if (url.contains('file_code=')) return url;
    final parts = url.split('/').where((e) => e.trim().isNotEmpty).toList(growable: false);
    final id = parts.isEmpty ? url : parts.last;
    return 'https://luluvdo.com/dl?op=embed&file_code=$id&embed=1&referer=luluvdo.com&adb=0';
  }

  @override
  Set<String> resolveStreams(Document document, String sourceUrl) {
    return _fileMatcher
        .allMatches(document.outerHtml)
        .map((m) => resolveUrl(sourceUrl, m.group(1)))
        .whereType<String>()
        .toSet();
  }
}

class MixDropHoster extends Hoster {
  MixDropHoster._();
  static final instance = MixDropHoster._();

  final _urlRegex = RegExp(r'(mixdro?p\.(?:c[ho]|to|sx|bz|gl|club))/(?:f|e)/(\w+)', caseSensitive: false);
  final _linkMatcher = RegExp(r'wurl=\s*[\"](.+?)[\"]', multiLine: true, caseSensitive: false);

  @override
  String get name => 'MixDrop';

  @override
  bool matchesUrl(String url) => _urlRegex.hasMatch(url);

  @override
  String updateUrl(String url) => url.replaceAll('/f/', '/e/');

  @override
  Set<String> resolveStreams(Document document, String sourceUrl) {
    return _linkMatcher
        .allMatches(document.outerHtml)
        .map((m) => resolveUrl(sourceUrl, m.group(1)))
        .whereType<String>()
        .toSet();
  }
}

class SpeedfilesHoster extends Hoster {
  SpeedfilesHoster._();
  static final instance = SpeedfilesHoster._();

  final _urlRegex = RegExp(r'(speedfiles\.net)/(\w+)', caseSensitive: false);
  final _encodedMatcher = RegExp(r'var\s*_0x5opu234\s*=\s*"(.*?)";', multiLine: true, caseSensitive: false);

  @override
  String get name => 'Speedfiles';

  @override
  bool matchesUrl(String url) => _urlRegex.hasMatch(url);

  @override
  Set<String> resolveStreams(Document document, String sourceUrl) {
    final out = <String>{};
    for (final match in _encodedMatcher.allMatches(document.outerHtml)) {
      final encoded = match.group(1)?.trim();
      if (encoded == null || encoded.isEmpty) continue;
      try {
        final decoded = utf8.decode(base64.decode(encoded)).trim();
        final reversed = decoded.swapCase().split('').reversed.join();
        final reversedDecoded = utf8.decode(base64.decode(reversed)).trim().split('').reversed.join();
        final decodedHex = List.generate(reversedDecoded.length ~/ 2, (i) {
          final chunk = reversedDecoded.substring(i * 2, i * 2 + 2);
          return String.fromCharCode(int.parse(chunk, radix: 16));
        }).join();
        final shifted = decodedHex.runes.map((r) => String.fromCharCode(r - 3)).join();
        final link = utf8.decode(base64.decode(shifted.swapCase().split('').reversed.join())).trim();
        final resolved = resolveUrl(sourceUrl, link);
        if (resolved != null) out.add(resolved);
      } catch (_) {
        // ignore invalid payloads
      }
    }
    return out;
  }
}

class StreamtapeHoster extends Hoster {
  StreamtapeHoster._();
  static final instance = StreamtapeHoster._();

  final _urlRegex = RegExp(r'(s(?:tr)?(?:eam|have)?(?:ta?p?e?|cloud|adblock(?:plus|er))\.(?:com|cloud|net|pe|site|link|cc|online|fun|cash|to|xyz))/(?:e|v)/([0-9a-zA-Z]+)', caseSensitive: false);
  final _substringLinkMatcher = RegExp(r'ById\(.+?=\s*([\"]//[^;<]+)', caseSensitive: false);
  final _partMatcher = RegExp(r'[\"]?(\S+)[\"]\S*\s*\([\"](\S+)[\"]', multiLine: true, caseSensitive: false);
  final _substringMatcher = RegExp(r'substring\((\d+)', multiLine: true, caseSensitive: false);
  final _botlinkMatcher = RegExp(r"'botlink.*innerHTML.*?'(.*)'.*?\+.*?'(.*)'", multiLine: true, caseSensitive: false);

  @override
  String get name => 'Streamtape';

  @override
  bool matchesUrl(String url) => _urlRegex.hasMatch(url);

  @override
  String updateUrl(String url) {
    var next = url.contains('/e/') ? url.replaceAll('/e/', '/v/') : url;
    if (next.endsWith('mp4')) {
      next = next.substring(0, next.lastIndexOf('/'));
    }
    return next;
  }

  @override
  Set<String> resolveStreams(Document document, String sourceUrl) {
    final out = <String>{};
    out.addAll(_substringLinks(document, sourceUrl));
    out.addAll(_botLinks(document, sourceUrl));
    return out;
  }

  Set<String> _substringLinks(Document document, String sourceUrl) {
    final html = document.outerHtml;
    final matches = _substringLinkMatcher.allMatches(html).toList(growable: false);
    if (matches.isEmpty) return const {};

    final out = <String>{};
    for (final match in matches) {
      final raw = match.group(1)?.replaceAll("'", '"').trim();
      if (raw == null || raw.isEmpty) continue;
      final parts = raw.split(r'\+');
      final buffer = StringBuffer();

      for (final part in parts) {
        final partMatch = _partMatcher.firstMatch(part);
        final p1 = partMatch?.group(1)?.trim();
        final p2 = partMatch?.group(2)?.trim();
        var p3 = 0;
        if (part.contains('substring')) {
          for (final sm in _substringMatcher.allMatches(part)) {
            p3 += int.tryParse(sm.group(1) ?? '') ?? 0;
          }
        }
        if (p1 != null && p1.isNotEmpty) buffer.write(p1);
        if (p2 != null && p2.isNotEmpty && p2.length >= p3) buffer.write(p2.substring(p3));
      }

      final resolved = resolveUrl(sourceUrl, buffer.toString().trim());
      if (resolved != null) out.add(resolved);
    }
    return out;
  }

  Set<String> _botLinks(Document document, String sourceUrl) {
    final out = <String>{};
    for (final m in _botlinkMatcher.allMatches(document.outerHtml)) {
      final g1 = m.group(1)?.trim();
      final g2 = m.group(2)?.trim();
      if (g1 == null || g1.isEmpty || g2 == null || g2.length < 4) continue;
      final resolved = resolveUrl(sourceUrl, '$g1${g2.substring(4)}');
      if (resolved != null) out.add(resolved);
    }
    return out;
  }
}

class VidmolyHoster extends Hoster {
  VidmolyHoster._();
  static final instance = VidmolyHoster._();

  final _urlRegex = RegExp(r'(vidmoly\.to)/(\w+)', caseSensitive: false);
  final _fileMatcher = RegExp(r'file:\s*"(https?://.*?)"', multiLine: true, caseSensitive: false);

  @override
  String get name => 'Vidmoly';

  @override
  bool matchesUrl(String url) => _urlRegex.hasMatch(url);

  @override
  Set<String> resolveStreams(Document document, String sourceUrl) {
    return _fileMatcher
        .allMatches(document.outerHtml)
        .map((m) => resolveUrl(sourceUrl, m.group(1)))
        .whereType<String>()
        .toSet();
  }
}

class VoeHoster extends Hoster {
  VoeHoster._();
  static final instance = VoeHoster._();

  // Updated: VOE uses many domains now (voe.sx, voeunblk.com, voesxunblck.com, etc.)
  final _urlRegex = RegExp(
    r'(voe(?:unbl(?:oc)?k|sxunblck)?\.(?:sx|com|net))/(\w+)',
    caseSensitive: false,
  );
  final _hlsMatcher = RegExp(r'[\"]hls[\"]:\s*[\"](.*)[\"]', multiLine: true, caseSensitive: false);
  final _mp4Matcher = RegExp(r'[\"]mp4[\"]:\s*[\"](.*)[\"]', multiLine: true, caseSensitive: false);
  final _base64Matcher = RegExp(r"var\s+\w+\s*=\s*'([A-Za-z0-9+/=]{50,})'", multiLine: true, caseSensitive: false);

  // Fallback: match any long base64 string assigned to a variable
  final _genericBase64Matcher = RegExp(r"['\"]([A-Za-z0-9+/=]{100,})['\"]", multiLine: true, caseSensitive: false);

  // Direct m3u8/mp4 URL in page source
  final _directHlsMatcher = RegExp(r"['\"]?(https?://[^'\"<>\s]+\.m3u8(?:\?[^'\"<>\s]*)?)['\"]?", multiLine: true, caseSensitive: false);
  final _directMp4Matcher = RegExp(r"['\"]?(https?://[^'\"<>\s]+\.mp4(?:\?[^'\"<>\s]*)?)['\"]?", multiLine: true, caseSensitive: false);

  // VOE sometimes puts the source in a "sources" or "file" JS variable
  final _sourcesMatcher = RegExp(r'''sources\s*[:=]\s*\[\s*\{\s*(?:file|src)\s*:\s*['"](https?://[^'"]+)['"]''', multiLine: true, caseSensitive: false);
  final _fileMatcher = RegExp(r'''['"]?file['"]?\s*[:=]\s*['"](https?://[^'"]+\.(?:m3u8|mp4)[^'"]*)['"]''', multiLine: true, caseSensitive: false);

  final List<String> _junkParts = const ['@\$', '^^', '~@', '%?', '*~', '!!', '#&'];

  @override
  String get name => 'VOE';

  @override
  bool matchesUrl(String url) => _urlRegex.hasMatch(url);

  @override
  bool matchesDocument(Document document, String sourceUrl) {
    final meta = document.head?.querySelectorAll('meta[name=keywords]') ?? const [];
    final matchesMeta = meta.any((e) => (e.attributes['content'] ?? '').trim().toLowerCase() == name.toLowerCase());
    return matchesMeta || matchesUrl(sourceUrl);
  }

  @override
  Future<Document> redirect(Document document, String sourceUrl, Future<Document> Function(String p1) fetchDocument) async {
    if ((document.body?.children.length ?? 0) > 1) return document;
    final location = _redirectLocation(document);
    if (location == null) return document;
    return fetchDocument(location);
  }

  @override
  Set<String> resolveStreams(Document document, String sourceUrl) {
    final out = <String>{};
    final html = document.outerHtml;

    // 1) Classic "hls"/"mp4" JSON keys
    for (final m in _hlsMatcher.allMatches(html)) {
      final link = _tryDecodeUrl(sourceUrl, m.group(1));
      if (link != null) out.add(link);
    }
    for (final m in _mp4Matcher.allMatches(html)) {
      final link = _tryDecodeUrl(sourceUrl, m.group(1));
      if (link != null) out.add(link);
    }

    // 2) application/json script tags (original VOE obfuscation)
    for (final script in document.getElementsByTagName('script')) {
      if ((script.attributes['type'] ?? '').trim().toLowerCase() != 'application/json') continue;
      final decoded = _decodeScriptPayload(script.text);
      if (decoded == null) continue;
      final source = resolveUrl(sourceUrl, decoded['source'] as String?);
      final direct = resolveUrl(sourceUrl, decoded['direct_access_url'] as String?);
      if (source != null) out.add(source);
      if (direct != null) out.add(direct);
    }

    // 3) Base64 encoded variable (var a168c='...' or similar)
    for (final m in _base64Matcher.allMatches(html)) {
      _tryDecodeBase64Payload(sourceUrl, m.group(1), out);
    }

    // 4) Fallback: try any long base64 string in the page
    if (out.isEmpty) {
      for (final m in _genericBase64Matcher.allMatches(html)) {
        _tryDecodeBase64Payload(sourceUrl, m.group(1), out);
      }
    }

    // 5) Direct .m3u8 / .mp4 URLs in page source
    if (out.isEmpty) {
      for (final m in _directHlsMatcher.allMatches(html)) {
        final url = m.group(1);
        if (url != null && !url.contains('sample') && !url.contains('thumbnail')) {
          final resolved = resolveUrl(sourceUrl, url);
          if (resolved != null) out.add(resolved);
        }
      }
      for (final m in _directMp4Matcher.allMatches(html)) {
        final url = m.group(1);
        if (url != null && !url.contains('sample') && !url.contains('thumbnail')) {
          final resolved = resolveUrl(sourceUrl, url);
          if (resolved != null) out.add(resolved);
        }
      }
    }

    // 6) "sources" or "file" JS patterns
    if (out.isEmpty) {
      for (final m in _sourcesMatcher.allMatches(html)) {
        final resolved = resolveUrl(sourceUrl, m.group(1));
        if (resolved != null) out.add(resolved);
      }
      for (final m in _fileMatcher.allMatches(html)) {
        final resolved = resolveUrl(sourceUrl, m.group(1));
        if (resolved != null) out.add(resolved);
      }
    }

    return out;
  }

  /// Tries to decode a base64 payload containing JSON with 'source' and/or 'direct_access_url'
  void _tryDecodeBase64Payload(String sourceUrl, String? payload, Set<String> out) {
    if (payload == null || payload.isEmpty) return;
    try {
      // Method A: base64 → reversed → JSON
      final jsonText = utf8.decode(base64.decode(payload)).split('').reversed.join();
      final decoded = json.decode(jsonText) as Map<String, dynamic>;
      final source = resolveUrl(sourceUrl, decoded['source'] as String?);
      final direct = resolveUrl(sourceUrl, decoded['direct_access_url'] as String?);
      if (source != null) out.add(source);
      if (direct != null) out.add(direct);
    } catch (_) {
      try {
        // Method B: base64 → JSON (not reversed)
        final jsonText = utf8.decode(base64.decode(payload));
        final decoded = json.decode(jsonText) as Map<String, dynamic>;
        final source = resolveUrl(sourceUrl, decoded['source'] as String?);
        final direct = resolveUrl(sourceUrl, decoded['direct_access_url'] as String?);
        if (source != null) out.add(source);
        if (direct != null) out.add(direct);
      } catch (_) {
        // Not a valid JSON payload, ignore
      }
    }
  }

  String? _redirectLocation(Document document) {
    final script = document.getElementsByTagName('script').isEmpty ? null : document.getElementsByTagName('script').first.text;
    if (script == null || script.isEmpty) return null;
    final m = RegExp(r'window.location.href\s*=\s*[\"](https.*)[\"]', caseSensitive: false).firstMatch(script);
    return m?.group(1)?.trim();
  }

  String _shiftLetters(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      var code = rune;
      if (code >= 65 && code <= 90) {
        code = (code - 65 + 13) % 26 + 65;
      } else if (code >= 97 && code <= 122) {
        code = (code - 97 + 13) % 26 + 97;
      }
      buffer.writeCharCode(code);
    }
    return buffer.toString();
  }

  String _replaceJunk(String input) {
    var out = input;
    for (final junk in _junkParts) {
      out = out.replaceAll(junk, '_');
    }
    return out;
  }

  String _shiftBack(String input, int n) => input.runes.map((r) => String.fromCharCode(r - n)).join();

  Map<String, dynamic>? _decodeScriptPayload(String payload) {
    try {
      if (payload.length < 4) return null;
      final jsonText = payload.substring(2, payload.length - 2);
      final step1 = _shiftLetters(jsonText);
      final step2 = _replaceJunk(step1).replaceAll('_', '');
      final step3 = utf8.decode(base64.decode(step2));
      final step4 = _shiftBack(step3, 3);
      final step5 = utf8.decode(base64.decode(step4.split('').reversed.join())).trim();
      return json.decode(step5) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  String? _tryDecodeUrl(String sourceUrl, String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final trimmed = raw.trim();
    try {
      return resolveUrl(sourceUrl, utf8.decode(base64.decode(trimmed)));
    } catch (_) {
      return resolveUrl(sourceUrl, trimmed);
    }
  }
}
