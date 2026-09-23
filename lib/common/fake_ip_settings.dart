List<String> normalizeFakeIpFilters(String value) {
  return value
      .split(RegExp(r'\r\n?|\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toSet()
      .toList();
}

bool isValidFakeIpFilter(String value) {
  final entry = value.trim();
  if (entry.isEmpty || RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(entry)) {
    return false;
  }
  final lower = entry.toLowerCase();
  if (lower.startsWith('geosite:') || lower.startsWith('rule-set:')) {
    final names = entry.substring(entry.indexOf(':') + 1);
    return names.split(',').every((name) => name.isNotEmpty);
  }
  if (RegExp(r'[:/\\?#,]').hasMatch(entry)) return false;
  final parts = entry.split('.');
  for (var index = 0; index < parts.length; index++) {
    final part = parts[index];
    if (part.isEmpty && (index != 0 || parts.length == 1)) return false;
    if (part.contains('+') &&
        (part != '+' || index != 0 || parts.length == 1)) {
      return false;
    }
    if (part.contains('*') && part != '*') return false;
  }
  return true;
}

bool isValidFakeIpRange(String value) {
  final match = RegExp(
    r'^((?:0|[1-9][0-9]{0,2})\.){3}(0|[1-9][0-9]{0,2})/(0|[1-9][0-9]?)$',
  ).firstMatch(value.trim());
  if (match == null) return false;
  final parts = value.trim().split('/');
  if (int.parse(parts.last) > 29) return false;
  return parts.first.split('.').every((part) => int.parse(part) <= 255);
}
