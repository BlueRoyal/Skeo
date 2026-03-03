import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'hoster.dart';
import 'test_videos.dart';
import 'url_utils.dart';

class Skeo {
  Skeo._();

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
    final hosterSpecific = fitted?.resolveStreams(document, sourceUrl) ?? const <String>{};

    return {
      ...hosterSpecific,
      ..._videoSources(document, sourceUrl),
      ..._videosInDocument(document, sourceUrl),
    };
  }

  static Future<Set<String>> resolveStreamsFromUrl(
    String url, {
    http.Client? client,
    Hoster? hoster,
    Map<String, String> headers = const {},
  }) async {
    final effectiveClient = client ?? http.Client();
    final shouldClose = client == null;

    try {
      final urlHoster = hoster ?? Hoster.autoFromUrl(url);
      final firstUrl = urlHoster?.updateUrl(url) ?? url;
      final document = await _fetchDocument(firstUrl, effectiveClient, headers);
      final fitted = urlHoster ?? Hoster.autoFromDocument(document, firstUrl);
      final redirected = fitted == null
          ? document
          : await fitted.redirect(
              document,
              firstUrl,
              (target) => _fetchDocument(target, effectiveClient, headers),
            );

      return resolveStreamsFromDocument(redirected, sourceUrl: redirected.documentUri ?? firstUrl, hoster: fitted);
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

    try {
      final reachable = <String>{};
      for (final link in links.toSet()) {
        final response = await effectiveClient.head(Uri.parse(link), headers: headers);
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
    final response = await client.get(Uri.parse(url), headers: headers);
    final doc = html_parser.parse(response.body);
    doc.documentUri = url;
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
