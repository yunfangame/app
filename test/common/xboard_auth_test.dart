import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/api_endpoint_preference.dart';
import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/subscription_v2.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('builds the XBoard V1 login path from a configured host', () {
    expect(
      buildXboardLoginUri(Uri.parse('https://api.example.com:15699/base')),
      Uri.parse('https://api.example.com:15699/api/v1/passport/auth/login'),
    );
  });

  test('builds the XBoard V1 registration path from a configured host', () {
    expect(
      buildXboardRegisterUri(Uri.parse('https://api.example.com:15699/base')),
      Uri.parse('https://api.example.com:15699/api/v1/passport/auth/register'),
    );
  });

  test('builds the XBoard V1 forgot-password path from a configured host', () {
    expect(
      buildXboardForgetPasswordUri(
        Uri.parse('https://api.example.com:15699/base'),
      ),
      Uri.parse('https://api.example.com:15699/api/v1/passport/auth/forget'),
    );
  });

  test('builds the XBoard traffic log path from a configured host', () {
    expect(
      buildXboardTrafficLogUri(Uri.parse('https://api.example.com:15699/base')),
      Uri.parse('https://api.example.com:15699/api/v1/user/stat/getTrafficLog'),
    );
  });

  test('loads every XBoard notice page with tags and HTML content', () async {
    var requests = 0;
    final service = XboardAuthService(
      noticesRequester: (endpoint, authData) async {
        requests++;
        expect(endpoint.path, xboardNoticeFetchPath);
        expect(authData, 'Bearer notice-token');
        final current = endpoint.queryParameters['current'];
        if (current == '1') {
          return const XboardLoginResponse(
            statusCode: 200,
            data: {
              'data': [
                {
                  'id': 2,
                  'title': '重要公告',
                  'content': '<p><strong>富文本</strong></p>',
                  'tags': '["弹窗"]',
                  'img_url': '/images/notice.png',
                  'created_at': 1787996400,
                  'updated_at': 1787996500,
                },
              ],
              'total': 2,
            },
          );
        }
        return const XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': [
              {
                'id': 1,
                'title': '普通公告',
                'content': '<ul><li>内容</li></ul>',
                'tags': [],
                'created_at': 1787992800,
              },
            ],
            'total': 2,
          },
        );
      },
    );

    final notices = await service.fetchNotices(
      endpoint: Uri.parse('https://api.example.com/login'),
      authData: 'Bearer notice-token',
    );

    expect(requests, 2);
    expect(notices, hasLength(2));
    expect(notices.first.title, '重要公告');
    expect(notices.first.content, contains('<strong>'));
    expect(notices.first.tags, ['弹窗']);
    expect(notices.first.isPopup, isTrue);
    expect(
      notices.first.imageUrl,
      Uri.parse('https://api.example.com/images/notice.png'),
    );
    expect(notices.last.isPopup, isFalse);
  });

  test(
    'uses XBoard invitation, commission, transfer, and ticket APIs',
    () async {
      var generated = false;
      var transferredAmount = 0;
      var ticketSubject = '';
      var ticketLevel = 0;
      var ticketMessage = '';
      final service = XboardAuthService(
        inviteFetchRequester: (endpoint, authData) async {
          expect(
            endpoint,
            Uri.parse('https://api.example.com/api/v1/user/invite/fetch'),
          );
          expect(authData, 'Bearer invite-token');
          return const XboardLoginResponse(
            statusCode: 200,
            data: {
              'data': {
                'codes': [
                  {
                    'code': 'SIQU5wev',
                    'pv': 8,
                    'status': 0,
                    'created_at': 1787126400,
                  },
                ],
                'stat': [3, 12500, 2300, 10, 8000],
              },
            },
          );
        },
        inviteDetailsRequester: (endpoint, authData) async {
          expect(endpoint.path, xboardInviteDetailsPath);
          expect(endpoint.queryParameters['page_size'], '50');
          return const XboardLoginResponse(
            statusCode: 200,
            data: {
              'data': [
                {
                  'id': 9,
                  'order_amount': 10000,
                  'trade_no': '20260829001',
                  'get_amount': 1000,
                  'created_at': 1787961600,
                },
              ],
              'total': 1,
            },
          );
        },
        inviteSaveRequester: (endpoint, authData) async {
          expect(endpoint.path, xboardInviteSavePath);
          generated = true;
          return const XboardLoginResponse(
            statusCode: 200,
            data: {'data': true},
          );
        },
        commissionTransferRequester: (endpoint, authData, amount) async {
          expect(endpoint.path, xboardCommissionTransferPath);
          transferredAmount = amount;
          return const XboardLoginResponse(
            statusCode: 200,
            data: {'data': true},
          );
        },
        ticketSaveRequester:
            (endpoint, authData, subject, level, message) async {
              expect(endpoint.path, xboardTicketSavePath);
              ticketSubject = subject;
              ticketLevel = level;
              ticketMessage = message;
              return const XboardLoginResponse(
                statusCode: 200,
                data: {'data': true},
              );
            },
      );
      final endpoint = Uri.parse('https://api.example.com/login');
      const authData = 'Bearer invite-token';

      final summary = await service.fetchInviteSummary(
        endpoint: endpoint,
        authData: authData,
      );
      final records = await service.fetchInviteDetails(
        endpoint: endpoint,
        authData: authData,
      );
      await service.generateInviteCode(endpoint: endpoint, authData: authData);
      await service.transferCommission(
        endpoint: endpoint,
        authData: authData,
        amount: 8000,
      );
      await service.createTicket(
        endpoint: endpoint,
        authData: authData,
        subject: '佣金提现申请',
        level: 2,
        message: '提现方式: USDT\n提现金额: 50.00 CNY',
      );

      expect(summary.codes.single.code, 'SIQU5wev');
      expect(summary.codes.single.pageViews, 8);
      expect(summary.registeredUsers, 3);
      expect(summary.confirmedCommissionAmount, 125);
      expect(summary.pendingCommissionAmount, 23);
      expect(summary.commissionRate, 10);
      expect(summary.availableCommissionAmount, 80);
      expect(records.single.tradeNo, '20260829001');
      expect(records.single.amount, 10);
      expect(generated, isTrue);
      expect(transferredAmount, 8000);
      expect(ticketSubject, '佣金提现申请');
      expect(ticketLevel, 2);
      expect(ticketMessage, contains('USDT'));
      expect(ticketMessage, contains('50.00'));
    },
  );

  test('loads and sorts metered XBoard traffic records', () async {
    final service = XboardAuthService(
      trafficLogsRequester: (endpoint, authData) async {
        expect(
          endpoint,
          Uri.parse('https://api.example.com/api/v1/user/stat/getTrafficLog'),
        );
        expect(authData, 'Bearer traffic-token');
        return const XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': [
              {'d': 2048, 'u': 1024, 'record_at': 1700000000, 'server_rate': 2},
              {
                'd': '4096',
                'u': '1024',
                'record_at': '1700003600',
                'server_rate': '0.5',
              },
            ],
          },
        );
      },
    );

    final records = await service.fetchTrafficLogs(
      endpoint: Uri.parse('https://api.example.com/login'),
      authData: 'Bearer traffic-token',
    );

    expect(records, hasLength(2));
    expect(records.first.recordAtEpochSeconds, 1700003600);
    expect(records.first.downloadBytes, 4096);
    expect(records.first.uploadBytes, 1024);
    expect(records.first.serverRate, 0.5);
    expect(records.first.billedBytes, 2560);
    expect(records.last.billedBytes, 6144);
  });

  test('loads order history, details, and cancels pending orders', () async {
    var cancelledTradeNo = '';
    final service = XboardAuthService(
      ordersRequester: (endpoint, authData) async {
        expect(
          endpoint,
          Uri.parse('https://api.example.com/api/v1/user/order/fetch'),
        );
        expect(authData, 'Bearer order-token');
        return const XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': [
              {
                'id': 8,
                'trade_no': '20260829002',
                'period': 'reset_price',
                'total_amount': 700,
                'status': 0,
                'created_at': 1787996400,
                'plan': {'name': '60G 流量包'},
              },
              {
                'id': 7,
                'trade_no': '20260829001',
                'period': 'month_price',
                'total_amount': 800,
                'status': 3,
                'created_at': 1787992800,
                'plan': {'name': '包月套餐'},
              },
            ],
          },
        );
      },
      orderDetailRequester: (endpoint, authData) async {
        expect(endpoint.path, xboardOrderDetailPath);
        expect(endpoint.queryParameters['trade_no'], '20260829002');
        return const XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': {
              'id': 8,
              'trade_no': '20260829002',
              'period': 'reset_price',
              'total_amount': 700,
              'handling_amount': 50,
              'status': 0,
              'created_at': 1787996400,
              'plan': {'name': '60G 流量包'},
              'payment': {'name': '支付宝'},
            },
          },
        );
      },
      orderCancelRequester: (endpoint, authData, tradeNo) async {
        expect(endpoint.path, xboardOrderCancelPath);
        cancelledTradeNo = tradeNo;
        return const XboardLoginResponse(statusCode: 200, data: {'data': true});
      },
    );
    final endpoint = Uri.parse('https://api.example.com/login');
    const authData = 'Bearer order-token';

    final orders = await service.fetchOrders(
      endpoint: endpoint,
      authData: authData,
    );
    final detail = await service.fetchOrderDetail(
      endpoint: endpoint,
      authData: authData,
      tradeNo: '20260829002',
    );
    await service.cancelOrder(
      endpoint: endpoint,
      authData: authData,
      tradeNo: '20260829002',
    );

    expect(orders, hasLength(2));
    expect(orders.first.tradeNo, '20260829002');
    expect(orders.first.canCancel, isTrue);
    expect(orders.last.planName, '包月套餐');
    expect(detail.paymentName, '支付宝');
    expect(detail.handlingAmount, 50);
    expect(cancelledTradeNo, '20260829002');
  });

  test(
    'loads node rates and deduplicated tags from the XBoard node API',
    () async {
      final service = XboardAuthService(
        nodesRequester: (endpoint, authData) async {
          expect(
            endpoint,
            Uri.parse('https://api.example.com/api/v1/user/server/fetch'),
          );
          expect(authData, 'Bearer node-token');
          return const XboardLoginResponse(
            statusCode: 200,
            data: {
              'data': [
                {
                  'id': 10,
                  'name': '美国圣何塞',
                  'type': 'hysteria2',
                  'rate': '3.5',
                  'tags': ['US', 'Netflix'],
                  'is_online': 1,
                },
              ],
            },
          );
        },
      );

      final nodes = await service.fetchNodes(
        endpoint: Uri.parse(
          'https://api.example.com/api/v1/passport/auth/login',
        ),
        authData: 'Bearer node-token',
      );

      expect(nodes, hasLength(1));
      expect(nodes.single.name, '美国圣何塞');
      expect(nodes.single.rate, 3.5);
      expect(nodes.single.tags, ['US', 'Netflix']);
      expect(nodes.single.isOnline, isTrue);
    },
  );

  test('loads XBoard plans and billing prices', () async {
    final service = XboardAuthService(
      plansRequester: (endpoint, authData) async {
        expect(
          endpoint,
          Uri.parse('https://api.example.com/api/v1/user/plan/fetch'),
        );
        expect(authData, 'Bearer plan-token');
        return const XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': [
              {
                'id': 7,
                'name': '蜂窝全球套餐',
                'tags': ['热门', '专线'],
                'content': '高速专线\n流媒体解锁',
                'transfer_enable': 2000,
                'speed_limit': 500,
                'device_limit': 5,
                'month_price': 1500,
                'year_price': 12000,
                'onetime_price': null,
                'capacity_limit': 20,
                'sell': 1,
                'renew': 1,
              },
            ],
          },
        );
      },
    );

    final plans = await service.fetchPlans(
      endpoint: Uri.parse('https://api.example.com/login'),
      authData: 'Bearer plan-token',
    );

    expect(plans, hasLength(1));
    expect(plans.single.id, 7);
    expect(plans.single.name, '蜂窝全球套餐');
    expect(plans.single.tags, ['热门', '专线']);
    expect(plans.single.transferEnableGb, 2000);
    expect(plans.single.speedLimit, 500);
    expect(plans.single.deviceLimit, 5);
    expect(plans.single.prices, {'month_price': 1500, 'year_price': 12000});
    expect(plans.single.sell, isTrue);
    expect(plans.single.renew, isTrue);
    expect(plans.single.isSoldOut, isFalse);
  });

  test('loads the current plan by id from a single-plan response', () async {
    final service = XboardAuthService(
      plansRequester: (endpoint, authData) async {
        expect(
          endpoint,
          Uri.parse('https://api.example.com/api/v1/user/plan/fetch?id=81'),
        );
        expect(authData, 'Bearer current-plan-token');
        return const XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': {
              'id': 81,
              'name': '当前订阅套餐',
              'month_price': 2000,
              'reset_price': 500,
              'renew': 1,
            },
          },
        );
      },
    );

    final plans = await service.fetchPlans(
      endpoint: Uri.parse('https://api.example.com/login'),
      authData: 'Bearer current-plan-token',
      planId: 81,
    );

    expect(plans, hasLength(1));
    expect(plans.single.id, 81);
    expect(plans.single.name, '当前订阅套餐');
    expect(plans.single.prices, {'month_price': 2000, 'reset_price': 500});
    expect(plans.single.renew, isTrue);
  });

  test('uses XBoard payment methods, order, checkout, and status APIs', () async {
    final service = XboardAuthService(
      paymentMethodsRequester: (endpoint, authData) async {
        expect(
          endpoint,
          Uri.parse(
            'https://api.example.com/api/v1/user/order/getPaymentMethod',
          ),
        );
        expect(authData, 'Bearer payment-token');
        return const XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': [
              {
                'id': 3,
                'name': '支付宝',
                'payment': 'AlipayF2F',
                'icon': null,
                'handling_fee_fixed': 50,
                'handling_fee_percent': '1.5',
              },
            ],
          },
        );
      },
      orderSaveRequester: (endpoint, authData, planId, period) async {
        expect(
          endpoint,
          Uri.parse('https://api.example.com/api/v1/user/order/save'),
        );
        expect(authData, 'Bearer payment-token');
        expect(planId, 7);
        expect(period, 'month_price');
        return const XboardLoginResponse(
          statusCode: 200,
          data: {'data': '202608290001'},
        );
      },
      orderCheckoutRequester: (endpoint, authData, tradeNo, methodId) async {
        expect(
          endpoint,
          Uri.parse('https://api.example.com/api/v1/user/order/checkout'),
        );
        expect(authData, 'Bearer payment-token');
        expect(tradeNo, '202608290001');
        expect(methodId, 3);
        return const XboardLoginResponse(
          statusCode: 200,
          data: {'type': 1, 'data': 'https://pay.example.com/order/1'},
        );
      },
      orderCheckRequester: (endpoint, authData, tradeNo) async {
        expect(
          endpoint,
          Uri.parse(
            'https://api.example.com/api/v1/user/order/check?trade_no=202608290001',
          ),
        );
        expect(authData, 'Bearer payment-token');
        expect(tradeNo, '202608290001');
        return const XboardLoginResponse(statusCode: 200, data: {'data': 3});
      },
    );
    final endpoint = Uri.parse('https://api.example.com/login');

    final methods = await service.fetchPaymentMethods(
      endpoint: endpoint,
      authData: 'Bearer payment-token',
    );
    final tradeNo = await service.createOrder(
      endpoint: endpoint,
      authData: 'Bearer payment-token',
      planId: 7,
      period: 'month_price',
    );
    final checkout = await service.checkoutOrder(
      endpoint: endpoint,
      authData: 'Bearer payment-token',
      tradeNo: tradeNo,
      methodId: methods.single.id,
    );
    final status = await service.checkOrder(
      endpoint: endpoint,
      authData: 'Bearer payment-token',
      tradeNo: tradeNo,
    );

    expect(methods.single.name, '支付宝');
    expect(methods.single.handlingFeeFixed, 50);
    expect(methods.single.handlingFeePercent, 1.5);
    expect(tradeNo, '202608290001');
    expect(checkout.type, 1);
    expect(checkout.paymentPayload, 'https://pay.example.com/order/1');
    expect(status, 3);
  });

  test('uses XBoard account profile and security APIs', () async {
    var preferencesUpdated = false;
    var passwordChanged = false;
    final service = XboardAuthService(
      userInfoRequester: (endpoint, authData) async {
        expect(endpoint, Uri.parse('https://api.example.com/api/v1/user/info'));
        expect(authData, 'Bearer account-token');
        return const XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': {
              'email': 'member@example.com',
              'balance': 1250,
              'commission_balance': 300,
              'remind_expire': 1,
              'remind_traffic': 0,
              'telegram_id': '123456',
              'plan_id': 7,
              'expired_at': 1788192000,
              'avatar_url': 'https://cdn.example.com/avatar.png',
            },
          },
        );
      },
      userUpdateRequester:
          (endpoint, authData, remindExpire, remindTraffic) async {
            expect(
              endpoint,
              Uri.parse('https://api.example.com/api/v1/user/update'),
            );
            expect(remindExpire, isFalse);
            expect(remindTraffic, isTrue);
            preferencesUpdated = true;
            return const XboardLoginResponse(
              statusCode: 200,
              data: {'data': true},
            );
          },
      changePasswordRequester:
          (endpoint, authData, oldPassword, newPassword) async {
            expect(
              endpoint,
              Uri.parse('https://api.example.com/api/v1/user/changePassword'),
            );
            expect(oldPassword, 'old-secret');
            expect(newPassword, 'new-secret');
            passwordChanged = true;
            return const XboardLoginResponse(
              statusCode: 200,
              data: {'data': true},
            );
          },
      resetSecurityRequester: (endpoint, authData) async {
        expect(
          endpoint,
          Uri.parse('https://api.example.com/api/v1/user/resetSecurity'),
        );
        return const XboardLoginResponse(
          statusCode: 200,
          data: {'data': 'https://api.example.com/subscribe/new-token'},
        );
      },
    );
    final endpoint = Uri.parse('https://api.example.com/login');

    final info = await service.fetchUserInfo(
      endpoint: endpoint,
      authData: 'Bearer account-token',
    );
    await service.updateUserPreferences(
      endpoint: endpoint,
      authData: 'Bearer account-token',
      remindExpire: false,
      remindTraffic: true,
    );
    await service.changePassword(
      endpoint: endpoint,
      authData: 'Bearer account-token',
      oldPassword: 'old-secret',
      newPassword: 'new-secret',
    );
    final subscribeUrl = await service.resetSecurity(
      endpoint: endpoint,
      authData: 'Bearer account-token',
    );

    expect(info.email, 'member@example.com');
    expect(info.balance, 1250);
    expect(info.balanceAmount, 12.5);
    expect(info.remindExpire, isTrue);
    expect(info.remindTraffic, isFalse);
    expect(info.telegramId, '123456');
    expect(preferencesUpdated, isTrue);
    expect(passwordChanged, isTrue);
    expect(
      subscribeUrl,
      Uri.parse('https://api.example.com/subscribe/new-token'),
    );
  });

  test('loads and normalizes the XBoard guest registration config', () async {
    final calls = <Uri>[];
    final service = XboardAuthService(
      endpointLoader: () async => [
        Uri.parse('https://one.example.com'),
        Uri.parse('https://two.example.com'),
      ],
      guestConfigRequester: (endpoint) async {
        calls.add(endpoint);
        if (endpoint.host == 'one.example.com') {
          return const XboardLoginResponse(statusCode: 503);
        }
        return const XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': {
              'is_email_verify': 1,
              'is_invite_force': '1',
              'email_whitelist_suffix': [
                'qq.com',
                'gmail.com',
                'vip.163.com',
                'icloud.com',
              ],
              'app_description': '保留完整配置',
            },
          },
        );
      },
    );

    final config = await service.loadGuestConfig();

    expect(calls, [
      Uri.parse('https://one.example.com/api/v1/guest/comm/config'),
      Uri.parse('https://two.example.com/api/v1/guest/comm/config'),
    ]);
    expect(config.isEmailVerify, isTrue);
    expect(config.isInviteForce, isTrue);
    expect(config.emailWhitelistSuffix, [
      'qq.com',
      'gmail.com',
      'vip.163.com',
      'icloud.com',
    ]);
    expect(config.emailDomains, [
      '@qq.com',
      '@gmail.com',
      '@vip.163.com',
      '@icloud.com',
    ]);
    expect(config.rawData['app_description'], '保留完整配置');
    expect(service.currentGuestConfig, same(config));
  });

  test('requires email suffixes to come from the XBoard array', () async {
    final service = XboardAuthService(
      endpointLoader: () async => [Uri.parse('https://api.example.com')],
      guestConfigRequester: (endpoint) async => const XboardLoginResponse(
        statusCode: 200,
        data: {
          'data': {
            'is_email_verify': 0,
            'is_invite_force': 0,
            'email_whitelist_suffix': 0,
          },
        },
      ),
    );

    await expectLater(
      service.loadGuestConfig(),
      throwsA(
        isA<XboardAuthException>().having(
          (error) => error.failure,
          'failure',
          XboardAuthFailure.invalidResponse,
        ),
      ),
    );
  });

  test(
    'uses the XBoard login and authenticated subscription contracts',
    () async {
      final adapter = _RecordingAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = XboardAuthService(
        dio: dio,
        endpointLoader: () async => [
          Uri.parse('https://api.example.com:15699'),
        ],
      );

      await service.login(email: 'user@example.com', password: 'secret');
      await service.sendEmailVerification(email: '64567789@qq.com');
      final registration = await service.register(
        email: '64567789@qq.com',
        password: 'secret123',
        emailCode: '123456',
      );

      expect(adapter.requests, hasLength(4));
      final request = adapter.requests.first;
      expect(request.method, 'POST');
      expect(
        request.uri,
        Uri.parse('https://api.example.com:15699/api/v1/passport/auth/login'),
      );
      expect(request.contentType, startsWith('multipart/form-data'));
      expect(request.data, isA<FormData>());
      expect(Map.fromEntries((request.data as FormData).fields), {
        'email': 'user@example.com',
        'password': 'secret',
      });

      final subscribeRequest = adapter.requests[1];
      expect(subscribeRequest.method, 'GET');
      expect(
        subscribeRequest.uri,
        Uri.parse('https://api.example.com:15699/api/v1/user/getSubscribe'),
      );
      expect(subscribeRequest.headers['Authorization'], 'Bearer login-token');

      final emailRequest = adapter.requests[2];
      expect(emailRequest.method, 'POST');
      expect(
        emailRequest.uri,
        Uri.parse(
          'https://api.example.com:15699/api/v1/passport/comm/sendEmailVerify',
        ),
      );
      expect(emailRequest.contentType, startsWith('multipart/form-data'));
      expect(Map.fromEntries((emailRequest.data as FormData).fields), {
        'email': '64567789@qq.com',
        'isForgetPassword': 'false',
      });

      final registrationRequest = adapter.requests.last;
      expect(registrationRequest.method, 'POST');
      expect(
        registrationRequest.uri,
        Uri.parse(
          'https://api.example.com:15699/api/v1/passport/auth/register',
        ),
      );
      expect(
        registrationRequest.contentType,
        startsWith('multipart/form-data'),
      );
      expect(Map.fromEntries((registrationRequest.data as FormData).fields), {
        'email': '64567789@qq.com',
        'password': 'secret123',
        'email_code': '123456',
      });
      expect(registration.authData, 'Bearer registration-token');
    },
  );

  test('uses the XBoard forgot-password contracts', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final service = XboardAuthService(
      dio: dio,
      endpointLoader: () async => [Uri.parse('https://api.example.com:15699')],
    );

    await service.sendEmailVerification(
      email: 'user@example.com',
      isForgetPassword: true,
    );
    await service.resetPassword(
      email: ' user@example.com ',
      password: 'new-secret',
      emailCode: ' 123456 ',
    );

    expect(adapter.requests, hasLength(2));
    final verificationRequest = adapter.requests.first;
    expect(verificationRequest.method, 'POST');
    expect(
      verificationRequest.uri,
      Uri.parse(
        'https://api.example.com:15699/api/v1/passport/comm/sendEmailVerify',
      ),
    );
    expect(Map.fromEntries((verificationRequest.data as FormData).fields), {
      'email': 'user@example.com',
      'isForgetPassword': 'true',
    });

    final resetRequest = adapter.requests.last;
    expect(resetRequest.method, 'POST');
    expect(
      resetRequest.uri,
      Uri.parse('https://api.example.com:15699/api/v1/passport/auth/forget'),
    );
    expect(resetRequest.contentType, startsWith('multipart/form-data'));
    expect(Map.fromEntries((resetRequest.data as FormData).fields), {
      'email': 'user@example.com',
      'password': 'new-secret',
      'email_code': '123456',
    });
  });

  test(
    'forgot-password request fails over to another available host',
    () async {
      final calls = <Uri>[];
      final service = XboardAuthService(
        endpointLoader: () async => [
          Uri.parse('https://one.example.com'),
          Uri.parse('https://two.example.com'),
        ],
        passwordResetRequester: (endpoint, email, password, emailCode) async {
          calls.add(endpoint);
          expect(email, 'user@example.com');
          expect(password, 'new-secret');
          expect(emailCode, '123456');
          return XboardLoginResponse(
            statusCode: endpoint.host == 'one.example.com' ? 503 : 200,
            data: const {'data': true},
          );
        },
      );

      await service.resetPassword(
        email: 'user@example.com',
        password: 'new-secret',
        emailCode: '123456',
      );

      expect(calls, [
        Uri.parse('https://one.example.com/api/v1/passport/auth/forget'),
        Uri.parse('https://two.example.com/api/v1/passport/auth/forget'),
      ]);
    },
  );

  test('forgot-password validation rejection does not retry', () async {
    var calls = 0;
    final service = XboardAuthService(
      endpointLoader: () async => [
        Uri.parse('https://one.example.com'),
        Uri.parse('https://two.example.com'),
      ],
      passwordResetRequester: (endpoint, email, password, emailCode) async {
        calls++;
        return const XboardLoginResponse(
          statusCode: 422,
          data: {'message': '邮箱验证码错误'},
        );
      },
    );

    await expectLater(
      service.resetPassword(
        email: 'user@example.com',
        password: 'new-secret',
        emailCode: 'wrong',
      ),
      throwsA(
        isA<XboardAuthException>()
            .having(
              (error) => error.failure,
              'failure',
              XboardAuthFailure.passwordResetRejected,
            )
            .having((error) => error.message, 'message', '邮箱验证码错误'),
      ),
    );
    expect(calls, 1);
  });

  test('global API preference is tried first and keeps failover', () async {
    final preferenceStore = ApiEndpointPreferenceStore();
    await preferenceStore.save(Uri.parse('https://two.example.com:15699'));
    final healthService = ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      preferenceStore: preferenceStore,
      configLoader: (_) async => {
        'Authentication': 'FengWo',
        'hosts': [
          'https://one.example.com:15699',
          'https://two.example.com:15699',
        ],
      },
      endpointProbe: (_) async => true,
    );
    final calls = <Uri>[];
    final service = XboardAuthService(
      apiHealthService: healthService,
      loginRequester: (endpoint, email, password) async {
        calls.add(endpoint);
        if (endpoint.host == 'two.example.com') {
          return const XboardLoginResponse(statusCode: 503);
        }
        return const XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': {
              'token': 'subscription-token',
              'auth_data': 'Bearer login-token',
              'is_admin': false,
            },
          },
        );
      },
      subscriptionRequester: _successfulSubscriptionRequest,
    );

    final result = await service.login(
      email: 'user@example.com',
      password: 'secret',
    );

    expect(calls, [
      Uri.parse('https://two.example.com:15699/api/v1/passport/auth/login'),
      Uri.parse('https://one.example.com:15699/api/v1/passport/auth/login'),
    ]);
    expect(result.endpoint.host, 'one.example.com');
  });

  test('fails over to the next available host and parses auth data', () async {
    final calls = <Uri>[];
    final service = XboardAuthService(
      endpointLoader: () async => [
        Uri.parse('https://one.example.com:15699'),
        Uri.parse('https://two.example.com:15699'),
      ],
      loginRequester: (endpoint, email, password) async {
        calls.add(endpoint);
        expect(email, 'user@example.com');
        expect(password, 'secret');
        if (endpoint.host == 'one.example.com') {
          return const XboardLoginResponse(
            statusCode: 503,
            data: {'message': 'maintenance'},
          );
        }
        return const XboardLoginResponse(
          statusCode: 200,
          data: {
            'status': 'success',
            'data': {
              'token': 'subscription-token',
              'auth_data': 'Bearer login-token',
              'is_admin': false,
            },
          },
        );
      },
      subscriptionRequester: _successfulSubscriptionRequest,
    );

    final result = await service.login(
      email: 'user@example.com',
      password: 'secret',
    );

    expect(calls, [
      Uri.parse('https://one.example.com:15699/api/v1/passport/auth/login'),
      Uri.parse('https://two.example.com:15699/api/v1/passport/auth/login'),
    ]);
    expect(result.token, 'subscription-token');
    expect(result.authData, 'Bearer login-token');
    expect(result.isAdmin, isFalse);
    expect(
      result.subscribeUrl,
      Uri.parse('https://subscribe.example.com/client/token'),
    );
    expect(result.subscription.plan?.name, '蜂窝标准套餐');
    expect(result.subscription.uploadGb, 1);
    expect(result.subscription.downloadGb, 2);
    expect(result.subscription.usedGb, 3);
    expect(result.subscription.transferEnableGb, 10);
    expect(result.subscription.remainingGb, 7);
    expect(result.subscription.plan?.transferEnableGb, 20);
    expect(result.subscription.isUnlimitedTime, isTrue);
    expect(result.subscription.isMonthlyPlan, isFalse);
    expect(result.subscription.shouldShowNextPlanReset, isFalse);
    expect(result.subscription.rawData['device_limit'], 5);
    expect(result.subscription.plan?.rawData['content'], '完整套餐数据');
    expect(service.currentSession, same(result));
  });

  test('restores a saved session by validating its subscription', () async {
    final subscriptionCalls = <Uri>[];
    final service = XboardAuthService(
      endpointLoader: () async => [Uri.parse('https://backup.example.com')],
      subscriptionRequester: (endpoint, authData) async {
        subscriptionCalls.add(endpoint);
        expect(authData, 'Bearer saved-token');
        return _successfulSubscriptionResponse();
      },
    );

    final result = await service.restoreSession(
      preferredEndpoint: Uri.parse(
        'https://saved.example.com/api/v1/passport/auth/login',
      ),
      token: 'subscription-token',
      authData: 'Bearer saved-token',
    );

    expect(subscriptionCalls, [
      Uri.parse('https://saved.example.com/api/v1/user/getSubscribe'),
    ]);
    expect(result.authData, 'Bearer saved-token');
    expect(result.subscription.plan?.name, '蜂窝标准套餐');
    expect(service.currentSession, same(result));
  });

  test('accepts a subscription response without a legacy URL for V2', () async {
    final service = XboardAuthService(
      subscriptionRequester: (endpoint, authData) async {
        return const XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': {
              'token': '0123456789abcdef0123456789abcdef',
              'u': 0,
              'd': 0,
              'transfer_enable': 1073741824,
            },
          },
        );
      },
    );

    final subscription = await service.fetchSubscription(
      endpoint: Uri.parse('https://api.example.com'),
      authData: 'Bearer saved-token',
    );

    expect(subscription.subscribeUrl, isNull);
    expect(subscription.token, '0123456789abcdef0123456789abcdef');
  });

  test('global API preference overrides the previously saved host', () async {
    final preferenceStore = ApiEndpointPreferenceStore();
    await preferenceStore.save(Uri.parse('https://two.example.com'));
    final subscriptionCalls = <Uri>[];
    final service = XboardAuthService(
      apiHealthService: ApiHealthService(
        configUrl: 'https://config.example.com/app.json',
        preferenceStore: preferenceStore,
        configLoader: (_) async => {
          'Authentication': 'FengWo',
          'hosts': ['https://one.example.com', 'https://two.example.com'],
        },
        endpointProbe: (_) async => true,
      ),
      subscriptionRequester: (endpoint, authData) async {
        subscriptionCalls.add(endpoint);
        return _successfulSubscriptionResponse();
      },
    );

    final result = await service.restoreSession(
      preferredEndpoint: Uri.parse(
        'https://one.example.com/api/v1/passport/auth/login',
      ),
      token: 'subscription-token',
      authData: 'Bearer saved-token',
    );

    expect(subscriptionCalls.single.host, 'two.example.com');
    expect(result.endpoint.host, 'two.example.com');
  });

  test('fails over when an unavailable host returns a non-JSON page', () async {
    var calls = 0;
    final service = XboardAuthService(
      endpointLoader: () async => [
        Uri.parse('https://one.example.com'),
        Uri.parse('https://two.example.com'),
      ],
      loginRequester: (endpoint, email, password) async {
        calls++;
        if (calls == 1) {
          return const XboardLoginResponse(
            statusCode: 503,
            data: '<html>maintenance</html>',
          );
        }
        return const XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': {
              'token': 'subscription-token',
              'auth_data': 'Bearer login-token',
              'is_admin': 0,
            },
          },
        );
      },
      subscriptionRequester: _successfulSubscriptionRequest,
    );

    final result = await service.login(
      email: 'user@example.com',
      password: 'secret',
    );

    expect(calls, 2);
    expect(result.authData, 'Bearer login-token');
  });

  test(
    'subscription request fails over and preserves a finite expiry',
    () async {
      final subscriptionCalls = <Uri>[];
      final service = XboardAuthService(
        endpointLoader: () async => [
          Uri.parse('https://one.example.com'),
          Uri.parse('https://two.example.com'),
        ],
        loginRequester: _successfulLoginRequest,
        subscriptionRequester: (endpoint, authData) async {
          subscriptionCalls.add(endpoint);
          if (endpoint.host == 'one.example.com') {
            return const XboardLoginResponse(
              statusCode: 503,
              data: '<html>maintenance</html>',
            );
          }
          return _successfulSubscriptionResponse(expiredAt: 1800000000);
        },
      );

      final result = await service.login(
        email: 'user@example.com',
        password: 'secret',
      );

      expect(subscriptionCalls, [
        Uri.parse('https://one.example.com/api/v1/user/getSubscribe'),
        Uri.parse('https://two.example.com/api/v1/user/getSubscribe'),
      ]);
      expect(result.subscription.isUnlimitedTime, isFalse);
      expect(result.subscription.isMonthlyPlan, isTrue);
      expect(result.subscription.expiredAtEpochSeconds, 1800000000);
      expect(result.subscription.expiresAt, isNotNull);
      expect(result.subscription.shouldShowNextPlanReset, isTrue);
    },
  );

  test(
    'uses only the current subscription expired_at field for plan type',
    () async {
      final service = XboardAuthService(
        endpointLoader: () async => [Uri.parse('https://api.example.com')],
        loginRequester: _successfulLoginRequest,
        subscriptionRequester: (endpoint, authData) async =>
            const XboardLoginResponse(
              statusCode: 200,
              data: {
                'data': {
                  'plan_id': 7,
                  'expire_date': '2027-08-29T00:00:00Z',
                  'expired_at': 1819497600,
                  'next_reset_at': 1800000000,
                  'subscribe_url': 'https://subscribe.example.com/client/token',
                  'plan': {'id': 7, 'name': '任意名称'},
                },
              },
            ),
      );

      final result = await service.login(
        email: 'user@example.com',
        password: 'secret',
      );

      expect(result.subscription.isMonthlyPlan, isTrue);
      expect(result.subscription.expiredAtEpochSeconds, 1819497600);
      expect(result.subscription.shouldShowNextPlanReset, isTrue);
    },
  );

  test('ignores expire_date when expired_at is empty', () async {
    final service = XboardAuthService(
      endpointLoader: () async => [Uri.parse('https://api.example.com')],
      loginRequester: _successfulLoginRequest,
      subscriptionRequester: (endpoint, authData) async =>
          const XboardLoginResponse(
            statusCode: 200,
            data: {
              'data': {
                'plan_id': 7,
                'expire_date': '2027-08-29T00:00:00Z',
                'expired_at': 0,
                'next_reset_at': 1800000000,
                'subscribe_url': 'https://subscribe.example.com/client/token',
                'plan': {'id': 7, 'name': '包月字样也不参与判断'},
              },
            },
          ),
    );

    final result = await service.login(
      email: 'user@example.com',
      password: 'secret',
    );

    expect(result.subscription.isMonthlyPlan, isFalse);
    expect(result.subscription.isUnlimitedTime, isTrue);
    expect(result.subscription.shouldShowNextPlanReset, isFalse);
  });

  test('authentication rejection does not retry another host', () async {
    var calls = 0;
    final service = XboardAuthService(
      endpointLoader: () async => [
        Uri.parse('https://one.example.com'),
        Uri.parse('https://two.example.com'),
      ],
      loginRequester: (endpoint, email, password) async {
        calls++;
        return const XboardLoginResponse(
          statusCode: 400,
          data: {'status': 'fail', 'message': 'Incorrect email or password'},
        );
      },
    );

    await expectLater(
      service.login(email: 'user@example.com', password: 'wrong'),
      throwsA(
        isA<XboardAuthException>()
            .having(
              (error) => error.failure,
              'failure',
              XboardAuthFailure.authenticationRejected,
            )
            .having(
              (error) => error.message,
              'message',
              'Incorrect email or password',
            ),
      ),
    );
    expect(calls, 1);
  });

  test('empty available host list returns a clear error', () async {
    final service = XboardAuthService(endpointLoader: () async => const []);

    await expectLater(
      service.login(email: 'user@example.com', password: 'secret'),
      throwsA(
        isA<XboardAuthException>().having(
          (error) => error.failure,
          'failure',
          XboardAuthFailure.noAvailableHost,
        ),
      ),
    );
  });

  test(
    'secure login bypasses the legacy login and subscription APIs',
    () async {
      var legacyRequests = 0;
      final endpoint = Uri.parse('https://api.example.com');
      final service = XboardAuthService(
        endpointLoader: () async => [endpoint],
        subscriptionV2Client: _FakeSubscriptionV2Client(
          login: SubscriptionV2Login(
            endpoint: endpoint,
            token: 'secure-token',
            authData: 'Bearer secure-auth',
            isAdmin: false,
            subscription: _secureSummary,
            rawData: const {'protocol': 'v2'},
          ),
        ),
        loginRequester: (endpoint, email, password) async {
          legacyRequests++;
          return _successfulLoginRequest(endpoint, email, password);
        },
        subscriptionRequester: (endpoint, authData) async {
          legacyRequests++;
          return _successfulSubscriptionResponse();
        },
      );

      final session = await service.login(
        email: 'gray@example.com',
        password: 'secret',
        appVersion: '1.9.0',
      );

      expect(session.secureSubscription, isTrue);
      expect(session.token, 'secure-token');
      expect(session.subscribeUrl, isNull);
      expect(session.subscription.plan?.name, '安全套餐');
      expect(legacyRequests, 0);
    },
  );

  test('secure gateway failures never downgrade to legacy login', () async {
    var legacyRequests = 0;
    final service = XboardAuthService(
      endpointLoader: () async => [Uri.parse('https://api.example.com')],
      subscriptionV2Client: _FakeSubscriptionV2Client(
        loginError: const SubscriptionV2Exception('gateway_unavailable'),
      ),
      loginRequester: (endpoint, email, password) async {
        legacyRequests++;
        return _successfulLoginRequest(endpoint, email, password);
      },
    );

    await expectLater(
      service.login(email: 'gray@example.com', password: 'secret'),
      throwsA(
        isA<XboardAuthException>().having(
          (error) => error.failure,
          'failure',
          XboardAuthFailure.unavailable,
        ),
      ),
    );
    expect(legacyRequests, 0);
  });

  test(
    'signed gray-list rejection is the only secure login downgrade',
    () async {
      var legacyRequests = 0;
      final service = XboardAuthService(
        endpointLoader: () async => [Uri.parse('https://api.example.com')],
        subscriptionV2Client: _FakeSubscriptionV2Client(),
        loginRequester: (endpoint, email, password) async {
          legacyRequests++;
          return _successfulLoginRequest(endpoint, email, password);
        },
        subscriptionRequester: (endpoint, authData) async {
          legacyRequests++;
          return _successfulSubscriptionResponse();
        },
      );

      final session = await service.login(
        email: 'public@example.com',
        password: 'secret',
      );

      expect(session.secureSubscription, isFalse);
      expect(legacyRequests, 2);
    },
  );

  test(
    'secure session restore fetches only the device-signed summary',
    () async {
      var legacyRequests = 0;
      final service = XboardAuthService(
        endpointLoader: () async => [Uri.parse('https://api.example.com')],
        subscriptionV2Client: _FakeSubscriptionV2Client(
          summary: _secureSummary,
        ),
        subscriptionRequester: (endpoint, authData) async {
          legacyRequests++;
          return _successfulSubscriptionResponse();
        },
      );

      final session = await service.restoreSession(
        preferredEndpoint: Uri.parse('https://api.example.com'),
        token: 'secure-token',
        authData: 'Bearer secure-auth',
        secureSubscription: true,
      );

      expect(session.secureSubscription, isTrue);
      expect(session.subscription.email, 'gray@example.com');
      expect(legacyRequests, 0);
    },
  );

  test('successful response must contain token and auth_data', () async {
    final service = XboardAuthService(
      endpointLoader: () async => [Uri.parse('https://api.example.com')],
      loginRequester: (endpoint, email, password) async {
        return const XboardLoginResponse(
          statusCode: 200,
          data: {
            'status': 'success',
            'data': {'token': 'only-one-token'},
          },
        );
      },
    );

    await expectLater(
      service.login(email: 'user@example.com', password: 'secret'),
      throwsA(
        isA<XboardAuthException>().having(
          (error) => error.failure,
          'failure',
          XboardAuthFailure.invalidResponse,
        ),
      ),
    );
  });
}

