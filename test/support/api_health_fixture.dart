import 'package:fl_clash/common/api_health.dart';

class ApiHealthFixture extends ApiHealthService {
  ApiHealthFixture(this.endpoint);

  final Uri endpoint;

  @override
  Future<List<Uri>> loadVerifiedCandidateEndpoints() async => [endpoint];

  @override
  Future<Uri?> loadLastSuccessfulEndpoint() async => null;

  @override
  Future<void> rememberSuccessfulEndpoint(Uri endpoint) async {}
}
