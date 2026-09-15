import 'package:fl_clash/common/invite_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('appends the invite code inside the configured hash route', () {
    expect(
      buildInviteLink({
        'InviteLink': 'https://share.fengwo.live#/register?code=',
      }, '8rFTfl6O'),
      'https://share.fengwo.live#/register?code=8rFTfl6O',
    );
  });

  test('uses the configured domain and preserves existing parameters', () {
    expect(
      buildInviteLink({
        'InviteLink': ' https://new.example.com/register?source=app&code= ',
      }, ' ABC123 '),
      'https://new.example.com/register?source=app&code=ABC123',
    );
  });

  test('encodes the code as a single query value', () {
    final link = buildInviteLink({
      'InviteLink': 'https://share.example.com#/register?code=',
    }, 'A+B&C#D/E?');
    final route = Uri.parse(Uri.parse(link).fragment);
    expect(route.queryParameters, {'code': 'A+B&C#D/E?'});
  });

  test('rejects missing or invalid link configuration', () {
    for (final config in [
      null,
      [],
      {},
      {'InviteLink': 123},
      {'InviteLink': ''},
      {'InviteLink': '/register?code='},
      {'InviteLink': 'javascript:alert(1)'},
      {'InviteLink': 'https://'},
      {'InviteLink': 'https://bad host.example/register?code='},
    ]) {
      expect(() => buildInviteLink(config, 'ABC123'), throwsFormatException);
    }
  });

  test('rejects an empty invite code', () {
    expect(
      () => buildInviteLink({
        'InviteLink': 'https://share.example.com#/register?code=',
      }, '  '),
      throwsFormatException,
    );
  });
}
