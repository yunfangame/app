class TunFailure implements Exception {
  const TunFailure(
    this.stage,
    this.code, {
    this.osErrorCode,
    this.installerExitCode,
    this.cause,
  });

  factory TunFailure.elevation(int error) =>
      TunFailure('authorization', switch (error) {
        1223 => 'authorization_cancelled',
        5 => 'access_denied',
        2 || 3 => 'helper_missing',
        577 || 1275 => 'security_policy_blocked',
        _ => 'elevation_failed',
      }, osErrorCode: error);

  factory TunFailure.installerExit(int exitCode) => TunFailure(
    'service_install',
    switch (exitCode) {
      1223 => 'authorization_cancelled',
      5 => 'access_denied',
      2 || 3 => 'helper_missing',
      577 || 1275 => 'security_policy_blocked',
      1053 => 'service_timeout',
      1067 => 'service_exited',
      1072 => 'service_pending_delete',
      10048 => 'helper_port_in_use',
      _ => 'installer_failed',
    },
    osErrorCode: switch (exitCode) {
      2 ||
      3 ||
      5 ||
      577 ||
      1053 ||
      1067 ||
      1072 ||
      1223 ||
      1275 ||
      10048 => exitCode,
      _ => null,
    },
    installerExitCode: exitCode,
  );

  final String stage;
  final String code;
  final int? osErrorCode;
  final int? installerExitCode;
  final Object? cause;

  Map<String, Object?> toDiagnosticData() => {
    'stage': stage,
    'reason': code,
    if (osErrorCode != null) 'os_error_code': osErrorCode,
    if (installerExitCode != null) 'installer_exit_code': installerExitCode,
    if (cause != null) 'cause': '$cause',
  };

  @override
  String toString() =>
      'TunFailure($stage, $code, $osErrorCode, $installerExitCode)';
}
