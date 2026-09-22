import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 西安电子科技大学统一身份认证（金智 authserver）的登录态管理。
///
/// 只保存登录成功后认证服务器下发的 Cookie，不保存账号密码。
class AuthService extends ChangeNotifier {
  AuthService._();

  /// 全局单例，登录态在整个 App 内共享。
  static final AuthService instance = AuthService._();

  /// 统一身份认证站点。
  static const String authServerOrigin = 'https://ids.xidian.edu.cn';

  /// 统一身份认证的主机名，用来判断当前页面是不是登录页。
  static const String authServerHost = 'ids.xidian.edu.cn';

  /// 抓教务数据时用的 UA，伪装成桌面浏览器。
  ///
  /// ehall 里那几个应用（培养方案、课表）在手机 UA 下会走移动端分支，接口直接
  /// 报「调用接口异常」；桌面浏览器访问才正常，TP2MD 那边也是这么跑的。
  ///
  /// 登录页不换这个 UA——手机上桌面版登录页很难操作。
  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// 登录成功后要跳转的业务系统，这里用一站式服务大厅。
  static const String serviceUrl = 'https://ehall.xidian.edu.cn/';

  /// CAS 的登录凭证 Cookie 名。
  ///
  /// 只有认证通过后认证服务器才会下发它，所以它是判断会话是否真正建立的
  /// 依据；登录页自身也会写 Cookie，不能用「有没有 Cookie」来判断。
  static const String castgcName = 'CASTGC';

  /// 登录页埋点写的 Cookie 名，值是用户输入的账号（学号/工号）。
  ///
  /// 培养方案这类数据要和账号绑定，就靠它区分是谁的数据；万一页面结构变了
  /// 埋点失败，退化用 [sessionKey] 区分。
  static const String accountCookieName = 'xdh_username';

  /// 往登录页注入的脚本：把用户名输入框的内容写进 [accountCookieName]。
  ///
  /// 认证服务器跳走之后页面 DOM 就没了，但 Cookie 还在，认证成功后从
  /// CookieManager 里把这个 Cookie 捞回来就能拿到账号名。
  static const String usernameHookJs =
      '''
(function() {
  var el = document.getElementById('username') ||
           document.getElementById('un') ||
           document.querySelector('input[name="username"]') ||
           document.querySelector('input[name="un"]');
  if (!el || el.dataset.xdhHooked === '1') { return; }
  el.dataset.xdhHooked = '1';
  var save = function() {
    var v = (el.value || '').trim();
    if (!v) { return; }
    document.cookie = '$accountCookieName=' + encodeURIComponent(v) +
        ';path=/;max-age=7776000';
  };
  el.addEventListener('input', save);
  el.addEventListener('change', save);
  el.addEventListener('blur', save);
  var form = el.closest('form');
  if (form) {
    form.addEventListener('submit', save);
    var btn = form.querySelector('button[type="submit"]') ||
              form.querySelector('button');
    if (btn) { btn.addEventListener('click', save); }
  }
})();
''';

  /// 需要采集 Cookie 的站点。
  ///
  /// Cookie 是按路径匹配的，查询用的 URL 必须落在 Cookie 自己的路径下，
  /// 否则拿不回来——[castgcName] 就挂在 authserver 这个路径下。
  static const List<String> cookieOrigins = <String>[
    authServerOrigin,
    '$authServerOrigin/authserver',
    'https://ehall.xidian.edu.cn',
  ];

  /// CAS 登录地址。
  ///
  /// 带上 service 参数后，认证通过时认证服务器会 302 到业务系统并附上
  /// `ticket=ST-...`，这个票据是判断登录成功最可靠的信号。
  static String get loginUrl {
    final String service = Uri.encodeComponent(serviceUrl);
    return '$authServerOrigin/authserver/login'
        '?service=$service&type=userNameLogin&login_type=generalLogin';
  }

  static const String _cookieKey = 'xidian_auth_cookies';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Map<String, String> _cookies = <String, String>{};
  bool _restored = false;

