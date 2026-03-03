final Set<String> _testVideoHosts = {
  'test-videos.co.uk',
  'test-streams.mux.dev',
  'bbb3d.renderfarming.net',
};

final Set<String> _testVideos = {
  'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_2MB.mp4',
  'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  'http://distribution.bbb3d.renderfarming.net/video/mp4/bbb_sunflower_1080p_30fps_normal.mp4',
};

List<String> filterTestVideos(Iterable<String> links) {
  return links.where((link) {
    if (_testVideos.contains(link)) {
      return false;
    }

    final uri = Uri.tryParse(link);
    if (uri == null || uri.host.isEmpty) {
      return true;
    }

    return !_testVideoHosts.contains(uri.host.toLowerCase());
  }).toList(growable: false);
}
