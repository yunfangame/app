import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GlobalState exposes a fallback accent color before plugin startup', () {
    expect(GlobalState().accentColor, const Color(defaultPrimaryColor));
  });

  test('stale account node results cannot replace the active account', () {
    final state = GlobalState();
    final first = _session('account-a');
    final second = _session('account-b');
    final firstRevision = state.activateXboardSession(first);
    final secondRevision = state.activateXboardSession(second);

    expect(
      state.setXboardNodesForSession(first, firstRevision, [
        _node('Account A node'),
      ]),
      isFalse,
    );
    expect(
      state.setXboardNodesForSession(second, secondRevision, [
        _node('Account B node'),
      ]),
      isTrue,
    );
    expect(state.xboardNodes.single.name, 'Account B node');

    state.clearXboardSession();
    expect(
      state.setXboardNodesForSession(second, secondRevision, [
        _node('Late Account B node'),
      ]),
      isFalse,
    );
    expect(state.xboardNodes, isEmpty);
  });
}

XboardLoginResult _session(String account) {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: '$account-token',
    authData: 'Bearer $account',
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: Uri.parse('https://subscribe.example.com/$account'),
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: 1024,
      email: '$account@example.com',
      rawData: const {},
    ),
  );
}

XboardNodeData _node(String name) {
  return XboardNodeData(
    id: name.hashCode,
    name: name,
    type: 'vless',
    rate: 1,
    tags: const [],
    isOnline: true,
    rawData: const {},
  );
}
