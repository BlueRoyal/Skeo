extension SwapCase on String {
  String swapCase() {
    final buffer = StringBuffer();
    for (final rune in runes) {
      final char = String.fromCharCode(rune);
      if (char.toUpperCase() == char && char.toLowerCase() != char) {
        buffer.write(char.toLowerCase());
      } else if (char.toLowerCase() == char && char.toUpperCase() != char) {
        buffer.write(char.toUpperCase());
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }
}
