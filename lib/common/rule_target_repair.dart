({List<String> rules, int replacedCount}) repairRuleTargets(
  List<String> rules, {
  required Set<String> availableTargets,
  required List<String> subscriptionRules,
}) {
  String? matchTarget(List<String> source) {
    for (final rule in source.reversed) {
      final parts = rule.split(',');
      if (parts.length == 2 && parts.first.trim().toUpperCase() == 'MATCH') {
        final target = parts.last.trim();
        if (availableTargets.contains(target)) return target;
      }
    }
    return null;
  }

  final fallback =
      matchTarget(subscriptionRules) ?? matchTarget(rules) ?? 'GLOBAL';
  var replacedCount = 0;
  final repaired = rules.map((rule) {
    final parts = rule.split(',');
    if (parts.length < 2 || parts.first.trim().toUpperCase() == 'SUB-RULE') {
      return rule;
    }
    var targetIndex = parts.length - 1;
    while (targetIndex > 1 &&
        const {'no-resolve', 'src'}.contains(parts[targetIndex].trim())) {
      targetIndex--;
    }
    final target = parts[targetIndex].trim();
    if (target.isEmpty || availableTargets.contains(target)) return rule;
    parts[targetIndex] = fallback;
    if (target.toUpperCase() != 'MATCH') replacedCount++;
    return parts.join(',');
  }).toList();
  return (rules: repaired, replacedCount: replacedCount);
}
