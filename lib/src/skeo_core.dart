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
    'Accept-Encoding': 'gzip, deflate',
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

    final effectiveClient = client ?? http.Client();
    final shouldClose = client == null;
    final effectiveHeaders = {..._defaultHeaders, ...headers};

    // Cookie jar for this session
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

      print('[SKEO] Fetching document (1st request)...');
      var fetchResult = await _fetchDocument(firstUrl, effectiveClient, effectiveHeaders, cookies);
      var document = fetchResult.document;
      var currentUrl = fetchResult.url;

      // Detect JS redirect page: small body with "Redirecting..." title
      // and no real content. Re-fetch with cookies that were set.
      if (_isJsRedirectPage(document)) {
        print('[SKEO] Detected JS redirect page. Cookies collected: ${cookies.keys.toList()}');
        print('[SKEO] Fetching document (2nd request with cookies)...');
        fetchResult = await _fetchDocument(firstUrl, effectiveClient, effectiveHeaders, cookies);
        document = fetchResult.document;
        currentUrl = fetchResult.url;

        // If still a redirect page, try without the token requirement
        if (_isJsRedirectPage(document)) {
          print('[SKEO] Still a redirect page. Trying /e/ embed URL...');
          // Some VOE URLs work better with /e/ prefix
          final embedUrl = _toEmbedUrl(firstUrl);
          if (embedUrl != firstUrl) {
            print('[SKEO] Trying embed URL: $embedUrl');
            fetchResult = await _fetchDocument(embedUrl, effectiveClient, effectiveHeaders, cookies);
            document = fetchResult.document;
            currentUrl = fetchResult.url;
          }
        }
      }

      print('[SKEO] Document ready, url=$currentUrl, HTML length=${document.outerHtml.length}');

      final fitted = urlHoster ?? Hoster.autoFromDocument(document, currentUrl);
      print('[SKEO] Fitted hoster: ${fitted?.name ?? "NONE"}');

      Document redirected = document;
      if (fitted != null) {
        redirected = await fitted.redirect(
          document,
          currentUrl,
          (target) async {
            print('[SKEO] Following redirect to: $target');
            final r = await _fetchDocument(target, effectiveClient, effectiveHeaders, cookies);
            currentUrl = r.url;
            return r.document;
          },
        );
      }

      if (redirected != document) {
        print('[SKEO] Hoster redirect happened, new url=$currentUrl');
      }

      final results = resolveStreamsFromDocument(redirected, sourceUrl: currentUrl, hoster: fitted);
      print('[SKEO] ========== FINAL RESULTS: $results ==========');
      return results;
    } catch (e, st) {
      print('[SKEO] ERROR: $e');
      print('[SKEO] STACKTRACE: $st');
      rethrow;
    } finally {
      if (shouldClose) effectiveClient.close();
    }
  }

  /// Detect the VOE JS redirect stub page
  static bool _isJsRedirectPage(Document document) {
    final title = document.querySelector('title')?.text.trim().toLowerCase() ?? '';
    final bodyLen = document.body?.text.trim().length ?? 0;
    final isRedirect = title.contains('redirect') && bodyLen < 100;
    print('[SKEO] _isJsRedirectPage: title="$title", bodyTextLen=$bodyLen, result=$isRedirect');
    return isRedirect;
  }

  /// Convert a VOE URL to embed format: https://voe.sx/abc -> https://voe.sx/e/abc
  static String _toEmbedUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final segments = uri.pathSegments;
    if (segments.isEmpty) return url;
    // Already an embed URL
    if (segments.first == 'e') return url;
    // Convert: /xvdpt9qbzek2 -> /e/xvdpt9qbzek2
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

  /// Fetch a document and handle cookie persistence
  static Future<_FetchResult> _fetchDocument(
    String url,
    http.Client client,
    Map<String, String> headers,
    Map<String, String> cookies,
  ) async {
    // Add cookies to request
    final requestHeaders = {...headers};
    if (cookies.isNotEmpty) {
      final cookieHeader = cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
      requestHeaders['Cookie'] = cookieHeader;
      print('[SKEO] _fetchDocument: sending cookies: $cookieHeader');
    }

    print('[SKEO] _fetchDocument: GET $url');
    final response = await client.get(Uri.parse(url), headers: requestHeaders);
    print('[SKEO] _fetchDocument: status=${response.statusCode}, body length=${response.body.length}');

    // Extract cookies from Set-Cookie headers
    final setCookie = response.headers['set-cookie'];
    if (setCookie != null) {
      _parseCookies(setCookie, cookies);
      print('[SKEO] _fetchDocument: cookies after parsing: ${cookies.keys.toList()}');
    }

    // Handle HTTP 302/301 redirects (just in case)
    if (response.statusCode == 301 || response.statusCode == 302) {
      final location = response.headers['location'];
      if (location != null) {
        print('[SKEO] _fetchDocument: HTTP redirect to $location');
        return _fetchDocument(location, client, headers, cookies);
      }
    }

    final preview = response.body.length > 500 ? response.body.substring(0, 500) : response.body;
    print('[SKEO] _fetchDocument: body preview:\n$preview');

    final doc = html_parser.parse(response.body);
    return _FetchResult(doc, url);
  }

  /// Parse Set-Cookie header(s) into our cookie jar
  static void _parseCookies(String setCookieHeader, Map<String, String> cookies) {
    // Set-Cookie can contain multiple cookies separated by comma,
    // but also date strings contain commas. Split on pattern "name=value"
    // at the start of each cookie.
    final parts = setCookieHeader.split(RegExp(r',(?=[A-Za-z_][A-Za-z0-9_]*=)'));
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      // Extract just name=value (before first ;)
      final semicolonIdx = trimmed.indexOf(';');
      final nameValue = semicolonIdx > 0 ? trimmed.substring(0, semicolonIdx) : trimmed;
      final equalsIdx = nameValue.indexOf('=');
      if (equalsIdx > 0) {
        final name = nameValue.substring(0, equalsIdx).trim();
        final value = nameValue.substring(equalsIdx + 1).trim();
        cookies[name] = value;
      }
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
