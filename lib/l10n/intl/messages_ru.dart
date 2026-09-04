// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a ru locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'ru';

  static String m0(current, total) => "${current} / ${total}";

  static String m1(index) => "API-узел ${index}";

  static String m2(reachable, total) => "Доступно API: ${reachable}/${total}";

  static String m3(count) => "Стран и регионов: ${count}";

  static String m4(count) =>
      "${Intl.plural(count, one: '${count} день назад', few: '${count} дня назад', many: '${count} дней назад', other: '${count} дня назад')}";

  static String m5(label) =>
      "Вы уверены, что хотите удалить выбранные ${label}?";

  static String m6(label) => "Вы уверены, что хотите удалить текущий ${label}?";

  static String m7(label) => "Детали {}";

  static String m8(label) => "${label} не может быть пустым";

  static String m9(count) => "${count} записей";

  static String m10(label) => "Текущий ${label} уже существует";

  static String m11(name) => "Для ${name} уже установлена последняя версия";

  static String m12(name) => "${name} обновлено";

  static String m13(name) => "Обновление ${name}...";

  static String m14(count) =>
      "${Intl.plural(count, one: '${count} час назад', few: '${count} часа назад', many: '${count} часов назад', other: '${count} часа назад')}";

  static String m15(count) => "${count} часов";

  static String m16(target) => "${target} является недопустимой политикой";

  static String m17(proxyName) => "${proxyName} является недопустимым прокси";

  static String m18(providerName) =>
      "${providerName} является недопустимым провайдером прокси";

  static String m19(subRule) => "${subRule} является недопустимым подправилом";

  static String m20(count) => "Подключений: ${count}";

  static String m21(appName) =>
      "1. Open System Settings > Privacy & Security\n2. Choose Location Services\n3. Find and check ${appName} in the right list\n\nAfter completing the setup, return to the app and use it normally. Thank you for your cooperation.";

  static String m22(index) => "Сервер ${index}";

  static String m23(count) =>
      "${Intl.plural(count, one: '${count} минута назад', few: '${count} минуты назад', many: '${count} минут назад', other: '${count} минуты назад')}";

  static String m24(count) =>
      "${Intl.plural(count, one: '${count} месяц назад', few: '${count} месяца назад', many: '${count} месяцев назад', other: '${count} месяца назад')}";

  static String m25(reachable, total) => "Разрешается ${reachable}/${total}";

  static String m26(address) => "${address} прослушивается";

  static String m27(address) => "Не удаётся подключиться к ${address}";

  static String m28(code, stage, error) => "${code} / ${stage}${error}";

  static String m29(address) => "Обратное чтение подтвердило ${address}";

  static String m30(date) => "Следующий сброс тарифа: ${date}";

  static String m31(count) => "Узлов: ${count}";

  static String m32(label) => "${label} пока отсутствуют";

  static String m33(label) => "${label} должно быть числом";

  static String m34(current, total) => "Страница ${current} из ${total}";

  static String m35(count) => "${count}";

  static String m36(label) => "${label} должен быть числом от 1024 до 49151";

  static String m37(count) =>
      "Сохранено: ${count}; активно при включённой замене";

  static String m38(count) => "${count} секунд";

  static String m39(count) => "Выбрано ${count} элементов";

  static String m40(date) =>
      "Срок действия тарифа истёк ${date}. Продлите его, чтобы продолжить работу.";

  static String m41(date) =>
      "Тариф истекает ${date}, менее чем через 3 дня. Продлите его заранее.";

  static String m42(remaining) =>
      "Осталось только ${remaining} ГБ — меньше 10 ГБ. Купите или продлите тариф.";

  static String m43(code) =>
      "Не удалось включить системный прокси (${code}). Переключатель возвращён назад. Экспортируйте журналы для диагностики";

  static String m44(code) =>
      "Не удалось отключить системный прокси (${code}). Отключите его вручную в настройках Windows";

  static String m45(count) => "Заказов: ${count}";

  static String m46(label) => "${label} должен быть URL";

  static String m47(count) =>
      "${Intl.plural(count, one: '${count} год назад', few: '${count} года назад', many: '${count} лет назад', other: '${count} года назад')}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "about": MessageLookupByLibrary.simpleMessage("О программе"),
    "acceleratorHome": MessageLookupByLibrary.simpleMessage("Ускорение"),
    "accessControl": MessageLookupByLibrary.simpleMessage("Контроль доступа"),
    "accessControlAllowDesc": MessageLookupByLibrary.simpleMessage(
      "Разрешить только выбранным приложениям доступ к VPN",
    ),
    "accessControlDesc": MessageLookupByLibrary.simpleMessage(
      "Настройка доступа приложений к прокси",
    ),
    "accessControlNotAllowDesc": MessageLookupByLibrary.simpleMessage(
      "Выбранные приложения будут исключены из VPN",
    ),
    "accessControlSettings": MessageLookupByLibrary.simpleMessage(
      "Настройки контроля доступа",
    ),
    "accessTime": MessageLookupByLibrary.simpleMessage("Время подключения"),
    "account": MessageLookupByLibrary.simpleMessage("Аккаунт"),
    "accountBalance": MessageLookupByLibrary.simpleMessage("Баланс аккаунта"),
    "accountCenterSubtitle": MessageLookupByLibrary.simpleMessage(
      "Управление данными аккаунта и настройками безопасности",
    ),
    "action": MessageLookupByLibrary.simpleMessage("Действие"),
    "action_mode": MessageLookupByLibrary.simpleMessage("Переключить режим"),
    "action_proxy": MessageLookupByLibrary.simpleMessage("Системный прокси"),
    "action_start": MessageLookupByLibrary.simpleMessage("Старт/Стоп"),
    "action_tun": MessageLookupByLibrary.simpleMessage("TUN"),
    "action_view": MessageLookupByLibrary.simpleMessage("Показать/Скрыть"),
    "actions": MessageLookupByLibrary.simpleMessage("Действие"),
    "activateNow": MessageLookupByLibrary.simpleMessage("Активировать"),
    "actualConnectionDelay": MessageLookupByLibrary.simpleMessage(
      "Фактическая задержка",
    ),
    "add": MessageLookupByLibrary.simpleMessage("Добавить"),
    "addProfile": MessageLookupByLibrary.simpleMessage("Добавить профиль"),
    "addProxies": MessageLookupByLibrary.simpleMessage("Добавить прокси"),
    "addProxy": MessageLookupByLibrary.simpleMessage("Добавить прокси"),
    "addProxyGroup": MessageLookupByLibrary.simpleMessage(
      "Добавить группу прокси",
    ),
    "addProxyProviders": MessageLookupByLibrary.simpleMessage(
      "Добавить провайдеров прокси",
    ),
    "addRule": MessageLookupByLibrary.simpleMessage("Добавить правило"),
    "addSsid": MessageLookupByLibrary.simpleMessage("Добавить SSID"),
    "addedRules": MessageLookupByLibrary.simpleMessage("Добавленные правила"),
    "additionalParameters": MessageLookupByLibrary.simpleMessage(
      "Дополнительные параметры",
    ),
    "address": MessageLookupByLibrary.simpleMessage("Адрес"),
    "addressHelp": MessageLookupByLibrary.simpleMessage("Адрес сервера WebDAV"),
    "addressTip": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, введите действительный адрес WebDAV",
    ),
    "advancedConfig": MessageLookupByLibrary.simpleMessage(
      "Расширенная конфигурация",
    ),
    "advancedConfigDesc": MessageLookupByLibrary.simpleMessage(
      "Предоставляет разнообразные варианты конфигурации",
    ),
    "advancedSettings": MessageLookupByLibrary.simpleMessage("Расширенные"),
    "advancedSettingsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Настройте поведение VPN и параметры сети",
    ),
    "agree": MessageLookupByLibrary.simpleMessage("Согласен"),
    "allGeodataUpdated": MessageLookupByLibrary.simpleMessage(
      "Все ресурсы геоданных обновлены",
    ),
    "allPlans": MessageLookupByLibrary.simpleMessage("Все"),
    "allowBypass": MessageLookupByLibrary.simpleMessage(
      "Разрешить приложениям обходить VPN",
    ),
    "allowBypassDesc": MessageLookupByLibrary.simpleMessage(
      "Некоторые приложения могут обходить VPN при включении",
    ),
    "allowLan": MessageLookupByLibrary.simpleMessage("Разрешить LAN"),
    "allowLanDesc": MessageLookupByLibrary.simpleMessage(
      "Разрешить доступ к прокси через локальную сеть",
    ),
    "alreadyHaveAccount": MessageLookupByLibrary.simpleMessage(
      "Уже есть аккаунт?",
    ),
    "announcementCenter": MessageLookupByLibrary.simpleMessage(
      "Центр объявлений",
    ),
    "announcementPosition": m0,
    "announcementTooltip": MessageLookupByLibrary.simpleMessage(
      "Показать объявления",
    ),
    "announcementUnavailableOffline": MessageLookupByLibrary.simpleMessage(
      "Новые объявления недоступны в автономном режиме",
    ),
    "apiEndpointApplied": MessageLookupByLibrary.simpleMessage(
      "Выбран как основной API-сервер для всего приложения",
    ),
    "apiEndpointLabel": m1,
    "apiEndpointsAvailable": m2,
    "apiStatus": MessageLookupByLibrary.simpleMessage("Состояние API"),
    "apiStatusUnavailable": MessageLookupByLibrary.simpleMessage(
      "Состояние API недоступно",
    ),
    "app": MessageLookupByLibrary.simpleMessage("Приложение"),
    "appAccessControl": MessageLookupByLibrary.simpleMessage(
      "Контроль доступа приложений",
    ),
    "appendSystemDns": MessageLookupByLibrary.simpleMessage(
      "Добавить системный DNS",
    ),
    "appendSystemDnsTip": MessageLookupByLibrary.simpleMessage(
      "Принудительно добавить системный DNS к конфигурации",
    ),
    "application": MessageLookupByLibrary.simpleMessage("Приложение"),
    "applicationDesc": MessageLookupByLibrary.simpleMessage(
      "Изменение настроек, связанных с приложением",
    ),
    "applyPreferredIps": MessageLookupByLibrary.simpleMessage("Применить все"),
    "asnLabel": MessageLookupByLibrary.simpleMessage("ASN"),
    "authorized": MessageLookupByLibrary.simpleMessage("Разрешено"),
    "auto": MessageLookupByLibrary.simpleMessage("Авто"),
    "autoCheckUpdate": MessageLookupByLibrary.simpleMessage(
      "Автопроверка обновлений",
    ),
    "autoCheckUpdateDesc": MessageLookupByLibrary.simpleMessage(
      "Автоматически проверять обновления при запуске приложения",
    ),
    "autoCloseConnections": MessageLookupByLibrary.simpleMessage(
      "Автоматическое закрытие соединений",
    ),
    "autoCloseConnectionsDesc": MessageLookupByLibrary.simpleMessage(
      "Автоматически закрывать соединения после смены узла",
    ),
    "autoLaunch": MessageLookupByLibrary.simpleMessage("Автозапуск"),
    "autoLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "Следовать автозапуску системы",
    ),
    "autoRefresh": MessageLookupByLibrary.simpleMessage("Автообновление"),
    "autoRenew": MessageLookupByLibrary.simpleMessage("Автопродление"),
    "autoRun": MessageLookupByLibrary.simpleMessage("Автозапуск"),
    "autoRunDesc": MessageLookupByLibrary.simpleMessage(
      "Автоматический запуск при открытии приложения",
    ),
    "autoSetSystemDns": MessageLookupByLibrary.simpleMessage(
      "Автоматическая настройка системного DNS",
    ),
    "autoUpdate": MessageLookupByLibrary.simpleMessage("Автообновление"),
    "autoUpdateInterval": MessageLookupByLibrary.simpleMessage(
      "Интервал автообновления (минуты)",
    ),
    "automaticLogin": MessageLookupByLibrary.simpleMessage(
      "Входить автоматически",
    ),
    "automaticLoginUnavailable": MessageLookupByLibrary.simpleMessage(
      "Автоматический вход временно недоступен. Войдите вручную или повторите попытку позже",
    ),
    "automaticSelection": MessageLookupByLibrary.simpleMessage("Автовыбор"),
    "availabilityRate": MessageLookupByLibrary.simpleMessage("Доступность"),
    "availableCommissionEmpty": MessageLookupByLibrary.simpleMessage(
      "Нет доступной комиссии",
    ),
    "availableCount": MessageLookupByLibrary.simpleMessage("Доступно"),
    "availableEndpoints": MessageLookupByLibrary.simpleMessage(
      "Доступные серверы",
    ),
    "backToLogin": MessageLookupByLibrary.simpleMessage("Вернуться ко входу"),
    "backup": MessageLookupByLibrary.simpleMessage("Резервное копирование"),
    "backupAndRestore": MessageLookupByLibrary.simpleMessage(
      "Резервное копирование и восстановление",
    ),
    "backupAndRestoreDesc": MessageLookupByLibrary.simpleMessage(
      "Синхронизация данных через WebDAV или файлы",
    ),
    "backupSuccess": MessageLookupByLibrary.simpleMessage(
      "Резервное копирование успешно",
    ),
    "basicConfig": MessageLookupByLibrary.simpleMessage("Базовая конфигурация"),
    "basicConfigDesc": MessageLookupByLibrary.simpleMessage(
      "Глобальное изменение базовых настроек",
    ),
    "basicInfo": MessageLookupByLibrary.simpleMessage("Основная информация"),
    "basicStrategy": MessageLookupByLibrary.simpleMessage("Базовая стратегия"),
    "batteryOptimizationDesc": MessageLookupByLibrary.simpleMessage(
      "To ensure background operation, please disable battery optimization for this app. Tap to go to settings.",
    ),
    "batteryOptimizationStatusTip": MessageLookupByLibrary.simpleMessage(
      "Из-за особенностей системы этот статус не всегда может быть точным.",
    ),
    "bind": MessageLookupByLibrary.simpleMessage("Привязать"),
    "blacklistMode": MessageLookupByLibrary.simpleMessage(
      "Режим черного списка",
    ),
    "bound": MessageLookupByLibrary.simpleMessage("Привязан"),
    "brandName": MessageLookupByLibrary.simpleMessage("FengWo Accelerator"),
    "buyNow": MessageLookupByLibrary.simpleMessage("Купить"),
    "bypassDomain": MessageLookupByLibrary.simpleMessage("Обход домена"),
    "bypassDomainDesc": MessageLookupByLibrary.simpleMessage(
      "Действует только при включенном системном прокси",
    ),
    "cacheCorrupt": MessageLookupByLibrary.simpleMessage(
      "Кэш поврежден. Хотите очистить его?",
    ),
    "campusNetworkApplyFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось применить режим университетской сети. Проверьте подключение и повторите попытку",
    ),
    "campusNetworkDisabled": MessageLookupByLibrary.simpleMessage(
      "Режим университетской сети выключен",
    ),
    "campusNetworkEnabled": MessageLookupByLibrary.simpleMessage(
      "Режим университетской сети включён",
    ),
    "campusNetworkInformation": MessageLookupByLibrary.simpleMessage(
      "Когда режим выключен, используется обычное разрешение CDN. После включения или смены маршрута конфигурация ядра перезагружается автоматически.",
    ),
    "campusNetworkLine": MessageLookupByLibrary.simpleMessage(
      "Входной маршрут",
    ),
    "campusNetworkLine1": MessageLookupByLibrary.simpleMessage("Маршрут 1"),
    "campusNetworkLine2": MessageLookupByLibrary.simpleMessage("Маршрут 2"),
    "campusNetworkLine3": MessageLookupByLibrary.simpleMessage("Маршрут 3"),
    "campusNetworkMode": MessageLookupByLibrary.simpleMessage(
      "Режим университетской сети",
    ),
    "campusNetworkModeSubtitle": MessageLookupByLibrary.simpleMessage(
      "Переключение на выделенные входные маршруты в университетской сети",
    ),
    "campusNetworkSwitch": MessageLookupByLibrary.simpleMessage(
      "Включить режим университетской сети",
    ),
    "campusNetworkSwitchDescription": MessageLookupByLibrary.simpleMessage(
      "Сопоставляет домены узлов с выбранным входным маршрутом",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("Отмена"),
    "cancelOrder": MessageLookupByLibrary.simpleMessage("Отменить заказ"),
    "cancelOrderMessage": MessageLookupByLibrary.simpleMessage(
      "После отмены оплатить заказ нельзя. При необходимости создайте новый заказ.",
    ),
    "cancelOrderTitle": MessageLookupByLibrary.simpleMessage(
      "Отменить этот заказ?",
    ),
    "cancelSelectAll": MessageLookupByLibrary.simpleMessage(
      "Отменить выбор всего",
    ),
    "candidateCount": MessageLookupByLibrary.simpleMessage("Кандидаты"),
    "carrier": MessageLookupByLibrary.simpleMessage("Оператор"),
    "cfApplyFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось применить IP CF. Предыдущая конфигурация восстановлена",
    ),
    "cfApplySuccess": MessageLookupByLibrary.simpleMessage(
      "Оптимальные IP CF применены, конфигурация ядра перезагружена",
    ),
    "cfTargetMissingMessage": MessageLookupByLibrary.simpleMessage(
      "Сначала добавьте домены узлов для замены CF-оптимизацией в удалённую конфигурацию.",
    ),
    "cfTargetMissingTitle": MessageLookupByLibrary.simpleMessage(
      "Целевой домен не настроен",
    ),
    "cfTargetValidationFailed": MessageLookupByLibrary.simpleMessage(
      "IP не прошли TLS-проверку целевых доменов. Конфигурация не изменена",
    ),
    "chainProxy": MessageLookupByLibrary.simpleMessage("Цепочка прокси"),
    "chainProxyActive": MessageLookupByLibrary.simpleMessage(
      "Цепочный прокси запущен",
    ),
    "chainProxyApplyFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось применить конфигурацию. Восстановлена предыдущая",
    ),
    "chainProxyConnectivityFailed": MessageLookupByLibrary.simpleMessage(
      "Проверка цепочного прокси завершилась ошибкой. Он отключён, предыдущая конфигурация восстановлена",
    ),
    "chainProxyDescription": MessageLookupByLibrary.simpleMessage(
      "Управление дополнительным выходом SOCKS5 или HTTP",
    ),
    "chainProxyDirectModeUnsupported": MessageLookupByLibrary.simpleMessage(
      "Сначала выберите режим «Правила» или «Глобальный»",
    ),
    "chainProxyDisabled": MessageLookupByLibrary.simpleMessage(
      "Цепочный прокси не включён",
    ),
    "chainProxyEnabled": MessageLookupByLibrary.simpleMessage(
      "Цепочный прокси запущен",
    ),
    "chainProxyLocked": MessageLookupByLibrary.simpleMessage(
      "Остальные записи заблокированы во время работы",
    ),
    "chainProxyRollbackFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось применить цепочный прокси и восстановить предыдущую конфигурацию. Перезапустите приложение",
    ),
    "chainProxySessionNotice": MessageLookupByLibrary.simpleMessage(
      "После включения трафик идёт через узел подписки, а затем через цепочный прокси.",
    ),
    "chainProxyStopped": MessageLookupByLibrary.simpleMessage(
      "Цепочный прокси остановлен",
    ),
    "changePasswordTitle": MessageLookupByLibrary.simpleMessage(
      "Изменить пароль",
    ),
    "changePlanAction": MessageLookupByLibrary.simpleMessage("Сменить тариф"),
    "checkUpdate": MessageLookupByLibrary.simpleMessage("Проверить обновления"),
    "checkUpdateError": MessageLookupByLibrary.simpleMessage(
      "Текущее приложение уже является последней версией",
    ),
    "checkingApiStatus": MessageLookupByLibrary.simpleMessage(
      "Проверка доступности API...",
    ),
    "checkingLoginStatus": MessageLookupByLibrary.simpleMessage(
      "Проверка состояния входа...",
    ),
    "chooseSpeedTest": MessageLookupByLibrary.simpleMessage("Выбрать сервис"),
    "clearData": MessageLookupByLibrary.simpleMessage("Очистить данные"),
    "clipboardExport": MessageLookupByLibrary.simpleMessage(
      "Экспорт в буфер обмена",
    ),
    "clipboardImport": MessageLookupByLibrary.simpleMessage(
      "Импорт из буфера обмена",
    ),
    "closeAction": MessageLookupByLibrary.simpleMessage("Закрыть"),
    "closeAllConnections": MessageLookupByLibrary.simpleMessage(
      "Закрыть все подключения",
    ),
    "closeAllConnectionsDescription": MessageLookupByLibrary.simpleMessage(
      "Все текущие подключения будут закрыты. Приложения могут подключиться снова автоматически.",
    ),
    "closeConnection": MessageLookupByLibrary.simpleMessage(
      "Закрыть подключение",
    ),
    "cloudflarePreferredIp": MessageLookupByLibrary.simpleMessage(
      "Оптимальный IP CF",
    ),
    "cloudflarePreferredIpDescription": MessageLookupByLibrary.simpleMessage(
      "Поиск более быстрого узла Cloudflare для текущей сети",
    ),
    "color": MessageLookupByLibrary.simpleMessage("Цвет"),
    "colorSchemes": MessageLookupByLibrary.simpleMessage("Цветовые схемы"),
    "columns": MessageLookupByLibrary.simpleMessage("Столбцы"),
    "commission": MessageLookupByLibrary.simpleMessage("Комиссия"),
    "commissionPayoutRecords": MessageLookupByLibrary.simpleMessage(
      "История комиссий",
    ),
    "commissionRate": MessageLookupByLibrary.simpleMessage("Ставка комиссии"),
    "commissionTransfer": MessageLookupByLibrary.simpleMessage("Перевести"),
    "commissionTransferConfirmMessage": MessageLookupByLibrary.simpleMessage(
      "Комиссия будет переведена на баланс аккаунта для покупки тарифов.",
    ),
    "commissionTransferConfirmTitle": MessageLookupByLibrary.simpleMessage(
      "Перевести всю доступную комиссию?",
    ),
    "commissionTransferred": MessageLookupByLibrary.simpleMessage(
      "Комиссия переведена на баланс аккаунта",
    ),
    "commissionWithdraw": MessageLookupByLibrary.simpleMessage("Вывести"),
    "compatible": MessageLookupByLibrary.simpleMessage("Режим совместимости"),
    "completedCount": MessageLookupByLibrary.simpleMessage("Завершено"),
    "configDataDetected": MessageLookupByLibrary.simpleMessage(
      "Данные обнаружены в конфигурации",
    ),
    "confirm": MessageLookupByLibrary.simpleMessage("Подтвердить"),
    "confirmClearAllData": MessageLookupByLibrary.simpleMessage(
      "Вы уверены, что хотите очистить все данные?",
    ),
    "confirmDeleteProxyGroup": MessageLookupByLibrary.simpleMessage(
      "Вы уверены, что хотите удалить текущую группу прокси?",
    ),
    "confirmExitWindow": MessageLookupByLibrary.simpleMessage(
      "Вы уверены, что хотите выйти из текущего окна?",
    ),
    "confirmForceCrashCore": MessageLookupByLibrary.simpleMessage(
      "Вы уверены, что хотите принудительно аварийно завершить работу ядра?",
    ),
    "confirmNewPassword": MessageLookupByLibrary.simpleMessage(
      "Подтвердите новый пароль",
    ),
    "confirmOverwriteTip": MessageLookupByLibrary.simpleMessage(
      "Существующие данные будут перезаписаны после подтверждения",
    ),
    "confirmPassword": MessageLookupByLibrary.simpleMessage(
      "Подтвердите пароль",
    ),
    "confirmReset": MessageLookupByLibrary.simpleMessage("Сбросить"),
    "connected": MessageLookupByLibrary.simpleMessage("Подключено"),
    "connecting": MessageLookupByLibrary.simpleMessage("Подключение..."),
    "connection": MessageLookupByLibrary.simpleMessage("Соединение"),
    "connectionDetails": MessageLookupByLibrary.simpleMessage(
      "Сведения о подключении",
    ),
    "connectionRuleAlreadyExists": MessageLookupByLibrary.simpleMessage(
      "Это правило уже существует. Профиль применён повторно",
    ),
    "connectionRuleApplied": MessageLookupByLibrary.simpleMessage(
      "Правило добавлено и применено",
    ),
    "connectionRuleAppliedAndSwitched": MessageLookupByLibrary.simpleMessage(
      "Правило добавлено, включён режим правил",
    ),
    "connectionStatus": MessageLookupByLibrary.simpleMessage(
      "Состояние подключения",
    ),
    "connections": MessageLookupByLibrary.simpleMessage("Соединения"),
    "connectionsDesc": MessageLookupByLibrary.simpleMessage(
      "Просмотр текущих данных о соединениях",
    ),
    "connectivity": MessageLookupByLibrary.simpleMessage("Связь："),
    "consumptionOnly": MessageLookupByLibrary.simpleMessage("Только расходы"),
    "content": MessageLookupByLibrary.simpleMessage("Содержание"),
    "contentNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Содержимое не может быть пустым",
    ),
    "contentScheme": MessageLookupByLibrary.simpleMessage("Контентная тема"),
    "controlGlobalAddedRules": MessageLookupByLibrary.simpleMessage(
      "Управление глобальными добавленными правилами",
    ),
    "copy": MessageLookupByLibrary.simpleMessage("Копировать"),
    "copyEnvVar": MessageLookupByLibrary.simpleMessage(
      "Копирование переменных окружения",
    ),
    "copyInviteCode": MessageLookupByLibrary.simpleMessage("Копировать код"),
    "copyLink": MessageLookupByLibrary.simpleMessage("Копировать ссылку"),
    "copySuccess": MessageLookupByLibrary.simpleMessage("Копирование успешно"),
    "core": MessageLookupByLibrary.simpleMessage("Ядро"),
    "coreIpv6": MessageLookupByLibrary.simpleMessage("IPv6 ядра"),
    "coreIpv6Description": MessageLookupByLibrary.simpleMessage(
      "Управление поддержкой IPv6 верхнего уровня Mihomo",
    ),
    "coreStatus": MessageLookupByLibrary.simpleMessage("Основной статус"),
    "countriesAndRegions": MessageLookupByLibrary.simpleMessage(
      "Страны и регионы",
    ),
    "countriesCount": m3,
    "country": MessageLookupByLibrary.simpleMessage("Страна"),
    "countryRegion": MessageLookupByLibrary.simpleMessage("Страна/регион"),
    "crashDetected": MessageLookupByLibrary.simpleMessage("Обнаружен сбой"),
    "crashDetectedTip": MessageLookupByLibrary.simpleMessage(
      "Во время предыдущего запуска произошёл сбой приложения. Чтобы предотвратить повторный сбой, текущий профиль был сброшен, а автоматическая настройка конфигурации пропущена.",
    ),
    "crashTest": MessageLookupByLibrary.simpleMessage("Тест на сбои"),
    "crashlytics": MessageLookupByLibrary.simpleMessage("Анализ сбоев"),
    "crashlyticsTip": MessageLookupByLibrary.simpleMessage(
      "При включении автоматически загружает журналы сбоев без конфиденциальной информации, когда приложение выходит из строя",
    ),
    "create": MessageLookupByLibrary.simpleMessage("Создать"),
    "createAccountSubtitle": MessageLookupByLibrary.simpleMessage(
      "Присоединяйтесь и начните управлять сетью",
    ),
    "createAccountTitle": MessageLookupByLibrary.simpleMessage(
      "Создать аккаунт",
    ),
    "createProfile": MessageLookupByLibrary.simpleMessage("Create Profile"),
    "createdAt": MessageLookupByLibrary.simpleMessage("Дата создания"),
    "creatingOrder": MessageLookupByLibrary.simpleMessage("Создание заказа…"),
    "creationTime": MessageLookupByLibrary.simpleMessage("Время создания"),
    "currentActiveConnections": MessageLookupByLibrary.simpleMessage(
      "Активные подключения",
    ),
    "currentEndpoint": MessageLookupByLibrary.simpleMessage(
      "Используется сейчас",
    ),
    "currentMonthTraffic": MessageLookupByLibrary.simpleMessage(
      "За этот месяц",
    ),
    "currentNode": MessageLookupByLibrary.simpleMessage("Текущий узел"),
    "currentNodeDelay": MessageLookupByLibrary.simpleMessage(
      "Задержка текущего узла",
    ),
    "currentPlanLabel": MessageLookupByLibrary.simpleMessage("Текущий тариф"),
    "custom": MessageLookupByLibrary.simpleMessage("Пользовательский"),
    "customDnsServers": MessageLookupByLibrary.simpleMessage(
      "Пользовательские DNS-серверы",
    ),
    "cut": MessageLookupByLibrary.simpleMessage("Вырезать"),
    "dailyBrowsingRuleMode": MessageLookupByLibrary.simpleMessage(
      "Обычный просмотр: режим правил надёжнее.",
    ),
    "dark": MessageLookupByLibrary.simpleMessage("Темный"),
    "dashboard": MessageLookupByLibrary.simpleMessage("Панель управления"),
    "dataChangedSave": MessageLookupByLibrary.simpleMessage(
      "Обнаружены изменения данных, хотите сохранить?",
    ),
    "dataCollectionContent": MessageLookupByLibrary.simpleMessage(
      "Это приложение использует Firebase Crashlytics для сбора информации о сбоях nhằm улучшения стабильности приложения.\nСобираемые данные включают информацию об устройстве и подробности о сбоях, но не содержат персональных конфиденциальных данных.\nВы можете отключить эту функцию в настройках.",
    ),
    "dataCollectionTip": MessageLookupByLibrary.simpleMessage(
      "Уведомление о сборе данных",
    ),
    "dataSource": MessageLookupByLibrary.simpleMessage("Источник данных"),
    "dateLabel": MessageLookupByLibrary.simpleMessage("Дата"),
    "daysAgo": m4,
    "defaultNameserver": MessageLookupByLibrary.simpleMessage(
      "Сервер имен по умолчанию",
    ),
    "defaultNameserverDesc": MessageLookupByLibrary.simpleMessage(
      "Для разрешения DNS-сервера",
    ),
    "defaultText": MessageLookupByLibrary.simpleMessage("По умолчанию"),
    "delay": MessageLookupByLibrary.simpleMessage("Задержка"),
    "delayTest": MessageLookupByLibrary.simpleMessage("Тест задержки"),
    "delete": MessageLookupByLibrary.simpleMessage("Удалить"),
    "deleteMultipTip": m5,
    "deleteTip": m6,
    "desc": MessageLookupByLibrary.simpleMessage(
      "Многоплатформенный прокси-клиент на основе ClashMeta, простой и удобный в использовании, с открытым исходным кодом и без рекламы.",
    ),
    "destination": MessageLookupByLibrary.simpleMessage("Назначение"),
    "destinationGeoIP": MessageLookupByLibrary.simpleMessage(
      "Геолокация назначения",
    ),
    "destinationIPASN": MessageLookupByLibrary.simpleMessage("ASN назначения"),
    "details": m7,
    "detectionTip": MessageLookupByLibrary.simpleMessage(
      "Опирается на сторонний API, только для справки",
    ),
    "developerMode": MessageLookupByLibrary.simpleMessage("Режим разработчика"),
    "developerModeEnableTip": MessageLookupByLibrary.simpleMessage(
      "Режим разработчика активирован.",
    ),
    "direct": MessageLookupByLibrary.simpleMessage("Прямой"),
    "disableProxy": MessageLookupByLibrary.simpleMessage("Остановить"),
    "disableUDP": MessageLookupByLibrary.simpleMessage("Отключить UDP"),
    "disclaimer": MessageLookupByLibrary.simpleMessage(
      "Отказ от ответственности",
    ),
    "disclaimerDesc": MessageLookupByLibrary.simpleMessage(
      "Это программное обеспечение используется только в некоммерческих целях, таких как учебные обмены и научные исследования. Запрещено использовать это программное обеспечение в коммерческих целях. Любая коммерческая деятельность, если таковая имеется, не имеет отношения к этому программному обеспечению.",
    ),
    "disconnected": MessageLookupByLibrary.simpleMessage("Отключено"),
    "discoverNewVersion": MessageLookupByLibrary.simpleMessage(
      "Обнаружена новая версия",
    ),
    "dnsDesc": MessageLookupByLibrary.simpleMessage(
      "Обновление настроек, связанных с DNS",
    ),
    "dnsHijacking": MessageLookupByLibrary.simpleMessage("DNS-перехват"),
    "dnsIpv6": MessageLookupByLibrary.simpleMessage("DNS IPv6"),
    "dnsIpv6Description": MessageLookupByLibrary.simpleMessage(
      "Возвращать записи IPv6 в запросах DNS",
    ),
    "dnsMode": MessageLookupByLibrary.simpleMessage("Режим DNS"),
    "dnsOverrideInformation": MessageLookupByLibrary.simpleMessage(
      "Если включено, используется встроенная конфигурация DNS вместо настроек DNS профиля",
    ),
    "dnsSettings": MessageLookupByLibrary.simpleMessage("Настройки DNS"),
    "dnsSettingsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Управление разрешением DNS",
    ),
    "doNotRemindToday": MessageLookupByLibrary.simpleMessage(
      "Больше не напоминать сегодня",
    ),
    "doYouWantToPass": MessageLookupByLibrary.simpleMessage(
      "Вы хотите пропустить",
    ),
    "domain": MessageLookupByLibrary.simpleMessage("Домен"),
    "domainOrService": MessageLookupByLibrary.simpleMessage("Домен / служба"),
    "done": MessageLookupByLibrary.simpleMessage("Готово"),
    "dontShowAgain": MessageLookupByLibrary.simpleMessage(
      "Больше не показывать",
    ),
    "download": MessageLookupByLibrary.simpleMessage("Скачивание"),
    "downloadSpeed": MessageLookupByLibrary.simpleMessage("Скорость загрузки"),
    "downloadTraffic": MessageLookupByLibrary.simpleMessage("Скачивание"),
    "downloaded": MessageLookupByLibrary.simpleMessage("Загружено"),
    "edit": MessageLookupByLibrary.simpleMessage("Редактировать"),
    "editGlobalRules": MessageLookupByLibrary.simpleMessage(
      "Редактировать глобальные правила",
    ),
    "editProxy": MessageLookupByLibrary.simpleMessage("Изменить прокси"),
    "editProxyGroup": MessageLookupByLibrary.simpleMessage(
      "Редактировать группу прокси",
    ),
    "editRule": MessageLookupByLibrary.simpleMessage("Редактировать правило"),
    "editSsid": MessageLookupByLibrary.simpleMessage("Изменить SSID"),
    "email": MessageLookupByLibrary.simpleMessage("Электронная почта"),
    "emailVerificationCode": MessageLookupByLibrary.simpleMessage(
      "Код подтверждения email",
    ),
    "emptyTip": m8,
    "en": MessageLookupByLibrary.simpleMessage("Английский"),
    "enableOfflineAction": MessageLookupByLibrary.simpleMessage(
      "Включить офлайн-режим",
    ),
    "enableOfflineDescription": MessageLookupByLibrary.simpleMessage(
      "Онлайн-проверка входа и обновление аккаунта будут пропущены. Будут использованы сохранённые подписка, узлы и данные аккаунта.",
    ),
    "enableOfflineTitle": MessageLookupByLibrary.simpleMessage(
      "Включить офлайн-режим?",
    ),
    "enableProxy": MessageLookupByLibrary.simpleMessage("Включить"),
    "enterConfirmPassword": MessageLookupByLibrary.simpleMessage(
      "Введите пароль еще раз",
    ),
    "enterEmail": MessageLookupByLibrary.simpleMessage(
      "Введите электронную почту",
    ),
    "enterEmailAddress": MessageLookupByLibrary.simpleMessage(
      "Введите адрес email",
    ),
    "enterInvitationCode": MessageLookupByLibrary.simpleMessage(
      "Введите код приглашения, если есть",
    ),
    "enterNewPassword": MessageLookupByLibrary.simpleMessage(
      "Введите новый пароль",
    ),
    "enterOldPassword": MessageLookupByLibrary.simpleMessage(
      "Введите текущий пароль",
    ),
    "enterPassword": MessageLookupByLibrary.simpleMessage("Введите пароль"),
    "enterVerificationCode": MessageLookupByLibrary.simpleMessage(
      "Введите код подтверждения",
    ),
    "enterWithdrawalAccount": MessageLookupByLibrary.simpleMessage(
      "Введите счёт или адрес получателя",
    ),
    "enterWithdrawalAmount": MessageLookupByLibrary.simpleMessage(
      "Введите сумму вывода",
    ),
    "entries": MessageLookupByLibrary.simpleMessage(" записей"),
    "entriesCount": m9,
    "exclude": MessageLookupByLibrary.simpleMessage(
      "Скрыть из последних задач",
    ),
    "excludeDesc": MessageLookupByLibrary.simpleMessage(
      "Когда приложение находится в фоновом режиме, оно скрыто из последних задач",
    ),
    "excludeProxyFilter": MessageLookupByLibrary.simpleMessage(
      "Исключить фильтр прокси",
    ),
    "excludeSsids": MessageLookupByLibrary.simpleMessage("Exclude SSIDs"),
    "excludeSsidsDesc": MessageLookupByLibrary.simpleMessage(
      "When connected to an excluded SSID Wi-Fi, the app running state will be automatically switched.",
    ),
    "excludeType": MessageLookupByLibrary.simpleMessage("Тип исключения"),
    "existsTip": m10,
    "exit": MessageLookupByLibrary.simpleMessage("Выход"),
    "expand": MessageLookupByLibrary.simpleMessage("Стандартный"),
    "expectedStatus": MessageLookupByLibrary.simpleMessage("Ожидаемый статус"),
    "expiryEmailReminder": MessageLookupByLibrary.simpleMessage(
      "Напоминание об окончании по почте",
    ),
    "exportFile": MessageLookupByLibrary.simpleMessage("Экспорт файла"),
    "exportLogs": MessageLookupByLibrary.simpleMessage("Экспорт логов"),
    "exportSuccess": MessageLookupByLibrary.simpleMessage("Экспорт успешен"),
    "expressiveScheme": MessageLookupByLibrary.simpleMessage("Экспрессивные"),
    "externalController": MessageLookupByLibrary.simpleMessage(
      "Внешний контроллер",
    ),
    "externalControllerDesc": MessageLookupByLibrary.simpleMessage(
      "При включении ядро Clash можно контролировать на порту 9090",
    ),
    "externalFetch": MessageLookupByLibrary.simpleMessage("Внешнее получение"),
    "externalLink": MessageLookupByLibrary.simpleMessage("Внешняя ссылка"),
    "fakeipFilter": MessageLookupByLibrary.simpleMessage("Фильтр Fakeip"),
    "fakeipRange": MessageLookupByLibrary.simpleMessage("Диапазон Fakeip"),
    "fallback": MessageLookupByLibrary.simpleMessage("Резервный"),
    "fallbackDesc": MessageLookupByLibrary.simpleMessage(
      "Обычно используется оффшорный DNS",
    ),
    "fallbackFilter": MessageLookupByLibrary.simpleMessage(
      "Фильтр резервного DNS",
    ),
    "fastestDownload": MessageLookupByLibrary.simpleMessage("Лучшая скорость"),
    "featureComingSoon": MessageLookupByLibrary.simpleMessage(
      "Функция станет доступна после подключения сервера",
    ),
    "fidelityScheme": MessageLookupByLibrary.simpleMessage("Точная передача"),
    "file": MessageLookupByLibrary.simpleMessage("Файл"),
    "fileDesc": MessageLookupByLibrary.simpleMessage("Прямая загрузка профиля"),
    "fileIsUpdate": MessageLookupByLibrary.simpleMessage(
      "Файл был изменен. Хотите сохранить изменения?",
    ),
    "findProcessMode": MessageLookupByLibrary.simpleMessage(
      "Режим поиска процесса",
    ),
    "findProcessModeDesc": MessageLookupByLibrary.simpleMessage(
      "При включении возможны небольшие потери производительности",
    ),
    "fontFamily": MessageLookupByLibrary.simpleMessage("Семейство шрифтов"),
    "forceRestartCoreTip": MessageLookupByLibrary.simpleMessage(
      "Вы уверены, что хотите принудительно перезапустить ядро?",
    ),
    "forgotPassword": MessageLookupByLibrary.simpleMessage("Забыли пароль?"),
    "forgotPasswordSubtitle": MessageLookupByLibrary.simpleMessage(
      "Сбросьте пароль и восстановите доступ к аккаунту",
    ),
    "forgotPasswordTitle": MessageLookupByLibrary.simpleMessage(
      "Восстановление пароля",
    ),
    "freeLabel": MessageLookupByLibrary.simpleMessage("Бесплатно"),
    "freeOrder": MessageLookupByLibrary.simpleMessage("Бесплатная активация"),
    "fruitSaladScheme": MessageLookupByLibrary.simpleMessage("Фруктовый микс"),
    "general": MessageLookupByLibrary.simpleMessage("Общие"),
    "generateInviteCode": MessageLookupByLibrary.simpleMessage("Создать код"),
    "generateMihomoRule": MessageLookupByLibrary.simpleMessage(
      "Создать правило Mihomo из этого подключения",
    ),
    "generatePaymentQr": MessageLookupByLibrary.simpleMessage(
      "Создать платёжный QR-код",
    ),
    "geoAutoUpdate": MessageLookupByLibrary.simpleMessage("Автообновление"),
    "geoAutoUpdateInterval": MessageLookupByLibrary.simpleMessage(
      "Интервал автообновления",
    ),
    "geoAutoUpdateIntervalTip": MessageLookupByLibrary.simpleMessage(
      "Интервал автообновления должен быть больше 0",
    ),
    "geoOptions": MessageLookupByLibrary.simpleMessage("Настройки Geo"),
    "geoResources": MessageLookupByLibrary.simpleMessage("Ресурсы Geo"),
    "geoSkipped": m11,
    "geoUpdated": m12,
    "geoUpdating": m13,
    "geodataLoader": MessageLookupByLibrary.simpleMessage(
      "Режим низкого потребления памяти для геоданных",
    ),
    "geodataLoaderDesc": MessageLookupByLibrary.simpleMessage(
      "Включение будет использовать загрузчик геоданных с низким потреблением памяти",
    ),
    "geodataSettings": MessageLookupByLibrary.simpleMessage("Геоданные"),
    "geodataSettingsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Обновление баз GeoIP и GeoSite",
    ),
    "geoipCode": MessageLookupByLibrary.simpleMessage("Код Geoip"),
    "global": MessageLookupByLibrary.simpleMessage("Глобальный"),
    "globalAccelerationNetwork": MessageLookupByLibrary.simpleMessage(
      "Глобальная сеть ускорения",
    ),
    "globalModeWarningDescription": MessageLookupByLibrary.simpleMessage(
      "Глобальный режим обрабатывает весь сетевой трафик. При первом переключении используется DIRECT, затем можно выбрать прокси-узел.",
    ),
    "globalNodeDistribution": MessageLookupByLibrary.simpleMessage(
      "Распределение узлов",
    ),
    "globalRuleModeSwitchHint": MessageLookupByLibrary.simpleMessage(
      "Сейчас включён глобальный режим. После добавления будет включён режим правил: это подключение использует политику выше, а остальной трафик — выбранную прокси-группу.",
    ),
    "go": MessageLookupByLibrary.simpleMessage("Перейти"),
    "goDownload": MessageLookupByLibrary.simpleMessage("Перейти к загрузке"),
    "goToConfigureScript": MessageLookupByLibrary.simpleMessage(
      "Перейти к настройке скрипта",
    ),
    "halfYearBilling": MessageLookupByLibrary.simpleMessage("Полгода"),
    "handlingFee": MessageLookupByLibrary.simpleMessage("Комиссия"),
    "hasCacheChange": MessageLookupByLibrary.simpleMessage(
      "Хотите сохранить изменения в кэше?",
    ),
    "helperCorruptTip": MessageLookupByLibrary.simpleMessage(
      "Служба Helper недоступна, поэтому TUN-режим включить нельзя. Переустановите FlClash.",
    ),
    "hideFromList": MessageLookupByLibrary.simpleMessage("Скрыть из списка"),
    "hidePassword": MessageLookupByLibrary.simpleMessage("Скрыть пароль"),
    "highestLatency": MessageLookupByLibrary.simpleMessage("Макс. задержка"),
    "host": MessageLookupByLibrary.simpleMessage("Хост"),
    "hostsDesc": MessageLookupByLibrary.simpleMessage("Добавить Hosts"),
    "hotkeyConflict": MessageLookupByLibrary.simpleMessage(
      "Конфликт горячих клавиш",
    ),
    "hotkeyManagement": MessageLookupByLibrary.simpleMessage(
      "Управление горячими клавишами",
    ),
    "hotkeyManagementDesc": MessageLookupByLibrary.simpleMessage(
      "Использование клавиатуры для управления приложением",
    ),
    "hours": MessageLookupByLibrary.simpleMessage("часов"),
    "hoursAgo": m14,
    "hoursCount": m15,
    "iHavePaid": MessageLookupByLibrary.simpleMessage(
      "Я оплатил, обновить статус",
    ),
    "icon": MessageLookupByLibrary.simpleMessage("Иконка"),
    "iconRecords": MessageLookupByLibrary.simpleMessage("История иконок"),
    "iconStyle": MessageLookupByLibrary.simpleMessage("Стиль иконки"),
    "iconUrl": MessageLookupByLibrary.simpleMessage("URL иконки"),
    "ignoreBatteryOptimization": MessageLookupByLibrary.simpleMessage(
      "Ignore Battery Optimization",
    ),
    "import": MessageLookupByLibrary.simpleMessage("Импорт"),
    "importFile": MessageLookupByLibrary.simpleMessage("Импорт из файла"),
    "importFromURL": MessageLookupByLibrary.simpleMessage("Импорт из URL"),
    "importUrl": MessageLookupByLibrary.simpleMessage("Импорт по URL"),
    "inAppPayment": MessageLookupByLibrary.simpleMessage("Оплата в приложении"),
    "includeAllProxies": MessageLookupByLibrary.simpleMessage(
      "Включить все прокси",
    ),
    "includeAllProxiesTip": MessageLookupByLibrary.simpleMessage(
      "Импорт всех прокси, не содержащих группы прокси, дополнительные группы прокси можно добавить ниже",
    ),
    "includeAllProxyProviders": MessageLookupByLibrary.simpleMessage(
      "Включить всех провайдеров прокси",
    ),
    "includeAllProxyProvidersTip": MessageLookupByLibrary.simpleMessage(
      "При включении это переопределит импортированных провайдеров прокси",
    ),
    "infiniteTime": MessageLookupByLibrary.simpleMessage(
      "Долгосрочное действие",
    ),
    "init": MessageLookupByLibrary.simpleMessage("Инициализация"),
    "inputCorrectHotkey": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, введите правильную горячую клавишу",
    ),
    "inputProxyGroupName": MessageLookupByLibrary.simpleMessage(
      "Введите имя группы прокси",
    ),
    "inputRuleContent": MessageLookupByLibrary.simpleMessage(
      "Введите содержимое правила",
    ),
    "intelligentSelected": MessageLookupByLibrary.simpleMessage(
      "Интеллектуальный выбор",
    ),
    "internet": MessageLookupByLibrary.simpleMessage("Интернет"),
    "interval": MessageLookupByLibrary.simpleMessage("Интервал"),
    "intranetIP": MessageLookupByLibrary.simpleMessage("Внутренний IP"),
    "invalidBackupFile": MessageLookupByLibrary.simpleMessage(
      "Неверный файл резервной копии",
    ),
    "invalidEmail": MessageLookupByLibrary.simpleMessage(
      "Введите корректный адрес электронной почты",
    ),
    "invalidEmailAccount": MessageLookupByLibrary.simpleMessage(
      "Введите корректный адрес email",
    ),
    "invalidPolicy": m16,
    "invalidPort": MessageLookupByLibrary.simpleMessage(
      "Введите корректный порт",
    ),
    "invalidProxy": m17,
    "invalidProxyProvider": m18,
    "invalidSubRule": m19,
    "invitationCode": MessageLookupByLibrary.simpleMessage("Код приглашения"),
    "invitationCodeOptional": MessageLookupByLibrary.simpleMessage(
      "Код приглашения (необязательно)",
    ),
    "invitationCodeRequired": MessageLookupByLibrary.simpleMessage(
      "Введите код приглашения",
    ),
    "inviteCode": MessageLookupByLibrary.simpleMessage("Код приглашения"),
    "inviteCodeCopied": MessageLookupByLibrary.simpleMessage(
      "Код приглашения скопирован",
    ),
    "inviteCodeDescription": MessageLookupByLibrary.simpleMessage(
      "Поделитесь кодом: после регистрации друга и покупки тарифа вы получите комиссию.",
    ),
    "inviteCodeGenerated": MessageLookupByLibrary.simpleMessage(
      "Код приглашения создан",
    ),
    "inviteCodeManagement": MessageLookupByLibrary.simpleMessage(
      "Управление кодами",
    ),
    "inviteHeroSubtitle": MessageLookupByLibrary.simpleMessage(
      "Больше приглашений — больше наград, без ограничений!",
    ),
    "inviteHeroTitle": MessageLookupByLibrary.simpleMessage(
      "Приглашайте друзей — получайте награды",
    ),
    "inviteLoadFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось загрузить данные приглашений",
    ),
    "invitePromotion": MessageLookupByLibrary.simpleMessage("Приглашения"),
    "ipAddress": MessageLookupByLibrary.simpleMessage("IP-адрес"),
    "ipLookup": MessageLookupByLibrary.simpleMessage("Проверка IP"),
    "ipLookupDescription": MessageLookupByLibrary.simpleMessage(
      "Регион, оператор и другие сведения о публичном IP",
    ),
    "ipLookupFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось получить данные IP. Проверьте подключение и повторите попытку",
    ),
    "ipcidr": MessageLookupByLibrary.simpleMessage("IPCIDR"),
    "ipv6Desc": MessageLookupByLibrary.simpleMessage(
      "При включении будет возможно получать IPv6 трафик",
    ),
    "ipv6InboundDesc": MessageLookupByLibrary.simpleMessage(
      "Разрешить входящий IPv6",
    ),
    "ipv6Settings": MessageLookupByLibrary.simpleMessage("Настройки IPv6"),
    "ipv6SettingsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Управление подключением IPv6 в Mihomo",
    ),
    "ja": MessageLookupByLibrary.simpleMessage("Японский"),
    "justNow": MessageLookupByLibrary.simpleMessage("Только что"),
    "keepAliveIntervalDesc": MessageLookupByLibrary.simpleMessage(
      "Интервал поддержания TCP-соединения",
    ),
    "keptCount": MessageLookupByLibrary.simpleMessage("Сохранено"),
    "key": MessageLookupByLibrary.simpleMessage("Ключ"),
    "language": MessageLookupByLibrary.simpleMessage("Язык"),
    "layout": MessageLookupByLibrary.simpleMessage("Макет"),
    "light": MessageLookupByLibrary.simpleMessage("Светлый"),
    "list": MessageLookupByLibrary.simpleMessage("Список"),
    "listen": MessageLookupByLibrary.simpleMessage("Слушать"),
    "liveConnectionList": MessageLookupByLibrary.simpleMessage(
      "Активные подключения",
    ),
    "liveConnectionsCount": m20,
    "liveConnectionsFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось загрузить подключения. Повторите попытку позже",
    ),
    "loadTest": MessageLookupByLibrary.simpleMessage("Тест загрузки"),
    "loading": MessageLookupByLibrary.simpleMessage("Загрузка..."),
    "loadingPaymentMethods": MessageLookupByLibrary.simpleMessage(
      "Загрузка способов оплаты…",
    ),
    "local": MessageLookupByLibrary.simpleMessage("Локальный"),
    "localBackupDesc": MessageLookupByLibrary.simpleMessage(
      "Резервное копирование локальных данных на локальный диск",
    ),
    "locationPermission": MessageLookupByLibrary.simpleMessage(
      "Location Permission",
    ),
    "locationPermissionDeniedMessage": MessageLookupByLibrary.simpleMessage(
      "Разрешение на геолокацию отклонено, поэтому невозможно получить имя текущей Wi-Fi сети. Включите разрешение на геолокацию вручную в системных настройках.",
    ),
    "locationPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "According to system requirements, obtaining the Wi-Fi name requires you to grant location permission.",
    ),
    "locationPermissionGuide": m21,
    "locationPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "Location Permission Required",
    ),
    "log": MessageLookupByLibrary.simpleMessage("Журнал"),
    "logLevel": MessageLookupByLibrary.simpleMessage("Уровень логов"),
    "logcat": MessageLookupByLibrary.simpleMessage("Logcat"),
    "logcatDesc": MessageLookupByLibrary.simpleMessage(
      "Отключение скроет запись логов",
    ),
    "loggedIn": MessageLookupByLibrary.simpleMessage("Вход выполнен"),
    "loggingIn": MessageLookupByLibrary.simpleMessage("Выполняется вход…"),
    "login": MessageLookupByLibrary.simpleMessage("Войти"),
    "loginEndpoint": MessageLookupByLibrary.simpleMessage("Сервер входа"),
    "loginEndpointLabel": m22,
    "loginFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось войти. Повторите попытку позже",
    ),
    "loginSessionExpired": MessageLookupByLibrary.simpleMessage(
      "Сеанс истёк. Войдите снова",
    ),
    "loginWelcome": MessageLookupByLibrary.simpleMessage(
      "С возвращением! Войдите в свою учётную запись",
    ),
    "logoutAccount": MessageLookupByLibrary.simpleMessage("Выйти"),
    "logoutConfirmMessage": MessageLookupByLibrary.simpleMessage(
      "Сохранённые на устройстве данные входа будут удалены.",
    ),
    "logoutConfirmTitle": MessageLookupByLibrary.simpleMessage(
      "Выйти из этого аккаунта?",
    ),
    "logs": MessageLookupByLibrary.simpleMessage("Логи"),
    "logsDesc": MessageLookupByLibrary.simpleMessage("Записи захвата логов"),
    "logsTest": MessageLookupByLibrary.simpleMessage("Тест журналов"),
    "loopback": MessageLookupByLibrary.simpleMessage(
      "Инструмент разблокировки Loopback",
    ),
    "loopbackDesc": MessageLookupByLibrary.simpleMessage(
      "Используется для разблокировки Loopback UWP",
    ),
    "loose": MessageLookupByLibrary.simpleMessage("Свободный"),
    "lowestLatency": MessageLookupByLibrary.simpleMessage("Мин. задержка"),
    "manageChainProxy": MessageLookupByLibrary.simpleMessage(
      "Управлять цепочкой",
    ),
    "manualSelection": MessageLookupByLibrary.simpleMessage("Ручной выбор"),
    "matchContent": MessageLookupByLibrary.simpleMessage("Условие"),
    "matchSourceIp": MessageLookupByLibrary.simpleMessage(
      "Сопоставить исходный IP",
    ),
    "maxFailedTimes": MessageLookupByLibrary.simpleMessage(
      "Макс. количество неудач",
    ),
    "memberValidUntil": MessageLookupByLibrary.simpleMessage(
      "Подписка действует до",
    ),
    "memoryInfo": MessageLookupByLibrary.simpleMessage("Информация о памяти"),
    "messageTest": MessageLookupByLibrary.simpleMessage(
      "Тестирование сообщения",
    ),
    "messageTestTip": MessageLookupByLibrary.simpleMessage("Это сообщение."),
    "min": MessageLookupByLibrary.simpleMessage("Мин"),
    "mine": MessageLookupByLibrary.simpleMessage("Моё"),
    "minimizeOnExit": MessageLookupByLibrary.simpleMessage(
      "Свернуть при выходе",
    ),
    "minimizeOnExitDesc": MessageLookupByLibrary.simpleMessage(
      "Изменить стандартное событие выхода из системы",
    ),
    "minutesAgo": m23,
    "mixedPort": MessageLookupByLibrary.simpleMessage("Смешанный порт"),
    "mixedPortSharedDescription": MessageLookupByLibrary.simpleMessage(
      "Общий порт HTTP и SOCKS5",
    ),
    "mode": MessageLookupByLibrary.simpleMessage("Режим"),
    "monochromeScheme": MessageLookupByLibrary.simpleMessage("Монохром"),
    "monthlyBilling": MessageLookupByLibrary.simpleMessage("Месяц"),
    "monthsAgo": m24,
    "more": MessageLookupByLibrary.simpleMessage("Еще"),
    "myInvitation": MessageLookupByLibrary.simpleMessage("Мои приглашения"),
    "myOrders": MessageLookupByLibrary.simpleMessage("Мои заказы"),
    "myWallet": MessageLookupByLibrary.simpleMessage("Мой кошелёк"),
    "name": MessageLookupByLibrary.simpleMessage("Имя"),
    "nameserver": MessageLookupByLibrary.simpleMessage("Сервер имен"),
    "nameserverDesc": MessageLookupByLibrary.simpleMessage(
      "Для разрешения домена",
    ),
    "nameserverPolicy": MessageLookupByLibrary.simpleMessage(
      "Политика сервера имен",
    ),
    "nameserverPolicyDesc": MessageLookupByLibrary.simpleMessage(
      "Указать соответствующую политику сервера имен",
    ),
    "network": MessageLookupByLibrary.simpleMessage("Сеть"),
    "networkDesc": MessageLookupByLibrary.simpleMessage(
      "Изменение настроек, связанных с сетью",
    ),
    "networkDetection": MessageLookupByLibrary.simpleMessage(
      "Обнаружение сети",
    ),
    "networkDiagnosticConfigDnsFailed": MessageLookupByLibrary.simpleMessage(
      "Локальный прокси имеет доступ в интернет, но домены конфигурации не разрешаются",
    ),
    "networkDiagnosticConfigDomains": MessageLookupByLibrary.simpleMessage(
      "Домены конфигурации",
    ),
    "networkDiagnosticConfigDomainsResult": m25,
    "networkDiagnosticCoreNotRunning": MessageLookupByLibrary.simpleMessage(
      "Ядро прокси не запущено",
    ),
    "networkDiagnosticInternetFailed": MessageLookupByLibrary.simpleMessage(
      "Нет доступа в интернет через локальный прокси",
    ),
    "networkDiagnosticInternetSuccess": MessageLookupByLibrary.simpleMessage(
      "Доступ в интернет через локальный прокси успешен",
    ),
    "networkDiagnosticLocalProxyPort": MessageLookupByLibrary.simpleMessage(
      "Локальный порт прокси",
    ),
    "networkDiagnosticNoProfile": MessageLookupByLibrary.simpleMessage(
      "Нет доступной конфигурации подписки. Войдите снова или обновите подписку",
    ),
    "networkDiagnosticNodeInternet": MessageLookupByLibrary.simpleMessage(
      "Доступ узла в интернет",
    ),
    "networkDiagnosticNodeUnavailable": MessageLookupByLibrary.simpleMessage(
      "Локальный порт работает, но текущий узел не имеет доступа в интернет",
    ),
    "networkDiagnosticPortListening": m26,
    "networkDiagnosticPortNotListening": MessageLookupByLibrary.simpleMessage(
      "Ядро запущено, но локальный порт прокси не прослушивается",
    ),
    "networkDiagnosticPortUnavailable": m27,
    "networkDiagnosticProxyFailure": m28,
    "networkDiagnosticProxyVerified": m29,
    "networkDiagnosticSuccess": MessageLookupByLibrary.simpleMessage(
      "Доступ в интернет через локальный прокси работает; перехват трафика приложений и TUN не проверен",
    ),
    "networkDiagnosticSystemProxyInvalid": MessageLookupByLibrary.simpleMessage(
      "Системный прокси Windows настроен неправильно",
    ),
    "networkDiagnosticTrafficEntryMissing": MessageLookupByLibrary.simpleMessage(
      "Узел работает, но системный прокси и TUN выключены, поэтому трафик приложений не поступает в ядро",
    ),
    "networkDiagnosticWindowsSystemProxy": MessageLookupByLibrary.simpleMessage(
      "Системный прокси Windows",
    ),
    "networkException": MessageLookupByLibrary.simpleMessage(
      "Ошибка сети, проверьте соединение и попробуйте еще раз",
    ),
    "networkSpeed": MessageLookupByLibrary.simpleMessage("Скорость сети"),
    "networkType": MessageLookupByLibrary.simpleMessage("Тип сети"),
    "neutralScheme": MessageLookupByLibrary.simpleMessage("Нейтральные"),
    "newPassword": MessageLookupByLibrary.simpleMessage("Новый пароль"),
    "nextAnnouncement": MessageLookupByLibrary.simpleMessage("Далее"),
    "nextPage": MessageLookupByLibrary.simpleMessage("Далее"),
    "nextPlanResetAt": m30,
    "noActiveConnections": MessageLookupByLibrary.simpleMessage(
      "Нет активных подключений. Запустите VPN и откройте сайт",
    ),
    "noActivePlan": MessageLookupByLibrary.simpleMessage(
      "Нет активного тарифа",
    ),
    "noAnnouncements": MessageLookupByLibrary.simpleMessage("Объявлений нет"),
    "noChainProxy": MessageLookupByLibrary.simpleMessage("Нет цепочных прокси"),
    "noChainProxyDescription": MessageLookupByLibrary.simpleMessage(
      "Добавьте прокси SOCKS5 или HTTP.",
    ),
    "noCommissionRecords": MessageLookupByLibrary.simpleMessage(
      "Истории комиссий пока нет",
    ),
    "noData": MessageLookupByLibrary.simpleMessage("Нет данных"),
    "noHandlingFee": MessageLookupByLibrary.simpleMessage("Без комиссии"),
    "noHotKey": MessageLookupByLibrary.simpleMessage("Нет горячей клавиши"),
    "noInfo": MessageLookupByLibrary.simpleMessage("Нет информации"),
    "noInviteCodes": MessageLookupByLibrary.simpleMessage(
      "Кодов пока нет. Создайте код кнопкой выше.",
    ),
    "noLimit": MessageLookupByLibrary.simpleMessage("Без ограничений"),
    "noLongerRemind": MessageLookupByLibrary.simpleMessage(
      "Больше не напоминать",
    ),
    "noMatchingConnections": MessageLookupByLibrary.simpleMessage(
      "Подходящие подключения не найдены",
    ),
    "noNetwork": MessageLookupByLibrary.simpleMessage("Нет сети"),
    "noNetworkApp": MessageLookupByLibrary.simpleMessage("Приложение без сети"),
    "noOrders": MessageLookupByLibrary.simpleMessage("Заказов пока нет"),
    "noPaymentMethods": MessageLookupByLibrary.simpleMessage(
      "Сейчас нет доступных способов оплаты",
    ),
    "noPaymentRequired": MessageLookupByLibrary.simpleMessage(
      "Этот заказ не требует оплаты",
    ),
    "noProfileForRule": MessageLookupByLibrary.simpleMessage(
      "Нет текущего профиля, в который можно сохранить правило",
    ),
    "noProxyGroupForFallback": MessageLookupByLibrary.simpleMessage(
      "В профиле нет прокси-группы для глобального резервного правила",
    ),
    "noRecords": MessageLookupByLibrary.simpleMessage("Нет записей"),
    "noResolve": MessageLookupByLibrary.simpleMessage("Не разрешать IP"),
    "noResolveHostname": MessageLookupByLibrary.simpleMessage(
      "Не разрешать имя хоста",
    ),
    "noTrafficRecords": MessageLookupByLibrary.simpleMessage(
      "За этот месяц нет записей",
    ),
    "nodeAvailable": MessageLookupByLibrary.simpleMessage("Доступен"),
    "nodeBackendOffline": MessageLookupByLibrary.simpleMessage(
      "Сервер отключён",
    ),
    "nodeBackendOnline": MessageLookupByLibrary.simpleMessage(
      "Сервер доступен",
    ),
    "nodeLabel": MessageLookupByLibrary.simpleMessage("Узел"),
    "nodeLocallyUnreachable": MessageLookupByLibrary.simpleMessage(
      "Недоступен в этой сети",
    ),
    "nodeNetworkFluctuating": MessageLookupByLibrary.simpleMessage(
      "Нестабильная сеть",
    ),
    "nodeStatus": MessageLookupByLibrary.simpleMessage("Узлы"),
    "nodeStatusSubtitle": MessageLookupByLibrary.simpleMessage(
      "Выберите лучший узел для быстрого и стабильного соединения",
    ),
    "nodeStatusUnknown": MessageLookupByLibrary.simpleMessage(
      "Статус неизвестен",
    ),
    "nodesCount": m31,
    "none": MessageLookupByLibrary.simpleMessage("Нет"),
    "notEnabled": MessageLookupByLibrary.simpleMessage("Не включено"),
    "notSelectedTip": MessageLookupByLibrary.simpleMessage(
      "Текущая группа прокси не может быть выбрана.",
    ),
    "notTested": MessageLookupByLibrary.simpleMessage("Не проверено"),
    "notificationSettings": MessageLookupByLibrary.simpleMessage("Уведомления"),
    "notificationSettingsSaved": MessageLookupByLibrary.simpleMessage(
      "Настройки уведомлений сохранены",
    ),
    "nullProfileDesc": MessageLookupByLibrary.simpleMessage(
      "Нет профиля, пожалуйста, добавьте профиль",
    ),
    "nullTip": m32,
    "numberTip": m33,
    "offline": MessageLookupByLibrary.simpleMessage("Не в сети"),
    "offlineCacheContinues": MessageLookupByLibrary.simpleMessage(
      "Существующий кэш продолжит использоваться на главной странице и в списке узлов.",
    ),
    "offlineCacheUnavailable": MessageLookupByLibrary.simpleMessage(
      "Нет действительного кэша подписки, проверенного за последние три дня",
    ),
    "offlineEntry": MessageLookupByLibrary.simpleMessage(
      "Продолжить с локальным кэшем",
    ),
    "offlineEntryHint": MessageLookupByLibrary.simpleMessage(
      "Использовать последнюю проверенную подписку и узлы",
    ),
    "offlineEntryUnavailable": MessageLookupByLibrary.simpleMessage(
      "Офлайн-кэш недоступен",
    ),
    "offlineMode": MessageLookupByLibrary.simpleMessage("Офлайн-режим"),
    "offlineModeBanner": MessageLookupByLibrary.simpleMessage(
      "Офлайн-режим включён. Показаны локальные сохранённые данные.",
    ),
    "offlineModeDescriptionTitle": MessageLookupByLibrary.simpleMessage(
      "Об офлайн-режиме",
    ),
    "offlineModeEnabled": MessageLookupByLibrary.simpleMessage("Включён"),
    "offlineNetworkTools": MessageLookupByLibrary.simpleMessage(
      "Сетевые инструменты, не требующие входа, останутся доступны.",
    ),
    "offlineNoUpdates": MessageLookupByLibrary.simpleMessage(
      "Тарифы, приглашения, подписка и данные пользователя не будут обновляться.",
    ),
    "oldPassword": MessageLookupByLibrary.simpleMessage("Текущий пароль"),
    "onDemand": MessageLookupByLibrary.simpleMessage("On Demand"),
    "onDemandDesc": MessageLookupByLibrary.simpleMessage(
      "Configure the program running state for specific scenarios",
    ),
    "oneTimeBilling": MessageLookupByLibrary.simpleMessage("Разово"),
    "oneTimePlans": MessageLookupByLibrary.simpleMessage("Разовые"),
    "online": MessageLookupByLibrary.simpleMessage("В сети"),
    "onlineFeaturesUnavailableOffline": MessageLookupByLibrary.simpleMessage(
      "Вернитесь в онлайн-режим, чтобы использовать эту функцию",
    ),
    "onlineSupport": MessageLookupByLibrary.simpleMessage("Поддержка"),
    "onlyIcon": MessageLookupByLibrary.simpleMessage("Только иконка"),
    "onlyStatisticsProxy": MessageLookupByLibrary.simpleMessage(
      "Только статистика прокси",
    ),
    "onlyStatisticsProxyDesc": MessageLookupByLibrary.simpleMessage(
      "При включении будет учитываться только трафик прокси",
    ),
    "optimizationComplete": MessageLookupByLibrary.simpleMessage(
      "Оптимизация завершена",
    ),
    "optimizationDownload": MessageLookupByLibrary.simpleMessage(
      "Проверка скорости загрузки",
    ),
    "optimizationFailed": MessageLookupByLibrary.simpleMessage(
      "Подходящий IP Cloudflare не найден. Проверьте подключение и повторите попытку",
    ),
    "optimizationLatency": MessageLookupByLibrary.simpleMessage(
      "Проверка задержки соединения",
    ),
    "optimizationPreparing": MessageLookupByLibrary.simpleMessage(
      "Загрузка кандидатов Cloudflare",
    ),
    "optional": MessageLookupByLibrary.simpleMessage("Необязательно"),
    "options": MessageLookupByLibrary.simpleMessage("Опции"),
    "orderAmount": MessageLookupByLibrary.simpleMessage("Сумма"),
    "orderCancelled": MessageLookupByLibrary.simpleMessage("Заказ отменён"),
    "orderCancelledSuccess": MessageLookupByLibrary.simpleMessage(
      "Заказ отменён",
    ),
    "orderCenterSubtitle": MessageLookupByLibrary.simpleMessage(
      "Просматривайте заказы, платежи и статус активации",
    ),
    "orderDetailsTitle": MessageLookupByLibrary.simpleMessage("Детали заказа"),
    "orderListFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось загрузить заказы",
    ),
    "orderNumber": MessageLookupByLibrary.simpleMessage("Номер заказа"),
    "orderPageIndicator": m34,
    "orderPeriod": MessageLookupByLibrary.simpleMessage("Период"),
    "orderPlan": MessageLookupByLibrary.simpleMessage("Тариф"),
    "orderStatusCancelled": MessageLookupByLibrary.simpleMessage("Отменён"),
    "orderStatusCompleted": MessageLookupByLibrary.simpleMessage("Завершён"),
    "orderStatusPending": MessageLookupByLibrary.simpleMessage(
      "Ожидает оплаты",
    ),
    "orderStatusProcessing": MessageLookupByLibrary.simpleMessage("Активация"),
    "orderStatusUnknown": MessageLookupByLibrary.simpleMessage("Неизвестно"),
    "organization": MessageLookupByLibrary.simpleMessage("Организация"),
    "other": MessageLookupByLibrary.simpleMessage("Другое"),
    "otherContributors": MessageLookupByLibrary.simpleMessage(
      "Другие участники",
    ),
    "otherTrafficPolicy": MessageLookupByLibrary.simpleMessage(
      "Политика прочего трафика",
    ),
    "outboundMode": MessageLookupByLibrary.simpleMessage(
      "Режим исходящего трафика",
    ),
    "override": MessageLookupByLibrary.simpleMessage("Переопределить"),
    "overrideDns": MessageLookupByLibrary.simpleMessage("Переопределить DNS"),
    "overrideDnsDesc": MessageLookupByLibrary.simpleMessage(
      "Включение переопределит настройки DNS в профиле",
    ),
    "overrideMode": MessageLookupByLibrary.simpleMessage(
      "Режим переопределения",
    ),
    "overrideScript": MessageLookupByLibrary.simpleMessage(
      "Скрипт переопределения",
    ),
    "overwriteTypeCustom": MessageLookupByLibrary.simpleMessage(
      "Пользовательский",
    ),
    "overwriteTypeCustomDesc": MessageLookupByLibrary.simpleMessage(
      "Пользовательский режим, полная настройка групп прокси и правил",
    ),
    "paidAt": MessageLookupByLibrary.simpleMessage("Время оплаты"),
    "palette": MessageLookupByLibrary.simpleMessage("Палитра"),
    "password": MessageLookupByLibrary.simpleMessage("Пароль"),
    "passwordChanged": MessageLookupByLibrary.simpleMessage(
      "Пароль успешно изменён",
    ),
    "passwordResetFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось сбросить пароль. Повторите позже",
    ),
    "passwordResetSuccess": MessageLookupByLibrary.simpleMessage(
      "Пароль сброшен. Войдите с новым паролем",
    ),
    "passwordTooShort": MessageLookupByLibrary.simpleMessage(
      "Пароль должен содержать не менее 8 символов",
    ),
    "passwordsDoNotMatch": MessageLookupByLibrary.simpleMessage(
      "Пароли не совпадают",
    ),
    "paste": MessageLookupByLibrary.simpleMessage("Вставить"),
    "paymentFailed": MessageLookupByLibrary.simpleMessage(
      "Оплата не завершена",
    ),
    "paymentMethod": MessageLookupByLibrary.simpleMessage("Способ оплаты"),
    "paymentSecurityHint": MessageLookupByLibrary.simpleMessage(
      "Заказ и QR-код создаются платёжным API XBoard в реальном времени",
    ),
    "paymentStaysInApp": MessageLookupByLibrary.simpleMessage(
      "Платёжный QR-код безопасно отображается в приложении",
    ),
    "paymentSuccessful": MessageLookupByLibrary.simpleMessage(
      "Оплата прошла успешно",
    ),
    "paymentSuccessfulHint": MessageLookupByLibrary.simpleMessage(
      "Тариф активируется. Обновите подписку через некоторое время",
    ),
    "payoutTime": MessageLookupByLibrary.simpleMessage("Дата выплаты"),
    "pendingCommission": MessageLookupByLibrary.simpleMessage(
      "Ожидает подтверждения",
    ),
    "pendingTest": MessageLookupByLibrary.simpleMessage("Ожидает"),
    "peopleCount": m35,
    "personalCenter": MessageLookupByLibrary.simpleMessage("Аккаунт"),
    "planCatalogEmpty": MessageLookupByLibrary.simpleMessage(
      "Сейчас нет доступных тарифов",
    ),
    "planCatalogFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось загрузить тарифы",
    ),
    "planDevicesLabel": MessageLookupByLibrary.simpleMessage("Устройства"),
    "planSpeedLabel": MessageLookupByLibrary.simpleMessage("Скорость"),
    "planStoreSubtitle": MessageLookupByLibrary.simpleMessage(
      "Безопасное, быстрое и стабильное подключение по всему миру",
    ),
    "planTrafficLabel": MessageLookupByLibrary.simpleMessage("Трафик"),
    "platformCount": MessageLookupByLibrary.simpleMessage("Сервисы"),
    "pleaseBindWebDAV": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, привяжите WebDAV",
    ),
    "pleaseEnterScriptName": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, введите название скрипта",
    ),
    "pleaseInputAdminPassword": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, введите пароль администратора",
    ),
    "pleaseUploadValidQrcode": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, загрузите действительный QR-код",
    ),
    "pleaseWait": MessageLookupByLibrary.simpleMessage(
      "Подождите и не отправляйте запрос повторно",
    ),
    "popularApps": MessageLookupByLibrary.simpleMessage(
      "Популярные приложения",
    ),
    "popularAppsDescription": MessageLookupByLibrary.simpleMessage(
      "Полезные клиенты и дополнительные приложения",
    ),
    "port": MessageLookupByLibrary.simpleMessage("Порт"),
    "portConflictTip": MessageLookupByLibrary.simpleMessage(
      "Введите другой порт",
    ),
    "portTip": m36,
    "practicalTools": MessageLookupByLibrary.simpleMessage("Утилиты"),
    "practicalToolsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Полезные сетевые инструменты для более удобной работы в интернете",
    ),
    "preferH3Desc": MessageLookupByLibrary.simpleMessage(
      "Приоритетное использование HTTP/3 для DOH",
    ),
    "preferredNodes": MessageLookupByLibrary.simpleMessage(
      "Рекомендуемые узлы",
    ),
    "prerequisites": MessageLookupByLibrary.simpleMessage("Prerequisites"),
    "pressKeyboard": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, нажмите клавишу.",
    ),
    "preview": MessageLookupByLibrary.simpleMessage("Предпросмотр"),
    "previousAnnouncement": MessageLookupByLibrary.simpleMessage("Назад"),
    "previousPage": MessageLookupByLibrary.simpleMessage("Назад"),
    "process": MessageLookupByLibrary.simpleMessage("процесс"),
    "profile": MessageLookupByLibrary.simpleMessage("Профиль"),
    "profileAutoUpdateIntervalInvalidValidationDesc":
        MessageLookupByLibrary.simpleMessage(
          "Пожалуйста, введите действительный формат интервала времени",
        ),
    "profileAutoUpdateIntervalNullValidationDesc":
        MessageLookupByLibrary.simpleMessage(
          "Пожалуйста, введите интервал времени для автообновления",
        ),
    "profileHasUpdate": MessageLookupByLibrary.simpleMessage(
      "Профиль был изменен. Хотите отключить автообновление?",
    ),
    "profileNameNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, введите имя профиля",
    ),
    "profileUrlInvalidValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, введите действительный URL профиля",
    ),
    "profileUrlNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, введите URL профиля",
    ),
    "profiles": MessageLookupByLibrary.simpleMessage("Профили"),
    "profilesSort": MessageLookupByLibrary.simpleMessage("Сортировка профилей"),
    "project": MessageLookupByLibrary.simpleMessage("Проект"),
    "protocolLabel": MessageLookupByLibrary.simpleMessage("Протокол"),
    "providers": MessageLookupByLibrary.simpleMessage("Провайдеры"),
    "provinceCity": MessageLookupByLibrary.simpleMessage("Регион/город"),
    "proxies": MessageLookupByLibrary.simpleMessage("Прокси"),
    "proxiesEmpty": MessageLookupByLibrary.simpleMessage("Список прокси пуст"),
    "proxyAccessAddress": MessageLookupByLibrary.simpleMessage(
      "Адрес локального прокси",
    ),
    "proxyChains": MessageLookupByLibrary.simpleMessage("Цепочки прокси"),
    "proxyDetectedAbnormal": MessageLookupByLibrary.simpleMessage(
      "Обнаружена аномалия выбранных прокси",
    ),
    "proxyFilter": MessageLookupByLibrary.simpleMessage("Фильтр прокси"),
    "proxyGroup": MessageLookupByLibrary.simpleMessage("Группа прокси"),
    "proxyGroupDetectedAbnormal": MessageLookupByLibrary.simpleMessage(
      "Обнаружена аномалия текущей группы прокси",
    ),
    "proxyGroupEmpty": MessageLookupByLibrary.simpleMessage(
      "Группа прокси пуста",
    ),
    "proxyGroupNameDuplicate": MessageLookupByLibrary.simpleMessage(
      "Имя группы прокси дублируется",
    ),
    "proxyGroupNameEmpty": MessageLookupByLibrary.simpleMessage(
      "Имя группы прокси не может быть пустым",
    ),
    "proxyNameDuplicate": MessageLookupByLibrary.simpleMessage(
      "Такое имя уже существует",
    ),
    "proxyNameserver": MessageLookupByLibrary.simpleMessage(
      "Прокси-сервер имен",
    ),
    "proxyNameserverDesc": MessageLookupByLibrary.simpleMessage(
      "Домен для разрешения прокси-узлов",
    ),
    "proxyNeededChooseNode": MessageLookupByLibrary.simpleMessage(
      "Нужен прокси: откройте список узлов и выберите узел, отличный от DIRECT.",
    ),
    "proxyPort": MessageLookupByLibrary.simpleMessage("Порт прокси"),
    "proxyProtocolMismatch": MessageLookupByLibrary.simpleMessage(
      "Неверный протокол. Обнаружен:",
    ),
    "proxyProviderDetectedAbnormal": MessageLookupByLibrary.simpleMessage(
      "Обнаружена аномалия выбранных провайдеров прокси",
    ),
    "proxyProviders": MessageLookupByLibrary.simpleMessage("Провайдеры прокси"),
    "proxyProvidersEmpty": MessageLookupByLibrary.simpleMessage(
      "Провайдеры прокси пусты",
    ),
    "proxyProvidersNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Провайдеры прокси не могут быть пустыми",
    ),
    "proxyServer": MessageLookupByLibrary.simpleMessage("Сервер"),
    "proxySettings": MessageLookupByLibrary.simpleMessage("Настройки прокси"),
    "proxySettingsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Управление локальным прокси-сервисом",
    ),
    "proxyType": MessageLookupByLibrary.simpleMessage("Тип прокси"),
    "proxyValidationFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось подключиться. Проверьте сервер, порт и учётные данны",
    ),
    "pruneCache": MessageLookupByLibrary.simpleMessage("Очистить кэш"),
    "publicIp": MessageLookupByLibrary.simpleMessage("Публичный IP"),
    "purchasePlan": MessageLookupByLibrary.simpleMessage("Тарифы"),
    "pureBlackMode": MessageLookupByLibrary.simpleMessage("Чисто черный режим"),
    "qrcode": MessageLookupByLibrary.simpleMessage("QR-код"),
    "qrcodeDesc": MessageLookupByLibrary.simpleMessage(
      "Сканируйте QR-код для получения профиля",
    ),
    "qualityNodes": MessageLookupByLibrary.simpleMessage("Качественные узлы"),
    "quarterlyBilling": MessageLookupByLibrary.simpleMessage("Квартал"),
    "queryNow": MessageLookupByLibrary.simpleMessage("Проверить"),
    "quickFill": MessageLookupByLibrary.simpleMessage("Быстрое заполнение"),
    "rainbowScheme": MessageLookupByLibrary.simpleMessage("Радужные"),
    "reachable": MessageLookupByLibrary.simpleMessage("Доступен"),
    "realTimeConnections": MessageLookupByLibrary.simpleMessage("Соединения"),
    "realTimeConnectionsSubtitle": MessageLookupByLibrary.simpleMessage(
      "VPN-ускорение активно и защищает сетевые подключения",
    ),
    "recurringPlans": MessageLookupByLibrary.simpleMessage("Периодические"),
    "redirPort": MessageLookupByLibrary.simpleMessage("Redir-порт"),
    "redo": MessageLookupByLibrary.simpleMessage("Повторить"),
    "refreshApiStatus": MessageLookupByLibrary.simpleMessage(
      "Обновить состояние API",
    ),
    "refreshConfiguration": MessageLookupByLibrary.simpleMessage(
      "Обновить конфигурацию",
    ),
    "refreshData": MessageLookupByLibrary.simpleMessage("Обновить"),
    "refreshNodes": MessageLookupByLibrary.simpleMessage("Обновить"),
    "refreshSubscription": MessageLookupByLibrary.simpleMessage(
      "Обновить подписку",
    ),
    "region": MessageLookupByLibrary.simpleMessage("Регион"),
    "registerAccount": MessageLookupByLibrary.simpleMessage("Создать аккаунт"),
    "registerAction": MessageLookupByLibrary.simpleMessage("Регистрация"),
    "registeredUsers": MessageLookupByLibrary.simpleMessage("Зарегистрировано"),
    "registrationApiPending": MessageLookupByLibrary.simpleMessage(
      "API регистрации еще не подключен",
    ),
    "registrationFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось зарегистрироваться. Повторите попытку позже",
    ),
    "registrationSuccess": MessageLookupByLibrary.simpleMessage(
      "Регистрация завершена",
    ),
    "reject": MessageLookupByLibrary.simpleMessage("Блокировать"),
    "remainingCommission": MessageLookupByLibrary.simpleMessage(
      "Доступная комиссия",
    ),
    "remainingTraffic": MessageLookupByLibrary.simpleMessage(
      "Осталось трафика",
    ),
    "remainingTrafficLabel": MessageLookupByLibrary.simpleMessage("Осталось"),
    "rememberMe": MessageLookupByLibrary.simpleMessage("Запомнить меня"),
    "rememberedPassword": MessageLookupByLibrary.simpleMessage(
      "Вспомнили пароль?",
    ),
    "remote": MessageLookupByLibrary.simpleMessage("Удаленный"),
    "remoteBackupDesc": MessageLookupByLibrary.simpleMessage(
      "Резервное копирование локальных данных на WebDAV",
    ),
    "remoteDestination": MessageLookupByLibrary.simpleMessage(
      "Удалённое назначение",
    ),
    "remove": MessageLookupByLibrary.simpleMessage("Удалить"),
    "rename": MessageLookupByLibrary.simpleMessage("Переименовать"),
    "renewPlanAction": MessageLookupByLibrary.simpleMessage("Продлить"),
    "renewalDoesNotResetTraffic": MessageLookupByLibrary.simpleMessage(
      "Продление увеличивает только срок действия тарифа и не сбрасывает использованный трафик. Чтобы восстановить квоту, выберите «Сбросить трафик».",
    ),
    "renewalNoticeTitle": MessageLookupByLibrary.simpleMessage(
      "Условия продления",
    ),
    "renewalUnavailable": MessageLookupByLibrary.simpleMessage(
      "Этот тариф сейчас нельзя продлить",
    ),
    "request": MessageLookupByLibrary.simpleMessage("Запрос"),
    "requestFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось выполнить запрос. Повторите попытку позже",
    ),
    "requests": MessageLookupByLibrary.simpleMessage("Запросы"),
    "requestsDesc": MessageLookupByLibrary.simpleMessage(
      "Просмотр последних записей запросов",
    ),
    "requiredField": MessageLookupByLibrary.simpleMessage("Обязательное поле"),
    "rerunOptimization": MessageLookupByLibrary.simpleMessage(
      "Повторить поиск",
    ),
    "reset": MessageLookupByLibrary.simpleMessage("Сброс"),
    "resetPageChangesTip": MessageLookupByLibrary.simpleMessage(
      "На текущей странице есть изменения. Вы уверены, что хотите сбросить?",
    ),
    "resetPasswordAction": MessageLookupByLibrary.simpleMessage(
      "Сбросить пароль",
    ),
    "resetSubscription": MessageLookupByLibrary.simpleMessage(
      "Сбросить подписку",
    ),
    "resetSubscriptionConfirmMessage": MessageLookupByLibrary.simpleMessage(
      "Старый адрес сразу перестанет работать, и все устройства потребуется синхронизировать заново.",
    ),
    "resetSubscriptionConfirmTitle": MessageLookupByLibrary.simpleMessage(
      "Сбросить подписку?",
    ),
    "resetSubscriptionDescription": MessageLookupByLibrary.simpleMessage(
      "Создайте новый адрес подписки, если текущий раскрыт или не работает",
    ),
    "resetTip": MessageLookupByLibrary.simpleMessage(
      "Убедитесь, что хотите сбросить",
    ),
    "resetTrafficAction": MessageLookupByLibrary.simpleMessage(
      "Сбросить трафик",
    ),
    "resettingPassword": MessageLookupByLibrary.simpleMessage("Сброс…"),
    "resources": MessageLookupByLibrary.simpleMessage("Ресурсы"),
    "resourcesDesc": MessageLookupByLibrary.simpleMessage(
      "Информация, связанная с внешними ресурсами",
    ),
    "respectRules": MessageLookupByLibrary.simpleMessage("Соблюдение правил"),
    "respectRulesDesc": MessageLookupByLibrary.simpleMessage(
      "DNS-соединение следует правилам, необходимо настроить proxy-server-nameserver",
    ),
    "restart": MessageLookupByLibrary.simpleMessage("Перезапустить"),
    "restartCoreTip": MessageLookupByLibrary.simpleMessage(
      "Вы уверены, что хотите перезапустить ядро?",
    ),
    "restore": MessageLookupByLibrary.simpleMessage("Восстановить"),
    "restoreAllData": MessageLookupByLibrary.simpleMessage(
      "Восстановить все данные",
    ),
    "restoreException": MessageLookupByLibrary.simpleMessage(
      "Ошибка восстановления",
    ),
    "restoreFromFileDesc": MessageLookupByLibrary.simpleMessage(
      "Восстановить данные из файла",
    ),
    "restoreFromWebDAVDesc": MessageLookupByLibrary.simpleMessage(
      "Восстановить данные через WebDAV",
    ),
    "restoreOnline": MessageLookupByLibrary.simpleMessage("Вернуться в онлайн"),
    "restoreOnlyConfig": MessageLookupByLibrary.simpleMessage(
      "Восстановить только файлы конфигурации",
    ),
    "restoreStrategy": MessageLookupByLibrary.simpleMessage(
      "Стратегия восстановления",
    ),
    "restoreStrategy_compatible": MessageLookupByLibrary.simpleMessage(
      "Совместимый",
    ),
    "restoreStrategy_override": MessageLookupByLibrary.simpleMessage(
      "Перезаписать",
    ),
    "restoreSuccess": MessageLookupByLibrary.simpleMessage(
      "Восстановление успешно",
    ),
    "restoringOnline": MessageLookupByLibrary.simpleMessage(
      "Восстановление онлайн-режима…",
    ),
    "retry": MessageLookupByLibrary.simpleMessage("Повторить"),
    "routeAddress": MessageLookupByLibrary.simpleMessage("Адрес маршрутизации"),
    "routeAddressDesc": MessageLookupByLibrary.simpleMessage(
      "Настройка адреса прослушивания маршрутизации",
    ),
    "routeMode": MessageLookupByLibrary.simpleMessage("Режим маршрутизации"),
    "routeMode_bypassPrivate": MessageLookupByLibrary.simpleMessage(
      "Обход частных адресов маршрутизации",
    ),
    "routeMode_config": MessageLookupByLibrary.simpleMessage(
      "Использовать конфигурацию",
    ),
    "ru": MessageLookupByLibrary.simpleMessage("Русский"),
    "rule": MessageLookupByLibrary.simpleMessage("Правило"),
    "ruleActionAndDesc": MessageLookupByLibrary.simpleMessage(
      "Логическое правило AND",
    ),
    "ruleActionDomainDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить полный домен",
    ),
    "ruleActionDomainKeywordDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить ключевое слово домена",
    ),
    "ruleActionDomainRegexDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставление по маске, поддерживает только * и ?",
    ),
    "ruleActionDomainSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить суффикс домена",
    ),
    "ruleActionDscpDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить метку DSCP (только для tproxy udp inbound)",
    ),
    "ruleActionDstPortDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон портов назначения запроса",
    ),
    "ruleActionGeoipDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить код страны IP-адреса",
    ),
    "ruleActionGeositeDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить домены внутри Geosite",
    ),
    "ruleActionInNameDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить входящее имя",
    ),
    "ruleActionInPortDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить входящий порт",
    ),
    "ruleActionInTypeDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить входящий тип",
    ),
    "ruleActionInUserDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить входящее имя пользователя, поддерживает несколько имен через /",
    ),
    "ruleActionIpAsnDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить ASN IP-адреса",
    ),
    "ruleActionIpCidr6Desc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон IP-адресов (IP-CIDR6 — это просто псевдоним)",
    ),
    "ruleActionIpCidrDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон IP-адресов",
    ),
    "ruleActionIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон суффиксов IP",
    ),
    "ruleActionMatchDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить все запросы, условия не требуются",
    ),
    "ruleActionNetworkDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить TCP или UDP",
    ),
    "ruleActionNotDesc": MessageLookupByLibrary.simpleMessage(
      "Логическое правило NOT",
    ),
    "ruleActionOrDesc": MessageLookupByLibrary.simpleMessage(
      "Логическое правило OR",
    ),
    "ruleActionProcessNameDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить по имени процесса, на Android соответствует имени пакета",
    ),
    "ruleActionProcessNameRegexDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить по регулярному выражению имени процесса, на Android соответствует имени пакета",
    ),
    "ruleActionProcessPathDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить по полному пути процесса",
    ),
    "ruleActionProcessPathRegexDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить по регулярному выражению пути процесса",
    ),
    "ruleActionRuleSetDesc": MessageLookupByLibrary.simpleMessage(
      "Ссылка на набор правил, требуется настройка rule-providers",
    ),
    "ruleActionSrcGeoipDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить код страны исходного IP",
    ),
    "ruleActionSrcIpAsnDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить ASN исходного IP",
    ),
    "ruleActionSrcIpCidrDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон исходных IP-адресов",
    ),
    "ruleActionSrcIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон исходных суффиксов IP",
    ),
    "ruleActionSrcPortDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить диапазон портов источника запроса",
    ),
    "ruleActionSubRuleDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить с подправилом, обратите внимание на использование скобок",
    ),
    "ruleActionUidDesc": MessageLookupByLibrary.simpleMessage(
      "Сопоставить Linux USER ID",
    ),
    "ruleEmpty": MessageLookupByLibrary.simpleMessage("Правило пусто"),
    "ruleName": MessageLookupByLibrary.simpleMessage("Название правила"),
    "ruleProviders": MessageLookupByLibrary.simpleMessage("Провайдеры правил"),
    "ruleSet": MessageLookupByLibrary.simpleMessage("Набор правил"),
    "ruleTarget": MessageLookupByLibrary.simpleMessage("Цель правила"),
    "ruleType": MessageLookupByLibrary.simpleMessage("Тип правила"),
    "ruleTypeHelp": MessageLookupByLibrary.simpleMessage(
      "DOMAIN соответствует точному домену, DOMAIN-SUFFIX также включает поддомены",
    ),
    "runNetworkDiagnostics": MessageLookupByLibrary.simpleMessage(
      "Запустить диагностику сети",
    ),
    "save": MessageLookupByLibrary.simpleMessage("Сохранить"),
    "saveChanges": MessageLookupByLibrary.simpleMessage("Сохранить изменения"),
    "savedDnsServersCount": m37,
    "scanToPay": MessageLookupByLibrary.simpleMessage("Сканируйте для оплаты"),
    "scanWithPaymentApp": MessageLookupByLibrary.simpleMessage(
      "Отсканируйте QR-код ниже подходящим платёжным приложением",
    ),
    "script": MessageLookupByLibrary.simpleMessage("Скрипт"),
    "scriptModeDesc": MessageLookupByLibrary.simpleMessage(
      "Режим скрипта, использование внешних расширяющих скриптов, предоставление возможности переопределения конфигурации одним кликом",
    ),
    "search": MessageLookupByLibrary.simpleMessage("Поиск"),
    "searchConnectionsHint": MessageLookupByLibrary.simpleMessage(
      "Поиск домена, IP, правила или узла",
    ),
    "seconds": MessageLookupByLibrary.simpleMessage("Секунд"),
    "secondsCount": m38,
    "selectAll": MessageLookupByLibrary.simpleMessage("Выбрать все"),
    "selectPaymentMethod": MessageLookupByLibrary.simpleMessage(
      "Выберите способ оплаты",
    ),
    "selectProxies": MessageLookupByLibrary.simpleMessage("Выбрать прокси"),
    "selectProxyGroup": MessageLookupByLibrary.simpleMessage(
      "Выберите прокси-группу",
    ),
    "selectProxyProviders": MessageLookupByLibrary.simpleMessage(
      "Выбрать провайдеров прокси",
    ),
    "selectRenewalPeriod": MessageLookupByLibrary.simpleMessage(
      "Выберите срок продления",
    ),
    "selectRuleSet": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, выберите набор правил",
    ),
    "selectSplitStrategy": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, выберите стратегию разделения",
    ),
    "selectSubRule": MessageLookupByLibrary.simpleMessage(
      "Пожалуйста, выберите подправило",
    ),
    "selectWithdrawalMethod": MessageLookupByLibrary.simpleMessage(
      "Выберите способ вывода",
    ),
    "selected": MessageLookupByLibrary.simpleMessage("Выбрано"),
    "selectedCountTitle": m39,
    "sendVerificationCode": MessageLookupByLibrary.simpleMessage("Отправить"),
    "sendingVerificationCode": MessageLookupByLibrary.simpleMessage(
      "Отправка...",
    ),
    "serviceStatus": MessageLookupByLibrary.simpleMessage("Состояние сервиса"),
    "settings": MessageLookupByLibrary.simpleMessage("Настройки"),
    "show": MessageLookupByLibrary.simpleMessage("Показать"),
    "showPassword": MessageLookupByLibrary.simpleMessage("Показать пароль"),
    "shrink": MessageLookupByLibrary.simpleMessage("Сжать"),
    "silentLaunch": MessageLookupByLibrary.simpleMessage("Тихий запуск"),
    "silentLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "Запуск в фоновом режиме",
    ),
    "size": MessageLookupByLibrary.simpleMessage("Размер"),
    "socksPort": MessageLookupByLibrary.simpleMessage("Socks-порт"),
    "soldOut": MessageLookupByLibrary.simpleMessage("Распродано"),
    "sort": MessageLookupByLibrary.simpleMessage("Сортировка"),
    "source": MessageLookupByLibrary.simpleMessage("Источник"),
    "sourceIp": MessageLookupByLibrary.simpleMessage("Исходный IP"),
    "specialProxy": MessageLookupByLibrary.simpleMessage("Специальный прокси"),
    "specialRules": MessageLookupByLibrary.simpleMessage("Специальные правила"),
    "speedStatistics": MessageLookupByLibrary.simpleMessage(
      "Статистика скорости",
    ),
    "speedTest": MessageLookupByLibrary.simpleMessage("Тест скорости"),
    "speedTestDescription": MessageLookupByLibrary.simpleMessage(
      "Проверка текущей скорости через сторонний сервис",
    ),
    "splitStrategy": MessageLookupByLibrary.simpleMessage(
      "Стратегия разделения",
    ),
    "splitStrategyNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Стратегия разделения не может быть пустой",
    ),
    "ssidsEmpty": MessageLookupByLibrary.simpleMessage("SSIDs is empty"),
    "stackMode": MessageLookupByLibrary.simpleMessage("Режим стека"),
    "standard": MessageLookupByLibrary.simpleMessage("Стандартный"),
    "standardModeDesc": MessageLookupByLibrary.simpleMessage(
      "Стандартный режим, переопределение базовой конфигурации, предоставление возможности простого добавления правил",
    ),
    "standardizedDelay": MessageLookupByLibrary.simpleMessage(
      "Стандартный RTT",
    ),
    "start": MessageLookupByLibrary.simpleMessage("Старт"),
    "startAcceleration": MessageLookupByLibrary.simpleMessage(
      "Начать ускорение",
    ),
    "startOptimization": MessageLookupByLibrary.simpleMessage("Начать поиск"),
    "startTest": MessageLookupByLibrary.simpleMessage("Начать проверку"),
    "startVpn": MessageLookupByLibrary.simpleMessage("Запуск VPN..."),
    "status": MessageLookupByLibrary.simpleMessage("Статус"),
    "statusDesc": MessageLookupByLibrary.simpleMessage(
      "Системный DNS будет использоваться при выключении",
    ),
    "stop": MessageLookupByLibrary.simpleMessage("Стоп"),
    "stopAcceleration": MessageLookupByLibrary.simpleMessage(
      "Остановить ускорение",
    ),
    "stopVpn": MessageLookupByLibrary.simpleMessage("Остановка VPN..."),
    "streamingExitRegion": MessageLookupByLibrary.simpleMessage(
      "Регион выхода",
    ),
    "streamingFailed": MessageLookupByLibrary.simpleMessage(
      "Ошибка подключения",
    ),
    "streamingNetworkError": MessageLookupByLibrary.simpleMessage(
      "Ошибка сетевого подключения",
    ),
    "streamingProxyRequired": MessageLookupByLibrary.simpleMessage(
      "Перед проверкой запустите ускорение и выберите прокси-узел",
    ),
    "streamingReachable": MessageLookupByLibrary.simpleMessage(
      "Веб-страница доступна, подробный статус не подтверждён",
    ),
    "streamingReachableProbeFailed": MessageLookupByLibrary.simpleMessage(
      "Веб-страница доступна, подробный статус не подтверждён",
    ),
    "streamingReachableProbeTimedOut": MessageLookupByLibrary.simpleMessage(
      "Веб-страница доступна, время подробной проверки истекло",
    ),
    "streamingRestricted": MessageLookupByLibrary.simpleMessage(
      "Ограничено по региону",
    ),
    "streamingServiceError": MessageLookupByLibrary.simpleMessage(
      "Сервис временно недоступен",
    ),
    "streamingTimedOut": MessageLookupByLibrary.simpleMessage(
      "Время проверки истекло. Повторите попытку",
    ),
    "streamingUnlockTest": MessageLookupByLibrary.simpleMessage(
      "Проверка стриминга",
    ),
    "streamingUnlockTestDescription": MessageLookupByLibrary.simpleMessage(
      "Проверка доступности стриминговых и ИИ-сервисов",
    ),
    "streamingUnlocked": MessageLookupByLibrary.simpleMessage(
      "Веб-страница доступна",
    ),
    "style": MessageLookupByLibrary.simpleMessage("Стиль"),
    "subRule": MessageLookupByLibrary.simpleMessage("Подправило"),
    "subRuleEmpty": MessageLookupByLibrary.simpleMessage("Подправило пусто"),
    "subRuleNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Подправило не может быть пустым",
    ),
    "submit": MessageLookupByLibrary.simpleMessage("Отправить"),
    "submitWithdrawalTicket": MessageLookupByLibrary.simpleMessage(
      "Отправить заявку",
    ),
    "subscriptionExpiredWarning": m40,
    "subscriptionExpiringWarning": m41,
    "subscriptionImportFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось загрузить узлы подписки. Проверьте сеть и повторите попытку",
    ),
    "subscriptionLowTrafficWarning": m42,
    "subscriptionNormalTooltip": MessageLookupByLibrary.simpleMessage(
      "Тариф в норме. Нажмите, чтобы узнать подробности",
    ),
    "subscriptionPlanUnavailable": MessageLookupByLibrary.simpleMessage(
      "Не удалось найти текущий тариф. Обновите данные и повторите попытку",
    ),
    "subscriptionResetSuccess": MessageLookupByLibrary.simpleMessage(
      "Подписка сброшена и синхронизирована",
    ),
    "subscriptionStatusNormalMessage": MessageLookupByLibrary.simpleMessage(
      "Остаток трафика и срок действия тарифа находятся в норме.",
    ),
    "subscriptionStatusNormalTitle": MessageLookupByLibrary.simpleMessage(
      "Тариф в норме",
    ),
    "subscriptionWarningTitle": MessageLookupByLibrary.simpleMessage(
      "Предупреждение о тарифе",
    ),
    "subscriptionWarningTooltip": MessageLookupByLibrary.simpleMessage(
      "Предупреждение о тарифе. Нажмите, чтобы узнать подробности",
    ),
    "suspended": MessageLookupByLibrary.simpleMessage("Приостановлено..."),
    "switchAndDirect": MessageLookupByLibrary.simpleMessage(
      "Переключить и использовать DIRECT",
    ),
    "switchNode": MessageLookupByLibrary.simpleMessage("Сменить узел"),
    "switchToGlobalMode": MessageLookupByLibrary.simpleMessage(
      "Переключиться в глобальный режим",
    ),
    "sync": MessageLookupByLibrary.simpleMessage("Синхронизация"),
    "system": MessageLookupByLibrary.simpleMessage("Система"),
    "systemApp": MessageLookupByLibrary.simpleMessage("Системное приложение"),
    "systemProxy": MessageLookupByLibrary.simpleMessage("Системный прокси"),
    "systemProxyApplyFailed": m43,
    "systemProxyDesc": MessageLookupByLibrary.simpleMessage(
      "Прикрепить HTTP-прокси к VpnService",
    ),
    "systemProxyDisableFailed": m44,
    "systemProxyStaleCleaned": MessageLookupByLibrary.simpleMessage(
      "Системный прокси, оставшийся после предыдущего аварийного завершения, очищен",
    ),
    "tab": MessageLookupByLibrary.simpleMessage("Вкладка"),
    "tabAnimation": MessageLookupByLibrary.simpleMessage("Анимация вкладок"),
    "tabAnimationDesc": MessageLookupByLibrary.simpleMessage(
      "Действительно только в мобильном виде",
    ),
    "tapToAuthorize": MessageLookupByLibrary.simpleMessage(
      "Нажмите, чтобы разрешить",
    ),
    "targetPolicy": MessageLookupByLibrary.simpleMessage("Целевая политика"),
    "tcpConcurrent": MessageLookupByLibrary.simpleMessage("TCP параллелизм"),
    "tcpConcurrentDesc": MessageLookupByLibrary.simpleMessage(
      "Включение позволит использовать параллелизм TCP",
    ),
    "telegramBinding": MessageLookupByLibrary.simpleMessage(
      "Привязка Telegram",
    ),
    "telegramId": MessageLookupByLibrary.simpleMessage("Telegram ID"),
    "telegramUnboundHint": MessageLookupByLibrary.simpleMessage(
      "Telegram не привязан к этому аккаунту",
    ),
    "testAll": MessageLookupByLibrary.simpleMessage("Проверить все"),
    "testAllEndpoints": MessageLookupByLibrary.simpleMessage("Проверить все"),
    "testEndpoint": MessageLookupByLibrary.simpleMessage("Проверить"),
    "testInterval": MessageLookupByLibrary.simpleMessage(
      "Интервал тестирования",
    ),
    "testUrl": MessageLookupByLibrary.simpleMessage("Тест URL"),
    "testWhenUsed": MessageLookupByLibrary.simpleMessage(
      "Тестировать при использовании",
    ),
    "testingStatus": MessageLookupByLibrary.simpleMessage("Проверка"),
    "textScale": MessageLookupByLibrary.simpleMessage("Масштабирование текста"),
    "theme": MessageLookupByLibrary.simpleMessage("Тема"),
    "themeColor": MessageLookupByLibrary.simpleMessage("Цвет темы"),
    "themeDesc": MessageLookupByLibrary.simpleMessage(
      "Установить темный режим, настроить цвет",
    ),
    "themeMode": MessageLookupByLibrary.simpleMessage("Режим темы"),
    "threeYearBilling": MessageLookupByLibrary.simpleMessage("3 года"),
    "tight": MessageLookupByLibrary.simpleMessage("Плотный"),
    "time": MessageLookupByLibrary.simpleMessage("Время"),
    "timeout": MessageLookupByLibrary.simpleMessage("Таймаут"),
    "timezoneLabel": MessageLookupByLibrary.simpleMessage("Часовой пояс"),
    "tip": MessageLookupByLibrary.simpleMessage("подсказка"),
    "todayTraffic": MessageLookupByLibrary.simpleMessage("Сегодня"),
    "toggle": MessageLookupByLibrary.simpleMessage("Переключить"),
    "tonalSpotScheme": MessageLookupByLibrary.simpleMessage("Тональный акцент"),
    "toolbox": MessageLookupByLibrary.simpleMessage("Инструменты"),
    "tools": MessageLookupByLibrary.simpleMessage("Инструменты"),
    "totalCommission": MessageLookupByLibrary.simpleMessage("Всего заработано"),
    "totalOrders": m45,
    "totalTrafficLabel": MessageLookupByLibrary.simpleMessage("Всего"),
    "tproxyPort": MessageLookupByLibrary.simpleMessage("Tproxy-порт"),
    "trafficDetailRecords": MessageLookupByLibrary.simpleMessage(
      "Журнал трафика",
    ),
    "trafficDetails": MessageLookupByLibrary.simpleMessage("Трафик"),
    "trafficDetailsSubtitle": MessageLookupByLibrary.simpleMessage(
      "Просматривайте расход и тенденции использования сети",
    ),
    "trafficEmailReminder": MessageLookupByLibrary.simpleMessage(
      "Напоминание о трафике по почте",
    ),
    "trafficRate": MessageLookupByLibrary.simpleMessage("Коэффициент"),
    "trafficRecordsFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось загрузить данные о трафике",
    ),
    "trafficResetBilling": MessageLookupByLibrary.simpleMessage("Сброс"),
    "trafficResetUnavailable": MessageLookupByLibrary.simpleMessage(
      "Для этого тарифа сейчас недоступен сброс трафика",
    ),
    "trafficUsage": MessageLookupByLibrary.simpleMessage(
      "Использование трафика",
    ),
    "tun": MessageLookupByLibrary.simpleMessage("TUN"),
    "tunDesc": MessageLookupByLibrary.simpleMessage(
      "действительно только в режиме администратора",
    ),
    "turnOff": MessageLookupByLibrary.simpleMessage("Выключить"),
    "turnOn": MessageLookupByLibrary.simpleMessage("Включить"),
    "twoYearBilling": MessageLookupByLibrary.simpleMessage("2 года"),
    "unbound": MessageLookupByLibrary.simpleMessage("Не привязан"),
    "undo": MessageLookupByLibrary.simpleMessage("Отменить"),
    "unifiedDelay": MessageLookupByLibrary.simpleMessage(
      "Унифицированная задержка",
    ),
    "unifiedDelayDesc": MessageLookupByLibrary.simpleMessage(
      "Убрать дополнительные задержки, такие как рукопожатие",
    ),
    "unknown": MessageLookupByLibrary.simpleMessage("Неизвестно"),
    "unknownNetworkError": MessageLookupByLibrary.simpleMessage(
      "Неизвестная сетевая ошибка",
    ),
    "unlimitedTime": MessageLookupByLibrary.simpleMessage("Без срока"),
    "unnamed": MessageLookupByLibrary.simpleMessage("Без имени"),
    "unreachable": MessageLookupByLibrary.simpleMessage("Недоступен"),
    "update": MessageLookupByLibrary.simpleMessage("Обновить"),
    "updateAll": MessageLookupByLibrary.simpleMessage("Обновить всё"),
    "upgradePlanAction": MessageLookupByLibrary.simpleMessage("Улучшить тариф"),
    "upload": MessageLookupByLibrary.simpleMessage("Загрузка"),
    "uploadSpeed": MessageLookupByLibrary.simpleMessage("Скорость отдачи"),
    "uploadTraffic": MessageLookupByLibrary.simpleMessage("Отдача"),
    "uploaded": MessageLookupByLibrary.simpleMessage("Отправлено"),
    "url": MessageLookupByLibrary.simpleMessage("URL"),
    "urlDesc": MessageLookupByLibrary.simpleMessage(
      "Получить профиль через URL",
    ),
    "urlTip": m46,
    "useHosts": MessageLookupByLibrary.simpleMessage("Использовать hosts"),
    "useSystemHosts": MessageLookupByLibrary.simpleMessage(
      "Использовать системные hosts",
    ),
    "usedTrafficLabel": MessageLookupByLibrary.simpleMessage("Использовано"),
    "userAgent": MessageLookupByLibrary.simpleMessage("User-Agent"),
    "userInfoFailed": MessageLookupByLibrary.simpleMessage(
      "Не удалось загрузить данные аккаунта",
    ),
    "userMapLabel": MessageLookupByLibrary.simpleMessage("Пользователь"),
    "username": MessageLookupByLibrary.simpleMessage("Имя пользователя"),
    "validatingProxy": MessageLookupByLibrary.simpleMessage("Проверка прокси…"),
    "validatingTargets": MessageLookupByLibrary.simpleMessage(
      "Проверка целевых доменов и выбранных IP",
    ),
    "value": MessageLookupByLibrary.simpleMessage("Значение"),
    "verificationApiPending": MessageLookupByLibrary.simpleMessage(
      "API подтверждения еще не подключен",
    ),
    "verificationEmailSent": MessageLookupByLibrary.simpleMessage(
      "Код отправлен. Если письмо не пришло, проверьте папку спама",
    ),
    "vibrantScheme": MessageLookupByLibrary.simpleMessage("Яркие"),
    "view": MessageLookupByLibrary.simpleMessage("Просмотр"),
    "viewApps": MessageLookupByLibrary.simpleMessage("Открыть список"),
    "viewDetails": MessageLookupByLibrary.simpleMessage("Подробнее"),
    "viewOrderDetails": MessageLookupByLibrary.simpleMessage("Подробнее"),
    "vpnConfigChangeDetected": MessageLookupByLibrary.simpleMessage(
      "Обнаружено изменение конфигурации VPN",
    ),
    "vpnEnableDesc": MessageLookupByLibrary.simpleMessage(
      "Автоматически направляет весь системный трафик через VpnService",
    ),
    "vpnTip": MessageLookupByLibrary.simpleMessage(
      "Изменения вступят в силу после перезапуска VPN",
    ),
    "waitingForPayment": MessageLookupByLibrary.simpleMessage(
      "Ожидание оплаты",
    ),
    "webDAVConfiguration": MessageLookupByLibrary.simpleMessage(
      "Конфигурация WebDAV",
    ),
    "whatHappensAfterSwitch": MessageLookupByLibrary.simpleMessage(
      "Что произойдёт после переключения",
    ),
    "whitelistMode": MessageLookupByLibrary.simpleMessage(
      "Режим белого списка",
    ),
    "withdrawalAccount": MessageLookupByLibrary.simpleMessage(
      "Счёт получателя",
    ),
    "withdrawalAmount": MessageLookupByLibrary.simpleMessage("Сумма вывода"),
    "withdrawalAmountExceeds": MessageLookupByLibrary.simpleMessage(
      "Сумма не может превышать доступную комиссию",
    ),
    "withdrawalAmountInvalid": MessageLookupByLibrary.simpleMessage(
      "Введите корректную сумму",
    ),
    "withdrawalMethod": MessageLookupByLibrary.simpleMessage("Способ вывода"),
    "withdrawalMethodAlipay": MessageLookupByLibrary.simpleMessage("Alipay"),
    "withdrawalMethodBank": MessageLookupByLibrary.simpleMessage(
      "Банковская карта",
    ),
    "withdrawalMethodUsdt": MessageLookupByLibrary.simpleMessage("USDT"),
    "withdrawalMethodWechat": MessageLookupByLibrary.simpleMessage(
      "WeChat Pay",
    ),
    "withdrawalRequestTitle": MessageLookupByLibrary.simpleMessage(
      "Заявка на вывод комиссии",
    ),
    "withdrawalTicketCreated": MessageLookupByLibrary.simpleMessage(
      "Заявка отправлена. Дождитесь обработки администратором.",
    ),
    "withdrawalTicketDescription": MessageLookupByLibrary.simpleMessage(
      "В системе будет создана заявка, которую обработает администратор.",
    ),
    "yearlyBilling": MessageLookupByLibrary.simpleMessage("Год"),
    "yearsAgo": m47,
    "zh_CN": MessageLookupByLibrary.simpleMessage("Упрощенный китайский"),
    "zoomIn": MessageLookupByLibrary.simpleMessage("Увеличить"),
    "zoomOut": MessageLookupByLibrary.simpleMessage("Уменьшить"),
  };
}
