({List<String> rules, int replacedCount}) repairRuleTargets(
  List<String> rules, {
  required Set<String> availableTargets,
  required List<String> subscriptionRules,
}) {
  String? matchTarget(List<String> source) {
    for (final rule in source) {
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
    final type = parts.first.trim().toUpperCase();
    if (parts.length < 2 || type == 'SUB-RULE') {
      return rule;
    }
    final targetIndex = switch (type) {
      'MATCH' => 1,
      'NOT' ||
      'OR' ||
      'AND' ||
      'DOMAIN-REGEX' ||
      'PROCESS-NAME-REGEX' ||
      'PROCESS-PATH-REGEX' => parts.length - 1,
      _ => 2,
    };
    if (targetIndex >= parts.length) return rule;
    final target = parts[targetIndex].trim();
    if (target.isEmpty || availableTargets.contains(target)) return rule;
    parts[targetIndex] = fallback;
    if (target.toUpperCase() != 'MATCH') replacedCount++;
    return parts.join(',');
  }).toList();
  return (rules: repaired, replacedCount: replacedCount);
}
