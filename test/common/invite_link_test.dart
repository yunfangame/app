import 'package:fl_clash/common/invite_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds an invite link from the remote configuration', () {
    expect(
      buildInviteLinkFromConfig(const {
        'InviteLink': 'https://share.fengwo.live#/register?code=',
      }, 'SIQU5wev'),
      'https://share.fengwo.live#/register?code=SIQU5wev',
    );
  });

  test('rejects a missing or insecure invite link', () {
    expect(
      () => buildInviteLinkFromConfig(const {}, 'SIQU5wev'),
      throwsFormatException,
    );
    expect(
      () => buildInviteLinkFromConfig(const {
        'InviteLink': 'http://share.example/register?code=',
      }, 'SIQU5wev'),
      throwsFormatException,
    );
  });
}