const _secureSummary = <String, Object?>{
  'plan_id': 7,
  'email': 'gray@example.com',
  'expired_at': null,
  'u': 1,
  'd': 2,
  'transfer_enable': 100,
  'device_limit': 3,
  'speed_limit': null,
  'next_reset_at': null,
  'reset_day': 0,
  'plan': {'id': 7, 'name': '安全套餐', 'transfer_enable': 100},
};

class _FakeSubscriptionV2Client extends SubscriptionV2Client {
  _FakeSubscriptionV2Client({this.login, this.loginError, this.summary});

  final SubscriptionV2Login? login;
  final SubscriptionV2Exception? loginError;
  final Map<String, Object?>? summary;

  @override
  Future<SubscriptionV2Login?> secureLogin({
    required Uri endpoint,
    required String email,
    required String password,
    required String appVersion,
    String? platform,
  }) async {
    if (loginError case final error?) throw error;
    return login;
  }

  @override
  Future<Map<String, Object?>> fetchSummary({
    required Uri endpoint,
    required String userToken,
  }) async {
    final value = summary;
    if (value == null) {
      throw const SubscriptionV2Exception('device_not_registered');
    }
    return value;
  }
}

class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final response = options.uri.path == xboardLoginPath
        ? '''{"data":{"token":"subscription-token","auth_data":"Bearer login-token","is_admin":false}}'''
        : options.uri.path == xboardSubscribePath
        ? '''{"data":{"subscribe_url":"https://subscribe.example.com/client/token","expired_at":0,"u":1073741824,"d":2147483648,"transfer_enable":10737418240,"plan":{"name":"蜂窝标准套餐","transfer_enable":21474836480}}}'''
        : options.uri.path == xboardRegisterPath
        ? '''{"data":{"token":"new-user-token","auth_data":"Bearer registration-token","is_admin":false}}'''
        : '''{"data":true}''';
    return ResponseBody.fromString(response, 200, headers: _jsonHeaders);
  }

  @override
  void close({bool force = false}) {}
}

