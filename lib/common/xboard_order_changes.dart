import 'package:fl_clash/common/xboard_auth.dart';
import 'package:flutter/foundation.dart';

class XboardOrderChange {
  XboardOrderChange(XboardLoginResult session)
    : endpoint = session.endpoint,
      authData = session.authData;

  final Uri endpoint;
  final String authData;

  bool matches(XboardLoginResult? session) =>
      session?.endpoint == endpoint && session?.authData == authData;
}

final xboardOrderChanges = ValueNotifier<XboardOrderChange?>(null);

void invalidateXboardOrders(XboardLoginResult session) {
  xboardOrderChanges.value = XboardOrderChange(session);
}