  /// 当前账号（学号/工号），来自登录页埋点的 Cookie，没抓到就是 null。
  String? _account;

  /// 当前登录会话的指纹（CASTGC 的哈希），账号名拿不到时用来区分登录。
  String? _sessionKey;

  /// 是否处于登录状态。
  bool get isLoggedIn => _cookies.containsKey(castgcName);

  /// 当前账号（学号/工号），可能为 null（登录页埋点没生效时）。
  String? get account => _account;

  /// 当前登录会话的指纹，同一份凭证恢复后保持不变。
  String? get sessionKey => _sessionKey;

  /// 从 Cookie 里提取账号标识。
  void _updateIdentity(Map<String, String> cookies) {
    final String? castgc = cookies[castgcName];
    _sessionKey = castgc == null ? null : _fingerprint(castgc);

    final String? accountCookie = cookies[accountCookieName];
    if (accountCookie == null || accountCookie.isEmpty) {
      // 没抓到新账号名就不能沿用旧值，否则换号后会串数据
      _account = null;
      return;
    }
    try {
      final String decoded = Uri.decodeComponent(accountCookie);
      _account = decoded.isEmpty ? null : decoded;
    } on ArgumentError {
      _account = accountCookie;
    }
  }

  /// FNV-1a 32 位指纹，只是用来区分不同的登录会话，碰撞概率可以忽略。
  static String _fingerprint(String value) {
    int hash = 0x811C9DC5;
    for (int i = 0; i < value.length; i++) {
      hash ^= value.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// 后续请求教务数据时使用的 Cookie 请求头。
  String get cookieHeader => _cookies.entries
      .map((MapEntry<String, String> entry) => '${entry.key}=${entry.value}')
      .join('; ');

  /// 从本地恢复上次的登录态，App 启动时调用一次。
  Future<void> restore() async {
    if (_restored) {
      return;
    }
    final String? raw = await _storage.read(key: _cookieKey);
    if (raw != null && raw.isNotEmpty) {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) {
        _cookies = decoded.map(
          (Object? key, Object? value) =>
              MapEntry<String, String>('$key', '$value'),
        );
      }
    }
    _restored = true;
    _updateIdentity(_cookies);
    notifyListeners();
  }

  /// 采集 WebView 里的 Cookie，建立本地会话并持久化。
  ///
  /// [verifiedByTicket] 表示调用方已经从跳转 URL 里确认过认证通过，此时只要
  /// 采到 Cookie 就算成功；为 false 时要求必须拿到 [castgcName]，避免把登录
  /// 页自身的 Cookie 误判成登录成功。
  ///
  /// 返回本地会话是否已建立。
  Future<bool> captureSession({required bool verifiedByTicket}) async {
    final Map<String, String> collected = <String, String>{};
    for (final String origin in cookieOrigins) {
      final List<Cookie> cookies = await CookieManager.instance().getCookies(
        url: WebUri(origin),
      );
      for (final Cookie cookie in cookies) {
        final String? value = cookie.value?.toString();
        if (value != null && value.isNotEmpty) {
          collected[cookie.name] = value;
        }
      }
    }

    debugPrint('[登录] verifiedByTicket=$verifiedByTicket 采到: ${collected.keys.join(', ')}');

    if (collected.isEmpty) {
      return false;
    }
    if (!verifiedByTicket && !collected.containsKey(castgcName)) {
      return false;
    }

    _cookies = collected;
    _updateIdentity(collected);
    await _storage.write(key: _cookieKey, value: jsonEncode(collected));
    notifyListeners();
    return true;
  }

  /// 退出登录：清掉本地凭证以及 WebView 里的 Cookie。
  Future<void> logout() async {
    _cookies = <String, String>{};
    _account = null;
    _sessionKey = null;
    await _storage.delete(key: _cookieKey);
    await CookieManager.instance().deleteAllCookies();
    notifyListeners();
  }
}
