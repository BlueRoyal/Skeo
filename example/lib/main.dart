import 'package:flutter/material.dart';
import 'package:skeo/skeo.dart';
import 'package:video_player/video_player.dart';

void main() {
  runApp(const SkeoExampleApp());
}

class SkeoExampleApp extends StatelessWidget {
  const SkeoExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Skeo Example',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const ExampleHomePage(),
    );
  }
}

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({super.key});

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage> {
  static const _defaultHosterUrl = 'https://voe.sx/d6ur6cbwu4og';

  final TextEditingController _hosterUrlController =
      TextEditingController(text: _defaultHosterUrl);

  List<String> _resolvedStreams = const [];
  VideoPlayerController? _videoController;
  String? _selectedStream;
  String? _errorMessage;
  bool _isResolving = false;
  bool _isPlayerInitializing = false;

  @override
  void initState() {
    super.initState();
    _resolveFromHosterUrl();
  }

  Future<void> _resolveFromHosterUrl() async {
    final url = _hosterUrlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _errorMessage = 'Bitte eine Hoster-URL eingeben.';
        _resolvedStreams = const [];
      });
      return;
    }

    setState(() {
      _isResolving = true;
      _errorMessage = null;
      _resolvedStreams = const [];
      _selectedStream = null;
    });

    try {
      final resolved = (await Skeo.resolveStreamsFromUrl(url)).toList();
      final filtered = Skeo.filterNotSample(resolved).toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _resolvedStreams = filtered;
        if (filtered.isEmpty) {
          _errorMessage =
              'Keine Stream-URLs gefunden. Prüfe den Link oder versuche einen anderen Hoster.';
        }
      });

      if (filtered.isNotEmpty) {
        await _initializePlayer(filtered.first);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Fehler beim Auflösen: $error';
      });
      await _disposePlayer();
    } finally {
      if (mounted) {
        setState(() {
          _isResolving = false;
        });
      }
    }
  }

  Future<void> _initializePlayer(String streamUrl) async {
    await _disposePlayer();

    setState(() {
      _isPlayerInitializing = true;
      _selectedStream = streamUrl;
    });

    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(streamUrl));
      await controller.initialize();
      await controller.play();
      await controller.setLooping(true);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _videoController = controller;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Stream kann nicht abgespielt werden: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPlayerInitializing = false;
        });
      }
    }
  }

  Future<void> _disposePlayer() async {
    final existing = _videoController;
    _videoController = null;
    if (existing != null) {
      await existing.dispose();
    }
  }

  @override
  void dispose() {
    _hosterUrlController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Skeo Flutter Example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Hoster-Link auflösen (VOE-Beispiel) und direkt abspielen:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _hosterUrlController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Hoster URL',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isResolving ? null : _resolveFromHosterUrl,
            icon: const Icon(Icons.play_circle_fill),
            label: Text(_isResolving ? 'Löse auf…' : 'Streams auflösen'),
          ),
          const SizedBox(height: 16),
          if (_errorMessage != null)
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_isResolving) ...[
            const SizedBox(height: 8),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_resolvedStreams.isNotEmpty) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedStream,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Gefundene Stream-URL auswählen',
              ),
              items: [
                for (final link in _resolvedStreams)
                  DropdownMenuItem(value: link, child: Text(link)),
              ],
              onChanged: (selected) {
                if (selected != null) {
                  _initializePlayer(selected);
                }
              },
            ),
            const SizedBox(height: 16),
            if (_isPlayerInitializing)
              const Center(child: CircularProgressIndicator())
            else if (_videoController != null)
              AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              ),
            const SizedBox(height: 16),
            const Text(
              'Aufgelöste Streams:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final link in _resolvedStreams) Text(link),
          ],
        ],
      ),
    );
  }
}
