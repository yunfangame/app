import 'dart:async';

import 'package:fl_clash/common/streaming_unlock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classifies a localized Netflix response as unlocked', () {
    final result = classifyStreamingResponse(
      StreamingPlatform.netflix,
      StreamingUnlockResponse(
        statusCode: 200,
        body: '<html></html>',
        finalUri: Uri.parse('https://www.netflix.com/tw-en/title/81215567'),
      ),
    );

    expect(result.status, StreamingUnlockStatus.unlocked);
    expect(result.region, 'TW');
  });

  test('keeps an HTTP challenge separate from a connection failure', () {
    final result = classifyStreamingResponse(
      StreamingPlatform.chatGpt,
      StreamingUnlockResponse(
        statusCode: 403,
        body: 'challenge required',
        finalUri: Uri.parse('https://chatgpt.com/'),
      ),
    );

    expect(result.status, StreamingUnlockStatus.reachable);
  });

  test('detects explicit regional restrictions', () {
    final result = classifyStreamingResponse(
      StreamingPlatform.disneyPlus,
      StreamingUnlockResponse(
        statusCode: 200,
        body: '',
        finalUri: Uri.parse('https://www.disneyplus.com/welcome/unavailable'),
      ),
    );

    expect(result.status, StreamingUnlockStatus.restricted);
  });

  test('does not treat a Disney route embedded in the page as restricted', () {
    final result = classifyStreamingResponse(
      StreamingPlatform.disneyPlus,
      StreamingUnlockResponse(
        statusCode: 200,
        body: '<script>routes = ["/welcome/unavailable"]</script>',
        finalUri: Uri.parse('https://www.disneyplus.com/en-jp/'),
      ),
    );

    expect(result.status, StreamingUnlockStatus.unlocked);
    expect(result.region, 'JP');
  });

  test(
    'does not treat static restriction text in a working page as blocked',
    () {
      const pageBody = '''
      <script>
        const errors = [
          'region not supported',
          'not available in your country',
          'unsupported_country',
          'nsez-403',
          '/app-unavailable-in-region'
        ];
      </script>
    ''';

      for (final platform in StreamingPlatform.values) {
        final result = classifyStreamingResponse(
          platform,
          StreamingUnlockResponse(
            statusCode: 200,
            body: pageBody,
            finalUri: Uri.parse('https://service.example/home'),
          ),
        );

        expect(
          result.status,
          StreamingUnlockStatus.unlocked,
          reason: platform.name,
        );
        expect(result.isPageAccessible, isTrue);
      }
    },
  );

  test('treats an HTTP challenge as page reachable, not region restricted', () {
    final result = classifyStreamingResponse(
      StreamingPlatform.tikTok,
      StreamingUnlockResponse(
        statusCode: 403,
        body: 'region not supported',
        finalUri: Uri.parse('https://www.tiktok.com/'),
      ),
    );

    expect(result.status, StreamingUnlockStatus.reachable);
    expect(result.isPageAccessible, isTrue);
  });

  test('treats HTTP 451 as an explicit regional restriction', () {
    final result = classifyStreamingResponse(
      StreamingPlatform.netflix,
      StreamingUnlockResponse(
        statusCode: 451,
        body: '',
        finalUri: Uri.parse('https://www.netflix.com/'),
      ),
    );

    expect(result.status, StreamingUnlockStatus.restricted);
    expect(result.isPageAccessible, isFalse);
  });

  test('treats server and transport failures as failed', () async {
    final serverResult = classifyStreamingResponse(
      StreamingPlatform.tikTok,
      StreamingUnlockResponse(
        statusCode: 503,
        body: '',
        finalUri: Uri.parse('https://www.tiktok.com/'),
      ),
    );
    final tester = StreamingUnlockTester(
      fetcher: (_) => throw const FormatException('offline'),
    );

    expect(serverResult.status, StreamingUnlockStatus.failed);
    expect(
      (await tester.test(StreamingPlatform.tikTok)).status,
      StreamingUnlockStatus.failed,
    );
  });

  test('checks Netflix reachability before verifying title access', () async {
    final requested = <Uri>[];
    final tester = StreamingUnlockTester(
      retryDelay: Duration.zero,
      fetcher: (uri) async {
        requested.add(uri);
        return StreamingUnlockResponse(
          statusCode: 200,
          body: '',
          finalUri: uri.path == '/'
              ? Uri.parse('https://www.netflix.com/jp/')
              : Uri.parse('https://www.netflix.com/jp-en/title/81215567'),
        );
      },
    );

    final result = await tester.test(StreamingPlatform.netflix);

    expect(requested.map((uri) => uri.path), ['/', '/title/81215567']);
    expect(result.status, StreamingUnlockStatus.unlocked);
    expect(result.region, 'JP');
  });

  test('keeps preliminary reachability when verification times out', () async {
    final tester = StreamingUnlockTester(
      requestTimeout: const Duration(milliseconds: 20),
      retryDelay: Duration.zero,
      fetcher: (uri) async {
        if (uri.path == '/') {
          return StreamingUnlockResponse(
            statusCode: 200,
            body: '',
            finalUri: Uri.parse('https://www.netflix.com/jp/'),
          );
        }
        return Completer<StreamingUnlockResponse>().future;
      },
    );

    final result = await tester.test(StreamingPlatform.netflix);

    expect(result.status, StreamingUnlockStatus.reachable);
    expect(result.region, 'JP');
    expect(result.failureReason, StreamingUnlockFailureReason.timeout);
  });

  test('retries transient failures once', () async {
    var attempts = 0;
    final tester = StreamingUnlockTester(
      retryDelay: Duration.zero,
      fetcher: (_) async {
        attempts++;
        if (attempts == 1) throw TimeoutException('slow');
        return StreamingUnlockResponse(
          statusCode: 200,
          body: '',
          finalUri: Uri.parse('https://www.disneyplus.com/'),
        );
      },
    );

    final result = await tester.test(StreamingPlatform.disneyPlus);

    expect(attempts, 2);
    expect(result.status, StreamingUnlockStatus.unlocked);
  });

  test('limits all-platform checks to two concurrent requests', () async {
    var active = 0;
    var peak = 0;
    final tester = StreamingUnlockTester(
      maxAttempts: 1,
      fetcher: (uri) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        active--;
        return StreamingUnlockResponse(
          statusCode: 200,
          body: '',
          finalUri: uri,
        );
      },
    );

    final results = await tester.testAll(
      StreamingPlatform.values,
      maxConcurrent: 2,
    );

    expect(results, hasLength(StreamingPlatform.values.length));
    expect(peak, 2);
  });
}
