String? resolveUrl(String? baseUrl, String? relUrl) {
  final trimmed = relUrl?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  final relative = Uri.tryParse(trimmed);
  if (relative == null) {
    return null;
  }

  if (relative.hasScheme) {
    return relative.toString();
  }

  final base = baseUrl == null ? null : Uri.tryParse(baseUrl);
  if (base == null) {
    return trimmed;
  }

  return base.resolveUri(relative).toString();
}
