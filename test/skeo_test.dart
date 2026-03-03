import 'package:html/parser.dart' as html_parser;
import 'package:skeo/skeo.dart';
import 'package:test/test.dart';

void main() {
  test('resolves video tags and raw links', () {
    final doc = html_parser.parse('''
      <html>
        <body>
          <video src="/video/main.mp4"><source src="/video/alt.m3u8"></video>
          <script>var x = "https://cdn.example.org/file.webm";</script>
        </body>
      </html>
    ''');

    final links = Skeo.resolveStreamsFromDocument(doc, sourceUrl: 'https://example.org/page');
    expect(links, contains('https://example.org/video/main.mp4'));
    expect(links, contains('https://example.org/video/alt.m3u8'));
    expect(links, contains('https://cdn.example.org/file.webm'));
  });

  test('luluvdo hoster converts URL and extracts stream', () {
    final hoster = Hoster.autoFromUrl('https://luluvdo.com/abc123');
    expect(hoster, isNotNull);
    expect(hoster!.updateUrl('https://luluvdo.com/abc123'), contains('file_code=abc123'));

    final doc = html_parser.parse('<script>file: "https://media.example.com/stream.mp4"</script>');
    final links = hoster.resolveStreams(doc, 'https://luluvdo.com/abc123');
    expect(links, contains('https://media.example.com/stream.mp4'));
  });

  test('filters sample links', () {
    final filtered = Skeo.filterNotSample({
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      'https://my.cdn.com/video.mp4',
    });

    expect(filtered, contains('https://my.cdn.com/video.mp4'));
    expect(filtered, isNot(contains('https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8')));
  });
}
