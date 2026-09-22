import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/auth_service.dart';

/// 内嵌浏览器登录页。
///
/// 学校在统一身份认证上启用了滑块验证码，没法直接调接口登录，所以这里把真实的
/// 认证页面放进 WebView，由用户自己完成滑块和账号密码输入，我们只负责在认证
/// 通过后把 Cookie 取回来。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  /// CAS 认证通过后签发的票据标记，URL 里出现它就说明认证已经过了。
  static const String _ticketMarker = 'ticket=ST-';

  /// 认证通过后会跳回的业务系统。
  ///
  /// 实测跳转有时会直接在 WebView 里走完，中间带 ticket 的那一跳不一定回
  /// 调我们的回调，所以落在业务系统的页面上也算认证通过。
  static const String _serviceHost = 'ehall.xidian.edu.cn';

  double _progress = 0;
  bool _busy = false;
  bool _finished = false;

  /// 从跳转 URL 判断认证是否已经完成。
  Future<void> _checkUrl(WebUri? url) async {
    if (url == null || _busy || _finished) {
      return;
    }
    debugPrint('[登录] 当前页面: $url');
    if (url.toString().contains(_ticketMarker) || url.host == _serviceHost) {
      await _finish(verifiedByTicket: true);
    }
  }

  /// 采集登录凭证。
  ///
  /// 自动检测没触发时，也可以由用户点「我已完成登录」手动触发，那时候只能靠
  /// 是否拿到 CAS 登录凭证来判断。
  Future<void> _finish({required bool verifiedByTicket}) async {
    if (_busy || _finished) {
      return;
    }
    setState(() => _busy = true);

    final bool success = await AuthService.instance.captureSession(
      verifiedByTicket: verifiedByTicket,
    );
    if (!mounted) {
      return;
    }

    if (success) {
      setState(() {
        _busy = false;
        _finished = true;
      });
      Navigator.of(context).pop(true);
      return;
    }

    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('还没检测到登录成功，请先在上方页面完成登录')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录教务系统'),
        bottom: _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress),
              )
            : null,
        actions: <Widget>[
          TextButton(
            onPressed: _busy ? null : () => _finish(verifiedByTicket: false),
            child: const Text('我已完成登录'),
          ),
        ],
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(AuthService.loginUrl)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          databaseEnabled: true,
          thirdPartyCookiesEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
        ),
        onProgressChanged: (InAppWebViewController controller, int progress) {
          setState(() => _progress = progress / 100);
        },
        onLoadStop: (InAppWebViewController controller, WebUri? url) {
          // 在认证服务器的登录页上埋点，把用户名记进 Cookie，登录成功后
          // 采集会话时顺带就能知道是谁登的
          if (url != null &&
              url.host == AuthService.authServerHost &&
              url.path.contains('login')) {
            controller.evaluateJavascript(source: AuthService.usernameHookJs);
          }
          _checkUrl(url);
        },
        onUpdateVisitedHistory:
            (InAppWebViewController controller, WebUri? url, bool? isReload) =>
                _checkUrl(url),
        onReceivedError:
            (
              InAppWebViewController controller,
              WebResourceRequest request,
              WebResourceError error,
            ) {
              if (request.isForMainFrame ?? false) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('页面加载失败：${error.description}')),
                );
              }
            },
      ),
    );
  }
}
