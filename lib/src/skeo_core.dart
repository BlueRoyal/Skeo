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

    try {
      final urlHoster = hoster ?? Hoster.autoFromUrl(url);
      print('[SKEO] Detected hoster: ${urlHoster?.name ?? "NONE"}');

      final firstUrl = urlHoster?.updateUrl(url) ?? url;
      print('[SKEO] URL after updateUrl: $firstUrl');

      final uri = Uri.tryParse(firstUrl);
      if (uri != null && !effectiveHeaders.containsKey('Referer')) {
        effectiveHeaders['Referer'] = '${uri.scheme}://${uri.host}/';
      }
      print('[SKEO] Headers: $effectiveHeaders');

      print('[SKEO] Fetching document...');
      final document = await _fetchDocument(firstUrl, effectiveClient, effectiveHeaders);
      print('[SKEO] Document fetched, baseUri=${document.baseUri}');

      final fitted = urlHoster ?? Hoster.autoFromDocument(document, firstUrl);
      print('[SKEO] Fitted hoster after document check: ${fitted?.name ?? "NONE"}');

      final redirected = fitted == null
          ? document
          : await fitted.redirect(
              document,
              firstUrl,
              (target) {
                print('[SKEO] Following redirect to: $target');
                return _fetchDocument(target, effectiveClient, effectiveHeaders);
              },
            );

      if (redirected != document) {
        print('[SKEO] Redirect happened, new baseUri=${redirected.baseUri}');
      }

      final results = resolveStreamsFromDocument(redirected, sourceUrl: redirected.baseUri ?? firstUrl, hoster: fitted);
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

  static Future<Document> _fetchDocument(String url, http.Client client, Map<String, String> headers) async {
    print('[SKEO] _fetchDocument: GET $url');
    final response = await client.get(Uri.parse(url), headers: headers);
    print('[SKEO] _fetchDocument: status=${response.statusCode}, content-length=${response.body.length}');
    print('[SKEO] _fetchDocument: response headers=${response.headers}');

    // Log first 500 chars of body for debugging
    final preview = response.body.length > 500 ? response.body.substring(0, 500) : response.body;
    print('[SKEO] _fetchDocument: body preview:\n$preview');

    final doc = html_parser.parse(response.body);
    doc.baseUri = url;
    return doc;
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
