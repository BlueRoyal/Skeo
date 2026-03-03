# Skeo (Dart/Flutter)

Dieses Repository wurde auf ein Dart-Package umgestellt, damit es direkt in Flutter-Projekten nutzbar ist.

## Installation

```yaml
dependencies:
  skeo:
    path: ../skeo
```

## Verwendung

```dart
import 'package:skeo/skeo.dart';

final streams = await Skeo.resolveStreamsFromUrl('https://example.com/embed/abc123');
final filtered = Skeo.filterNotSample(streams);
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
