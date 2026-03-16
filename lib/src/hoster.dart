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
      } catch (_) {}
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

  final _urlRegex = RegExp(
    r'(voe(?:unbl(?:oc)?k|sxunblck)?\.(?:sx|com|net))/(\w+)',
    caseSensitive: false,
  );
  final _hlsMatcher = RegExp(r'[\"]hls[\"]:\s*[\"](.*)[\"]', multiLine: true, caseSensitive: false);
  final _mp4Matcher = RegExp(r'[\"]mp4[\"]:\s*[\"](.*)[\"]', multiLine: true, caseSensitive: false);
  final _base64Matcher = RegExp(r"var\s+\w+\s*=\s*'([A-Za-z0-9+/=]{50,})'", multiLine: true, caseSensitive: false);
  final _genericBase64Matcher = RegExp(r"['\"]([A-Za-z0-9+/=]{100,})['\"]", multiLine: true, caseSensitive: false);
  final _directHlsMatcher = RegExp(r"['\"]?(https?://[^'\"<>\s]+\.m3u8(?:\?[^'\"<>\s]*)?)['\"]?", multiLine: true, caseSensitive: false);
  final _directMp4Matcher = RegExp(r"['\"]?(https?://[^'\"<>\s]+\.mp4(?:\?[^'\"<>\s]*)?)['\"]?", multiLine: true, caseSensitive: false);
  final _sourcesMatcher = RegExp(r'''sources\s*[:=]\s*\[\s*\{\s*(?:file|src)\s*:\s*['"](https?://[^'"]+)['"]''', multiLine: true, caseSensitive: false);
  final _fileMatcher = RegExp(r'''['"]?file['"]?\s*[:=]\s*['"](https?://[^'"]+\.(?:m3u8|mp4)[^'"]*)['"]''', multiLine: true, caseSensitive: false);

  final List<String> _junkParts = const ['@\$', '^^', '~@', '%?', '*~', '!!', '#&'];

  @override
  String get name => 'VOE';

  @override
  bool matchesUrl(String url) {
    final matches = _urlRegex.hasMatch(url);
    print('[VOE] matchesUrl("$url") = $matches');
    return matches;
  }

  @override
  bool matchesDocument(Document document, String sourceUrl) {
    final meta = document.head?.querySelectorAll('meta[name=keywords]') ?? const [];
    final matchesMeta = meta.any((e) => (e.attributes['content'] ?? '').trim().toLowerCase() == name.toLowerCase());
    final result = matchesMeta || matchesUrl(sourceUrl);
    print('[VOE] matchesDocument: matchesMeta=$matchesMeta, matchesUrl=${matchesUrl(sourceUrl)}, result=$result');
    return result;
  }

  @override
  Future<Document> redirect(Document document, String sourceUrl, Future<Document> Function(String p1) fetchDocument) async {
    print('[VOE] redirect: body children=${document.body?.children.length ?? 0}');
    if ((document.body?.children.length ?? 0) > 1) {
      print('[VOE] redirect: body has >1 children, no redirect needed');
      return document;
    }
    final location = _redirectLocation(document);
    print('[VOE] redirect: location=$location');
    if (location == null) return document;
    print('[VOE] redirect: following redirect to $location');
    return fetchDocument(location);
  }

  @override
  Set<String> resolveStreams(Document document, String sourceUrl) {
    final out = <String>{};
    final html = document.outerHtml;

    print('[VOE] ===== resolveStreams START =====');
    print('[VOE] HTML length: ${html.length}');
    print('[VOE] sourceUrl: $sourceUrl');

    // Log script tags
    final scripts = document.getElementsByTagName('script');
    print('[VOE] Found ${scripts.length} script tags');
    for (var i = 0; i < scripts.length; i++) {
      final s = scripts[i];
      final type = s.attributes['type'] ?? '(none)';
      final src = s.attributes['src'] ?? '(inline)';
      final textLen = s.text.length;
      print('[VOE]   script[$i]: type=$type, src=$src, textLength=$textLen');
      if (textLen > 0 && textLen < 300) {
        print('[VOE]   script[$i] content: ${s.text}');
      } else if (textLen >= 300) {
        print('[VOE]   script[$i] preview: ${s.text.substring(0, 200)}...');
      }
    }

    // 1) Classic "hls"/"mp4" JSON keys
    final hlsMatches = _hlsMatcher.allMatches(html).toList();
    print('[VOE] Step 1a - hlsMatcher matches: ${hlsMatches.length}');
    for (final m in hlsMatches) {
      print('[VOE]   hls raw: "${m.group(1)}"');
      final link = _tryDecodeUrl(sourceUrl, m.group(1));
      print('[VOE]   hls decoded: $link');
      if (link != null) out.add(link);
    }

    final mp4Matches = _mp4Matcher.allMatches(html).toList();
    print('[VOE] Step 1b - mp4Matcher matches: ${mp4Matches.length}');
    for (final m in mp4Matches) {
      print('[VOE]   mp4 raw: "${m.group(1)}"');
      final link = _tryDecodeUrl(sourceUrl, m.group(1));
      print('[VOE]   mp4 decoded: $link');
      if (link != null) out.add(link);
    }

    // 2) application/json script tags
    print('[VOE] Step 2 - checking application/json scripts');
    for (final script in scripts) {
      if ((script.attributes['type'] ?? '').trim().toLowerCase() != 'application/json') continue;
      print('[VOE]   Found application/json script, length=${script.text.length}');
      print('[VOE]   Preview: ${script.text.substring(0, script.text.length > 100 ? 100 : script.text.length)}...');
      final decoded = _decodeScriptPayload(script.text);
      print('[VOE]   Decoded payload: $decoded');
      if (decoded == null) continue;
      final source = resolveUrl(sourceUrl, decoded['source'] as String?);
      final direct = resolveUrl(sourceUrl, decoded['direct_access_url'] as String?);
      print('[VOE]   source=$source, direct=$direct');
      if (source != null) out.add(source);
      if (direct != null) out.add(direct);
    }

    // 3) Base64 encoded variable
    final base64Matches = _base64Matcher.allMatches(html).toList();
    print('[VOE] Step 3 - base64Matcher matches: ${base64Matches.length}');
    for (final m in base64Matches) {
      final payload = m.group(1);
      print('[VOE]   base64 payload (first 80 chars): ${payload?.substring(0, payload.length > 80 ? 80 : payload.length)}...');
      _tryDecodeBase64Payload(sourceUrl, payload, out);
    }

    // 4) Generic base64
    if (out.isEmpty) {
      final genericMatches = _genericBase64Matcher.allMatches(html).toList();
      print('[VOE] Step 4 - genericBase64Matcher matches: ${genericMatches.length}');
      for (final m in genericMatches) {
        final payload = m.group(1);
        print('[VOE]   generic base64 (first 80 chars): ${payload?.substring(0, payload!.length > 80 ? 80 : payload.length)}...');
        _tryDecodeBase64Payload(sourceUrl, payload, out);
      }
    } else {
      print('[VOE] Step 4 - skipped (already have results)');
    }

    // 5) Direct URLs
    if (out.isEmpty) {
      final hlsDirect = _directHlsMatcher.allMatches(html).toList();
      final mp4Direct = _directMp4Matcher.allMatches(html).toList();
      print('[VOE] Step 5 - directHls matches: ${hlsDirect.length}, directMp4 matches: ${mp4Direct.length}');
      for (final m in hlsDirect) {
        final url = m.group(1);
        print('[VOE]   direct hls: $url');
        if (url != null && !url.contains('sample') && !url.contains('thumbnail')) {
          final resolved = resolveUrl(sourceUrl, url);
          if (resolved != null) out.add(resolved);
        }
      }
      for (final m in mp4Direct) {
        final url = m.group(1);
        print('[VOE]   direct mp4: $url');
        if (url != null && !url.contains('sample') && !url.contains('thumbnail')) {
          final resolved = resolveUrl(sourceUrl, url);
          if (resolved != null) out.add(resolved);
        }
      }
    } else {
      print('[VOE] Step 5 - skipped (already have results)');
    }

    // 6) "sources"/"file" patterns
    if (out.isEmpty) {
      final sourcesMatches = _sourcesMatcher.allMatches(html).toList();
      final fileMatches = _fileMatcher.allMatches(html).toList();
      print('[VOE] Step 6 - sourcesMatcher matches: ${sourcesMatches.length}, fileMatcher matches: ${fileMatches.length}');
      for (final m in sourcesMatches) {
        print('[VOE]   sources: ${m.group(1)}');
        final resolved = resolveUrl(sourceUrl, m.group(1));
        if (resolved != null) out.add(resolved);
      }
      for (final m in fileMatches) {
        print('[VOE]   file: ${m.group(1)}');
        final resolved = resolveUrl(sourceUrl, m.group(1));
        if (resolved != null) out.add(resolved);
      }
    } else {
      print('[VOE] Step 6 - skipped (already have results)');
    }

    print('[VOE] ===== resolveStreams END: ${out.length} results =====');
    print('[VOE] Results: $out');
    return out;
  }

  void _tryDecodeBase64Payload(String sourceUrl, String? payload, Set<String> out) {
    if (payload == null || payload.isEmpty) return;
    // Method A: base64 → reversed → JSON
    try {
      final decoded = utf8.decode(base64.decode(payload));
      final reversed = decoded.split('').reversed.join();
      print('[VOE]     Method A: reversed string (first 100): ${reversed.substring(0, reversed.length > 100 ? 100 : reversed.length)}...');
      final json_ = json.decode(reversed) as Map<String, dynamic>;
      print('[VOE]     Method A: decoded JSON keys: ${json_.keys}');
      final source = resolveUrl(sourceUrl, json_['source'] as String?);
      final direct = resolveUrl(sourceUrl, json_['direct_access_url'] as String?);
      print('[VOE]     Method A: source=$source, direct=$direct');
      if (source != null) out.add(source);
      if (direct != null) out.add(direct);
      return;
    } catch (e) {
      print('[VOE]     Method A failed: $e');
    }
    // Method B: base64 → JSON (not reversed)
    try {
      final decoded = utf8.decode(base64.decode(payload));
      print('[VOE]     Method B: decoded (first 100): ${decoded.substring(0, decoded.length > 100 ? 100 : decoded.length)}...');
      final json_ = json.decode(decoded) as Map<String, dynamic>;
      print('[VOE]     Method B: decoded JSON keys: ${json_.keys}');
      final source = resolveUrl(sourceUrl, json_['source'] as String?);
      final direct = resolveUrl(sourceUrl, json_['direct_access_url'] as String?);
      print('[VOE]     Method B: source=$source, direct=$direct');
      if (source != null) out.add(source);
      if (direct != null) out.add(direct);
    } catch (e) {
      print('[VOE]     Method B failed: $e');
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
      print('[VOE]     _decodeScriptPayload: input length=${payload.length}');
      final step1 = _shiftLetters(jsonText);
      print('[VOE]     step1 (shiftLetters, first 50): ${step1.substring(0, step1.length > 50 ? 50 : step1.length)}...');
      final step2 = _replaceJunk(step1).replaceAll('_', '');
      print('[VOE]     step2 (replaceJunk, length): ${step2.length}');
      final step3 = utf8.decode(base64.decode(step2));
      print('[VOE]     step3 (base64 decode, first 50): ${step3.substring(0, step3.length > 50 ? 50 : step3.length)}...');
      final step4 = _shiftBack(step3, 3);
      print('[VOE]     step4 (shiftBack, first 50): ${step4.substring(0, step4.length > 50 ? 50 : step4.length)}...');
      final step5 = utf8.decode(base64.decode(step4.split('').reversed.join())).trim();
      print('[VOE]     step5 (final JSON, first 100): ${step5.substring(0, step5.length > 100 ? 100 : step5.length)}...');
      return json.decode(step5) as Map<String, dynamic>;
    } catch (e) {
      print('[VOE]     _decodeScriptPayload FAILED: $e');
      return null;
    }
  }

  String? _tryDecodeUrl(String sourceUrl, String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final trimmed = raw.trim();
    try {
      final decoded = utf8.decode(base64.decode(trimmed));
      print('[VOE]     _tryDecodeUrl: base64 decoded to "$decoded"');
      return resolveUrl(sourceUrl, decoded);
    } catch (_) {
      print('[VOE]     _tryDecodeUrl: not base64, using raw "$trimmed"');
      return resolveUrl(sourceUrl, trimmed);
    }
  }
}
