import 'package:flutter/material.dart';
import 'package:skeo/skeo.dart';

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

class ExampleHomePage extends StatelessWidget {
  const ExampleHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final resolved = Skeo.filterNotSample(const {
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      'https://cdn.example.org/movie.mp4',
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Skeo Flutter Example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Gefilterte Streams:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (final link in resolved) Text(link),
        ],
      ),
    );
  }
}
