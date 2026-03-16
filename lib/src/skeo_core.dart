import 'dart:io' as io;
import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'hoster.dart';
import 'test_videos.dart';
import 'url_utils.dart';

class Skeo {
  Skeo._();

  static const Map<String, String> _defaultHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9,de;q=0.8',
    'Connection': 'keep-alive',
    'Upgrade-Insecure-Requests': '1',
  };

  static final RegExp _cleanRegex = RegExp(
    r'http(s?)://\S+\.(mp4|m3u8|webm|mkv|flv|vob|drc|gifv|avi|((m?)(2?)ts)|mov|qt|wmv|yuv|rm((vb)?)|viv|asf|amv|m4p|m4v|mp2|mp((e)?)g|mpe|mpv|m2v|svi|3gp|3g2|mxf|roq|nsv|f4v|f4p|f4a|f4b|dll)',
    caseSensitive: false,
    multiLine: true,
  );

  static final RegExp _queryRegex = RegExp(
    '${_cleanRegex.pattern}(\\?\\w+=(\\w|-)*(?:&(?:\\w+=(\\w|[-_.~%])*|=(\\w|[-_.~%])+))*)?',
    caseSensitive: false,
    multiLine: true,
  );

  static Set<String> resolveStreamsFromDocument(Document document, {String sourceUrl = '', Hoster? hoster}) {
    final fitted = hoster ?? Hoster.autoFromDocument(document, sourceUrl);
    print('[SKEO] resolveStreamsFromDocument: hoster=${fitted?.name ?? "null"}, sourceUrl=$sourceUrl');

    final hosterSpecific = fitted?.resolveStreams(document, sourceUrl) ?? const <String>{};
    print('[SKEO] hosterSpecific results: $hosterSpecific');

    final videoSources = _videoSources(document, sourceUrl);
    print('[SKEO] videoSources results: $videoSources');

    final videosInDoc = _videosInDocument(document, sourceUrl);
    print('[SKEO] videosInDocument results: $videosInDoc');

    return {
      ...hosterSpecific,
      ...videoSources,
      ...videosInDoc,
    };
  }

  static Future<Set<String>> resolveStreamsFromUrl(
    String url, {
    http.Client? client,
    Hoster? hoster,
    Map<String, String> headers = const {},
  }) async {
    print('[SKEO] ========== resolveStreamsFromUrl ==========');
    print('[SKEO] Input URL: $url');

    final effectiveHeaders = {..._defaultHeaders, ...headers};
    final cookies = <String, String>{};

    try {
      final urlHoster = hoster ?? Hoster.autoFromUrl(url);
      print('[SKEO] Detected hoster: ${urlHoster?.name ?? "NONE"}');

      final firstUrl = urlHoster?.updateUrl(url) ?? url;
      print('[SKEO] URL after updateUrl: $firstUrl');

      final uri = Uri.tryParse(firstUrl);
      if (uri != null && !effectiveHeaders.containsKey('Referer')) {
        effectiveHeaders['Referer'] = '${uri.scheme}://${uri.host}/';
      }

      // Build list of URLs to try
      final urlsToTry = <String>[firstUrl];
      final embedUrl = _toEmbedUrl(firstUrl);
      if (embedUrl != firstUrl) {
        urlsToTry.add(embedUrl);
      }

      for (final tryUrl in urlsToTry) {
        print('[SKEO] --- Trying URL: $tryUrl ---');

        final fetchResult = await _fetchDocumentWithRedirects(tryUrl, effectiveHeaders, cookies);
        final document = fetchResult.document;
        final finalUrl = fetchResult.url;

        print('[SKEO] Final URL after redirects: $finalUrl');
        print('[SKEO] HTML length: ${document.outerHtml.length}');

        if (_isJsRedirectPage(document)) {
          print('[SKEO] Got JS redirect page, retrying with cookies...');
          final retry = await _fetchDocumentWithRedirects(tryUrl, effectiveHeaders, cookies);
          if (!_isJsRedirectPage(retry.document)) {
            print('[SKEO] Cookie retry worked!');
            final results = await _resolveFromDocument(retry.document, retry.url, urlHoster, effectiveHeaders, cookies);
            if (results.isNotEmpty) return results;
          }
          continue;
        }

        final results = await _resolveFromDocument(document, finalUrl, urlHoster, effectiveHeaders, cookies);
        if (results.isNotEmpty) return results;
        print('[SKEO] No streams found, trying next URL...');
      }

      print('[SKEO] ========== All URLs exhausted, 0 results ==========');
      return {};
    } catch (e, st) {
      print('[SKEO] ERROR: $e');
      print('[SKEO] STACKTRACE: $st');
      rethrow;
    }
  }

  static Future<Set<String>> _resolveFromDocument(
    Document document,
    String currentUrl,
    Hoster? urlHoster,
    Map<String, String> headers,
    Map<String, String> cookies,
  ) async {
    final fitted = urlHoster ?? Hoster.autoFromDocument(document, currentUrl);
    print('[SKEO] _resolveFromDocument: hoster=${fitted?.name ?? "NONE"}, url=$currentUrl');

    var redirected = document;
    var redirectUrl = currentUrl;
    if (fitted != null) {
      redirected = await fitted.redirect(
        document,
        currentUrl,
        (target) async {
          print('[SKEO] Following hoster redirect to: $target');
          final r = await _fetchDocumentWithRedirects(target, headers, cookies);
          redirectUrl = r.url;
          return r.document;
        },
      );
    }

    final results = resolveStreamsFromDocument(
      redirected,
      sourceUrl: redirected != document ? redirectUrl : currentUrl,
      hoster: fitted,
    );
    print('[SKEO] Results: $results');
    return results;
  }

  static bool _isJsRedirectPage(Document document) {
    final title = document.querySelector('title')?.text.trim().toLowerCase() ?? '';
    final html = document.outerHtml;
    final hasRedirectTitle = title.contains('redirect');
    final hasPermanentToken = html.contains('permanentToken');
    final isShortPage = html.length < 2000;
    final result = hasRedirectTitle || (hasPermanentToken && isShortPage);
    print('[SKEO] _isJsRedirectPage: title="$title", permanentToken=$hasPermanentToken, htmlLen=${html.length}, result=$result');
    return result;
  }

  static String _toEmbedUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return url;
    if (segments.first == 'e') return url;
    return uri.replace(path: '/e/${segments.last}').toString();
  }

  static Set<String> filterNotSample(Iterable<String> links) => filterTestVideos(links).toSet();

  static Future<Set<String>> filterReachable(
    Iterable<String> links, {
    http.Client? client,
    Map<String, String> headers = const {},
  }) async {
    final effectiveClient = client ?? http.Client();
    final shouldClose = client == null;
    final effectiveHeaders = {..._defaultHeaders, ...headers};

    try {
      final reachable = <String>{};
      for (final link in links.toSet()) {
        final response = await effectiveClient.head(Uri.parse(link), headers: effectiveHeaders);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          reachable.add(link);
        }
      }
      return reachable;
    } finally {
      if (shouldClose) effectiveClient.close();
    }
  }

  /// Fetch document using dart:io HttpClient so we can manually follow redirects
  /// and track the final URL (which http.Client doesn't expose).
  static Future<_FetchResult> _fetchDocumentWithRedirects(
    String url,
    Map<String, String> headers,
    Map<String, String> cookies,
  ) async {
    final ioClient = io.HttpClient();
    ioClient.userAgent = null; // We set our own User-Agent header

    var currentUrl = url;
    const maxRedirects = 10;

    try {
      for (var i = 0; i < maxRedirects; i++) {
        print('[SKEO] _fetch: GET $currentUrl (attempt ${i + 1})');

        final request = await ioClient.getUrl(Uri.parse(currentUrl));

        // Set headers
        headers.forEach((key, value) {
          request.headers.set(key, value);
        });

        // Set cookies
        if (cookies.isNotEmpty) {
          final cookieStr = cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
          request.headers.set('Cookie', cookieStr);
        }

        // Don't auto-follow redirects
        request.followRedirects = false;

        final response = await request.close();
        final statusCode = response.statusCode;

        // Collect cookies from response
        for (final cookie in response.cookies) {
          cookies[cookie.name] = cookie.value;
        }

        print('[SKEO] _fetch: status=$statusCode, cookies=${cookies.keys.toList()}');

        // Handle redirects manually
        if (statusCode == 301 || statusCode == 302 || statusCode == 303 || statusCode == 307 || statusCode == 308) {
          final location = response.headers.value('location');
          if (location != null) {
            // Resolve relative URLs
            final resolved = Uri.parse(currentUrl).resolve(location).toString();
            print('[SKEO] _fetch: redirect -> $resolved');
            // Drain the response body
            await response.drain();
            currentUrl = resolved;
            continue;
          }
        }

        // Read body
        final body = await response.transform(utf8.decoder).join();
        print('[SKEO] _fetch: body length=${body.length}');

        final preview = body.length > 500 ? body.substring(0, 500) : body;
        print('[SKEO] _fetch: body preview:\n$preview');

        final doc = html_parser.parse(body);
        return _FetchResult(doc, currentUrl);
      }

      // Max redirects exceeded
      print('[SKEO] _fetch: max redirects exceeded');
      return _FetchResult(html_parser.parse(''), currentUrl);
    } finally {
      ioClient.close();
    }
  }

  static Set<String> _videoSources(Document document, String sourceUrl) {
    final out = <String>{};
    for (final video in document.getElementsByTagName('video')) {
      final src = resolveUrl(sourceUrl, video.attributes['src']);
      if (src != null) out.add(src);
      for (final source in video.getElementsByTagName('source')) {
        final nested = resolveUrl(sourceUrl, source.attributes['src']);
        if (nested != null) out.add(nested);
      }
    }
    return out;
  }

  static Set<String> _videosInDocument(Document document, String sourceUrl) {
    final html = document.outerHtml;
    final clean = _cleanRegex.allMatches(html).map((m) => m.group(0)?.trim()).whereType<String>();
    final query = _queryRegex.allMatches(html).map((m) => m.group(0)?.trim()).whereType<String>();

    return {...clean, ...query}.map((v) => resolveUrl(sourceUrl, v)).whereType<String>().toSet();
  }
}

class _FetchResult {
  final Document document;
  final String url;
  _FetchResult(this.document, this.url);
}