const _jsonHeaders = {
  Headers.contentTypeHeader: [Headers.jsonContentType],
};

Future<XboardLoginResponse> _successfulLoginRequest(
  Uri endpoint,
  String email,
  String password,
) async {
  return const XboardLoginResponse(
    statusCode: 200,
    data: {
      'data': {
        'token': 'subscription-token',
        'auth_data': 'Bearer login-token',
        'is_admin': false,
      },
    },
  );
}

Future<XboardLoginResponse> _successfulSubscriptionRequest(
  Uri endpoint,
  String authData,
) async {
  expect(authData, 'Bearer login-token');
  return _successfulSubscriptionResponse();
}

XboardLoginResponse _successfulSubscriptionResponse({int expiredAt = 0}) {
  return XboardLoginResponse(
    statusCode: 200,
    data: {
      'data': {
        'plan_id': 7,
        'token': 'subscription-token',
        'expired_at': expiredAt,
        'u': bytesPerGigabyte,
        'd': bytesPerGigabyte * 2,
        'transfer_enable': bytesPerGigabyte * 10,
        'email': 'user@example.com',
        'uuid': 'user-uuid',
        'device_limit': 5,
        'speed_limit': 100,
        'next_reset_at': 1800000000,
        'reset_day': 12,
        'subscribe_url': 'https://subscribe.example.com/client/token',
        'plan': {
          'id': 7,
          'name': '蜂窝标准套餐',
          'transfer_enable': bytesPerGigabyte * 20,
          'content': '完整套餐数据',
        },
      },
    },
  );
}
