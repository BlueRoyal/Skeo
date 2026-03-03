# Skeo (Flutter Package)

Skeo ist ein Flutter/Dart-Package zum Auflösen von Stream-URLs (z. B. `.mp4`, `.m3u8`) aus Embed-Seiten und bekannten Hostern.

## Installation

```yaml
dependencies:
  skeo: ^1.0.0
```

## Verwendung

```dart
import 'package:skeo/skeo.dart';

final streams = await Skeo.resolveStreamsFromUrl('https://example.com/embed/abc123');
final filtered = Skeo.filterNotSample(streams);
```

## Flutter Example starten

```bash
cd example
flutter pub get
flutter run
```

## API

- `Skeo.resolveStreamsFromUrl(...)`
- `Skeo.resolveStreamsFromDocument(...)`
- `Skeo.filterNotSample(...)`
- `Skeo.filterReachable(...)`

Unterstützte Hoster:

- LuluVDO / LuluStream
- MixDrop
- Speedfiles
- Streamtape
- Vidmoly
- VOE

## Pub.dev Readiness

Für eine Veröffentlichung sind jetzt die wichtigsten Basics enthalten:

- `LICENSE`
- `CHANGELOG.md`
- Flutter-`example/` Projekt
- Lints + Tests

Vor dem Publish lokal prüfen:

```bash
flutter pub get
flutter test
dart pub publish --dry-run
```
