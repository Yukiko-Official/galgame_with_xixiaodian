import 'dart:convert';

/// 课表抓取用的注入脚本。
///
/// 这些接口都挂在一站式服务大厅（ehall.xidian.edu.cn）下面，所以在服务大厅
/// 的页面里发同源请求时，Cookie 会由浏览器自动带上，不用自己拼鉴权头。
///
/// 接口地址和字段名参考了 XDyou（github.com/BenderBlog/traintime_pda）。
class TimetableScripts {
  TimetableScripts._();

  /// 服务大厅域名，和 [AuthService] 里保存 Cookie 的域一致。
  static const String origin = 'https://ehall.xidian.edu.cn';

  /// 课表应用入口。先进这个页面，把 wdkb 应用的会话建立起来再调接口。
  static const String appUrl = '$origin/appShow?appId=4770397878132218';

  /// 公共的 POST 助手，返回响应原文。
  ///
  /// 这里特意用**同步** XHR：flutter_inappwebview 的 evaluateJavascript 不会等
  /// Promise，用 await fetch 的话拿回来的是个空对象。同步调用会卡一下主线程，
  /// 但抓取的时候无所谓。
  static const String _helpers = r'''
window.__ttPost = function(url, data) {
  var parts = [];
  for (var key in data) {
    var value = data[key];
    if (value === null || value === undefined) { continue; }
    parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(value));
  }
  var xhr = new XMLHttpRequest();
  xhr.open('POST', url, false);
  xhr.setRequestHeader(
    'Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
  xhr.withCredentials = true;
  xhr.send(parts.join('&'));
  return xhr.responseText;
};
''';

  /// 当前学期代码，形如 `2025-2026-1`；拿不到返回空串。
  static String get currentSemester => '''
$_helpers
(function() {
  try {
    var r = JSON.parse(window.__ttPost(
      '$origin/jwapp/sys/wdkb/modules/jshkcb/dqxnxq.do', {}));
    var rows = r && r.datas && r.datas.dqxnxq && r.datas.dqxnxq.rows;
    if (rows && rows.length > 0) { return String(rows[0].DM || ''); }
  } catch (e) {}
  return '';
})()
''';

  /// 诊断用：直接打一次当前学期接口，把状态码和响应原文带回来。
  static String get probeSemester => '''
$_helpers
(function() {
  var out = { url: location.href };
  try {
    var xhr = new XMLHttpRequest();
    xhr.open(
      'POST', '$origin/jwapp/sys/wdkb/modules/jshkcb/dqxnxq.do', false);
    xhr.setRequestHeader(
      'Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
    xhr.withCredentials = true;
    xhr.send('');
    out.status = xhr.status;
    out.body = String(xhr.responseText || '').slice(0, 300);
  } catch (e) {
    out.error = String(e);
  }
  return JSON.stringify(out);
})()
''';

  /// 学期第一周的起始日期；拿不到返回空串。
  static String termStart(String semesterCode) {
    final List<String> seg = semesterCode.split('-');
    final String year = seg.length >= 2 ? '${seg[0]}-${seg[1]}' : semesterCode;
    final String term = seg.length >= 3 ? seg[2] : '';
    return '''
$_helpers
(function() {
  try {
    var r = JSON.parse(window.__ttPost(
      '$origin/jwapp/sys/wdkb/modules/jshkcb/cxjcs.do',
      {XN: ${jsonEncode(year)}, XQ: ${jsonEncode(term)}}));
    var rows = r && r.datas && r.datas.cxjcs && r.datas.cxjcs.rows;
    if (rows && rows.length > 0) { return String(rows[0].XQKSRQ || ''); }
  } catch (e) {}
  return '';
})()
''';
  }

  /// 课表主体。返回 `{ok, rows}`，`unpublished` 表示这学期课表还没发布。
  static String classTable(String semesterCode, String account) => '''
$_helpers
(function() {
  try {
    var r = JSON.parse(window.__ttPost(
      '$origin/jwapp/sys/wdkb/modules/xskcb/xskcb.do',
      {XNXQDM: ${jsonEncode(semesterCode)}, XH: ${jsonEncode(account)}}));
    var data = r && r.datas && r.datas.xskcb;
    if (!data) {
      return JSON.stringify({ok: false, error: '课表接口没有返回数据'});
    }
    var extra = data.extParams || {};
    var msg = extra.msg ? String(extra.msg) : '';
    if (String(extra.code) !== '1') {
      return JSON.stringify({
        ok: false,
        error: msg || '课表获取失败',
        unpublished: msg.indexOf('未发布') >= 0
      });
    }
    return JSON.stringify({ok: true, rows: data.rows || []});
  } catch (e) {
    return JSON.stringify({ok: false, error: String(e)});
  }
})()
''';

  /// 没排进课表的课程。拿不到就当作空，不影响主流程。
  static String notArranged(String semesterCode, String account) => '''
$_helpers
(function() {
  try {
    var r = JSON.parse(window.__ttPost(
      '$origin/jwapp/sys/wdkb/modules/xskcb/cxxsllsywpk.do',
      {XNXQDM: ${jsonEncode(semesterCode)}, XH: ${jsonEncode(account)}}));
    var data = r && r.datas && r.datas.cxxsllsywpk;
    return JSON.stringify({ok: true, rows: (data && data.rows) || []});
  } catch (e) {
    return JSON.stringify({ok: true, rows: []});
  }
})()
''';
}
