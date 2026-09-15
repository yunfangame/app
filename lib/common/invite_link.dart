const inviteLinkConfigKey = 'InviteLink';

String buildInviteLinkFromConfig(Object? config, String inviteCode) {
  if (config is! Map) {
    throw const FormatException('Invite link configuration is unavailable');
  }
  final value = config[inviteLinkConfigKey];
  if (value is! String) {
    throw const FormatException('Invite link configuration is unavailable');
  }
  final prefix = value.trim();
  final uri = Uri.tryParse(prefix);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw const FormatException('Invite link configuration is invalid');
  }
  final code = inviteCode.trim();
  if (code.isEmpty) {
    throw const FormatException('Invite code is unavailable');
  }
  return '$prefix$code';
}
