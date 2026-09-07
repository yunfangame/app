part of '../action.dart';

@Riverpod(keepAlive: true)
class ProxiesAction extends _$ProxiesAction {
  @override
  void build() {}

  @protected
  CoreController get proxyController => coreController;

  void updateGroupsDebounce([Duration? duration]) {
    debouncer.call(FunctionTag.updateGroups, updateGroups, duration: duration);
  }

  void changeProxyDebounce(String groupName, String proxyName) {
    debouncer.call(FunctionTag.changeProxy, (
      String groupName,
      String proxyName,
    ) async {
      await changeProxy(groupName: groupName, proxyName: proxyName);
      updateGroupsDebounce();
    }, args: [groupName, proxyName]);
  }

  Future<void> updateGroups() async {
    try {
      commonPrint.log('updateGroups');
      ref.read(groupsProvider.notifier).value = await retry(
        task: () async {
          final sortType = ref.read(
            proxiesStyleSettingProvider.select((state) => state.sortType),
          );
          final delayMap = ref.read(delayDataSourceProvider);
          final testUrl = ref.read(
            appSettingProvider.select((state) => state.testUrl),
          );
          final selectedMap = ref.read(
            currentProfileProvider.select((state) => state?.selectedMap ?? {}),
          );
          return coreController.getProxiesGroups(
            selectedMap: selectedMap,
            sortType: sortType,
            delayMap: delayMap,
            defaultTestUrl: testUrl,
          );
        },
        retryIf: (res) => res.isEmpty,
      );
    } catch (e) {
      commonPrint.log(
        'updateGroups error: $e',
        logLevel: coreFailureLogLevel(e),
      );
      ref.read(groupsProvider.notifier).value = [];
    }
  }

  void updateCurrentGroupName(String groupName) {
    final profile = ref.read(currentProfileProvider);
    if (profile == null || profile.currentGroupName == groupName) return;
    ref
        .read(profilesProvider.notifier)
        .put(profile.copyWith(currentGroupName: groupName));
  }

  void updateCurrentUnfoldSet(Set<String> value) {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile == null) return;
    ref
        .read(profilesProvider.notifier)
        .put(currentProfile.copyWith(unfoldSet: value));
  }

  void setDelay(Delay delay) {
    ref.read(delayDataSourceProvider.notifier).setDelay(delay);
  }

  void setConnectionDelay(Delay delay) {
    ref.read(connectionDelayDataSourceProvider.notifier).setDelay(delay);
  }

  Future<void> changeProxy({
    required String groupName,
    required String proxyName,
  }) async {
    final fields = {
      'group_ref': diagnosticFingerprint(groupName),
      'node_ref': diagnosticFingerprint(proxyName),
      'close_connections': ref.read(appSettingProvider).closeConnections,
    };
    commonPrint.event('proxy.selection.started', fields: fields);
    try {
      final result = await proxyController.changeProxy(
        ChangeProxyParams(groupName: groupName, proxyName: proxyName),
      );
      if (result.isNotEmpty) {
        commonPrint.event('proxy.selection.rejected', fields: fields);
        throw StateError('proxy_selection_rejected');
      }
      if (!ref.mounted) return;
      if (ref.read(appSettingProvider).closeConnections) {
        commonPrint.event(
          'connections.close_all.requested',
          fields: {...fields, 'reason': 'node_switch'},
        );
        await proxyController.closeConnections();
        commonPrint.event(
          'connections.close_all.completed',
          fields: {...fields, 'reason': 'node_switch'},
        );
      } else {
        await proxyController.resetConnections();
      }
      commonPrint.event('proxy.selection.succeeded', fields: fields);
    } catch (error) {
      commonPrint.event(
        'proxy.selection.failed',
        fields: {
          ...fields,
          'error_type': error.runtimeType.toString(),
          'error': '$error',
        },
      );
      rethrow;
    }
    if (ref.mounted) ref.read(checkIpNumProvider.notifier).add();
  }

  Future<String> updateProvider(
    ExternalProvider provider, {
    bool showLoading = false,
  }) async {
    try {
      if (showLoading) {
        ref.read(isUpdatingProvider(provider.updatingKey).notifier).value =
            true;
      }
      final message = await coreController.updateExternalProvider(
        providerName: provider.name,
      );
      if (message.isNotEmpty) return message;
      ref
          .read(providersProvider.notifier)
          .setProvider(await coreController.getExternalProvider(provider.name));
      return '';
    } finally {
      ref.read(isUpdatingProvider(provider.updatingKey).notifier).value = false;
    }
  }
}
