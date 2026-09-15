String buildInviteLink(Object? config, String code) {
  final value = config is Map ? config['InviteLink'] : null;
  if (value is! String) {
    throw const FormatException('Invite link is not configured');
  }
  final prefix = value.trim();
  final uri = Uri.tryParse(prefix);
  if (uri == null ||
      !['https', 'http'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      RegExp(r'\s').hasMatch(prefix)) {
    throw const FormatException('Invalid invite link');
  }
  final inviteCode = code.trim();
  if (inviteCode.isEmpty) {
    throw const FormatException('Invite code is empty');
  }
  return '$prefix${Uri.encodeQueryComponent(inviteCode)}';
}
