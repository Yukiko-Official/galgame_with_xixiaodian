import 'dart:convert';

/// 培养方案抓取时注入页面执行的 JS。
///
/// 逻辑参考 GitHub 上的 TP2MD 项目（Selenium 版）：那边的做法是用 WebDriver
/// 切换 iframe、模拟点击，这里改成在页面里直接跑 JS，用 __findDoc/__findMind
/// 自己去找目标文档和 jsMind 实例，等价于 Selenium 的 switch_to.frame。
class PlanScripts {
  PlanScripts._();

  /// 服务大厅域名，和 AuthService 里保存 Cookie 的域一致。
  static const String origin = 'https://ehall.xidian.edu.cn';

  /// 培养方案应用入口。
  ///
  /// 「个人方案查询」的 appId 是从服务大厅搜索结果里抠出来的，直接带 appId
  /// 进应用比走「搜索 → 点进入应用」稳得多，也少两步。
  static const String appUrl = '$origin/appShow?appId=4766859113956613';

  /// 各脚本共用的工具函数。
  ///
  /// __findDoc 找「包含指定元素」的文档（主文档或同源 iframe，会往下钻几层），
  /// 注意它返回的是 **document**，要拿元素还得再 querySelector；__findMind 在
  /// window 及其同源 iframe 里翻出 jsMind 实例。
  static const String _helpers = r'''
function __findDoc(selector) {
  if (document.querySelector(selector)) return document;
  function scan(doc, depth) {
    if (depth > 4) return null;
    var frames;
    try { frames = doc.querySelectorAll('iframe'); } catch (e) { return null; }
    for (var i = 0; i < frames.length; i++) {
      var inner = null;
      try { inner = frames[i].contentDocument; } catch (e) {}
      if (!inner) continue;
      try {
        if (inner.querySelector(selector)) return inner;
      } catch (e) {}
      var found = scan(inner, depth + 1);
      if (found) return found;
    }
    return null;
  }
  return scan(document, 0);
}
function __findMind() {
  var names = ['_jm', 'jm', 'jsMind', 'jsmind', 'myJsMind',
               'jmInstance', 'jmn', 'mind', 'this_jm'];
  var wins = [window];
  function collect(win, depth) {
    if (depth > 4) return;
    var frames;
    try { frames = win.document.querySelectorAll('iframe'); } catch (e) { return; }
    for (var i = 0; i < frames.length; i++) {
      var w = null;
      try { w = frames[i].contentWindow; } catch (e) {}
      if (!w) continue;
      wins.push(w);
      collect(w, depth + 1);
    }
  }
  collect(window, 0);
  for (var w = 0; w < wins.length; w++) {
    for (var n = 0; n < names.length; n++) {
      try {
        var v = wins[w][names[n]];
        if (v && v.mind && v.mind.root) return v;
      } catch (e) {}
    }
  }
  for (var w2 = 0; w2 < wins.length; w2++) {
    var win = wins[w2];
    for (var k in win) {
      try {
        var v2 = win[k];
        if (v2 && typeof v2 === 'object' && v2.mind && v2.mind.root
            && v2.mind.root.topic !== undefined) return v2;
      } catch (e) {}
    }
  }
  return null;
}
''';

  /// 一站式服务大厅首页的搜索框是否已经出现（说明已完成登录）。
  static String get hasSearchBox =>
      _helpers +
      r'''
(function () {
  return !!__findDoc('input.search__content');
})();
''';

  /// 把关键词写进搜索框（用原生 setter，绕过前端框架对 value 的劫持）。
  static String searchInput(String keyword) =>
      '$_helpers\n'
      '''
(function () {
  var doc = __findDoc('input.search__content');
  if (!doc) return false;
  var input = doc.querySelector('input.search__content');
  if (!input) return false;
  var win = input.ownerDocument.defaultView || window;
  var setter = Object.getOwnPropertyDescriptor(
    win.HTMLInputElement.prototype, 'value'
  ).set;
  setter.call(input, ${jsonEncode(keyword)});
  input.dispatchEvent(new Event('input',  { bubbles: true }));
  input.dispatchEvent(new Event('change', { bubbles: true }));
  return true;
})();
''';

  /// 点击搜索按钮。
  static String get clickSearchButton =>
      _helpers +
      r'''
(function () {
  var doc = __findDoc('button.search__action');
  if (!doc) return false;
  doc.querySelector('button.search__action').click();
  return true;
})();
''';

  /// 诊断用：把当前页面上能看到的应用条目倒出来，看看搜索到底有没有出结果。
  static String get dumpApps =>
      _helpers +
      r'''
(function () {
  var doc = __findDoc('li.appitem') || document;
  var items = doc.querySelectorAll('li.appitem');
  var out = [];
  for (var i = 0; i < items.length && i < 40; i++) {
    var nameEl = items[i].querySelector('.appitem__name');
    var a = items[i].querySelector('a');
    out.push({
      name: nameEl ? nameEl.textContent.trim() : '',
      href: a ? (a.getAttribute('href') || '') : ''
    });
  }
  return JSON.stringify({count: items.length, url: location.href, items: out});
})()
''';

  /// 把页面里的 window.open 换成只记录地址的版本。
  ///
  /// 「进入应用」是开新窗口跳的，但脚本点出来的 window.open 不算用户手势，
  /// 会被弹窗拦截，所以我们自己把地址记下来，交给 Flutter 侧去跳。
  static const String hookOpen = r'''
(function () {
  if (window.__planHooked) return true;
  window.__planHooked = true;
  window.__planOpened = '';
  window.open = function (url) {
    window.__planOpened = String(url || '');
    return null;
  };
  document.addEventListener('click', function (e) {
    var el = e.target;
    for (var i = 0; i < 6 && el; i++) {
      if (el.tagName === 'A' && el.getAttribute('href')) {
        if (!window.__planOpened) {
          window.__planOpened = el.getAttribute('href');
        }
        break;
      }
      el = el.parentElement;
    }
  }, true);
  return true;
})();
''';

  /// 读一下点击之后拿到的地址，空串表示没拿到。
  static const String readOpened = r'''
(function () {
  return String(window.__planOpened || '');
})();
''';

  /// 诊断用：找「进入应用」按钮的祖先链，顺带看看结果列表的结构。
  static String probeSearch(String appName) =>
      '$_helpers\n'
      '''
(function () {
  var out = { url: location.href, enterButtons: [], applist: [], hits: [] };
  var target = ${jsonEncode(appName)};
  var all = document.querySelectorAll('*');
  var compact = function (el) {
    return el.tagName + '.' +
      String(el.className || '').replace(/\\s+/g, '_');
  };

  // 文本是「进入应用」的那个元素，往上找六层看看它是谁的按钮
  for (var i = 0; i < all.length; i++) {
    var el = all[i];
    if (el.children.length > 0) continue;
    var text = (el.textContent || '').replace(/\\s+/g, '');
    if (text !== '进入应用') continue;
    if (out.enterButtons.length >= 3) break;
    var chain = [];
    var p = el;
    for (var k = 0; k < 6 && p; k++) {
      chain.push(compact(p));
      p = p.parentElement;
    }
    out.enterButtons.push(chain.join(' << '));
  }

  // 搜索结果列表的前几项长什么样
  var list = document.querySelector('.applist');
  if (list) {
    var kids = list.children;
    for (var m = 0; m < kids.length && out.applist.length < 2; m++) {
      out.applist.push(kids[m].outerHTML.slice(0, 400));
    }
  }

  // 提到目标应用的那块
  for (var n = 0; n < all.length && out.hits.length < 1; n++) {
    var el2 = all[n];
    if (el2.children.length > 0) continue;
    if ((el2.textContent || '').trim().indexOf(target) < 0) continue;
    var q = el2;
    for (var r = 0; r < 4 && q.parentElement; r++) q = q.parentElement;
    out.hits.push(q.outerHTML.slice(0, 500));
  }

  return JSON.stringify(out);
})()
''';

  /// 搜索结果里是否已经出现目标应用的「进入应用」按钮。
  static String hasEnterApp(String appName) =>
      _helpers + _enterAppBody(appName, click: false);

  /// 点击目标应用的「进入应用」。
  static String clickEnterApp(String appName) =>
      _helpers + _enterAppBody(appName, click: true);

  static String _enterAppBody(String appName, {required bool click}) {
    final String hitButton = click
        ? 'try { btn.click(); } catch (e) {}\n      return true;'
        : 'return true;';
    final String hitCard = click
        ? 'try { el.click(); } catch (e) {}\n      return true;'
        : 'return true;';
    return '''
(function () {
  try {
    var name = ${jsonEncode(appName)};

    // 有的前端要 hover 过后才把「进入应用」渲染出来，先把卡片扫一遍
    var hoverTargets = document.querySelectorAll('.search__apps *, .appitem');
    var limit = hoverTargets.length < 50 ? hoverTargets.length : 50;
    for (var i = 0; i < limit; i++) {
      try {
        hoverTargets[i].dispatchEvent(
          new MouseEvent('mouseover', { bubbles: true })
        );
      } catch (e) {}
    }

    // 1) 优先找「进入应用」按钮，要求它所在的那一块提到了目标应用
    var nodes = document.querySelectorAll('button, a');
    for (var j = 0; j < nodes.length; j++) {
      var btn = nodes[j];
      if ((btn.textContent || '').replace(/\\s+/g, '') !== '进入应用') continue;
      var node = btn;
      var hit = false;
      for (var k = 0; k < 8 && node; k++) {
        if ((node.textContent || '').indexOf(name) >= 0) { hit = true; break; }
        node = node.parentElement;
      }
      if (!hit) continue;
      $hitButton
    }

    // 2) 没有按钮就直接点结果卡片
    var cards = document.querySelectorAll('li, div');
    for (var m = 0; m < cards.length; m++) {
      var el = cards[m];
      var cls = String(el.className || '');
      if (cls.indexOf('applist__item') < 0 && cls.indexOf('appitem') < 0) {
        continue;
      }
      if ((el.textContent || '').indexOf(name) < 0) continue;
      $hitCard
    }

    return false;
  } catch (e) {
    return false;
  }
})();
''';
  }

  /// 进入应用之后那张培养方案卡片是否出现了。
  static String get hasPlanCard =>
      _helpers +
      r'''
(function () {
  return !!__findDoc('div.grpyfa-content[data-action="详情"]');
})();
''';

  /// 点开培养方案卡片，点完才会渲染出 jsMind 树。
  static String get clickPlanCard =>
      _helpers +
      r'''
(function () {
  var doc = __findDoc('div.grpyfa-content[data-action="详情"]');
  if (!doc) return false;
  var cards = doc.querySelectorAll('div.grpyfa-content[data-action="详情"]');
  for (var i = 0; i < cards.length; i++) {
    var card = cards[i];
    try { card.scrollIntoView({ block: 'center' }); } catch (e) {}
    try {
      card.click();
      return true;
    } catch (e) {}
    try {
      card.dispatchEvent(new MouseEvent('click', {
        bubbles: true, cancelable: true, view: window
      }));
      return true;
    } catch (e) {}
  }
  return false;
})();
''';

  /// 培养方案页面里的思维导图节点是否已经渲染。
  static String get hasMindNode =>
      _helpers +
      r'''
(function () {
  return !!__findDoc('jmnode');
})();
''';

  /// 导出整棵培养方案树（topic 里是带标签的 HTML，交给 Dart 侧清洗）。
  static String get exportTree =>
      _helpers +
      r'''
(function () {
  var jm = __findMind();
  if (!jm) return JSON.stringify({ ok: false, error: 'jsMind instance not found' });
  function toObj(node) {
    var o = { id: node.id, topic: node.topic };
    if (node.children && node.children.length > 0) {
      o.children = node.children.map(toObj);
    }
    return o;
  }
  return JSON.stringify({ ok: true, data: toObj(jm.mind.root) });
})();
''';

  /// 选中某个节点，右侧会跟着刷新出它下面的课程。
  static String selectNode(String nodeId) =>
      '$_helpers\n'
      '''
(function () {
  var jm = __findMind();
  if (!jm) return false;
  var id = ${jsonEncode(nodeId)};
  try {
    var n = jm.get_node(id);
    while (n) {
      try { jm.expand_node(n); } catch (e) {}
      n = n.parent;
    }
  } catch (e) {}
  try {
    jm.select_node(id);
    return true;
  } catch (e) {
    return false;
  }
})();
''';

  /// 读取侧边栏里的课程行。
  ///
  /// 只认 kzh 与当前节点一致的行走 TP2MD 的老办法，侧边栏还没刷新到当前节点时
  /// 会出现别的 kzh 或者干脆没有，这两种情况都要靠调用方再等一轮。
  static String readCourses(String nodeId) =>
      '$_helpers\n'
      '''
(function () {
  var id = ${jsonEncode(nodeId)};
  var sel = 'tr.jsmind-course-tr, tr.jsmind-course-row, li.jsmind-course-item, '
          + 'div.jsmind-course-row, div.jsmind-course-item, .jsmind-course-list > *';
  var doc = __findDoc(sel);
  if (!doc) return JSON.stringify({ kzhs: [], rows: [] });

  var rows = doc.querySelectorAll(sel);
  var kzhs = [];
  var out = [];
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i];
    var edit = row.querySelector('a.jsmind-course-edit');
    var kzh = edit ? edit.getAttribute('kzh') : null;
    if (kzh && kzhs.indexOf(kzh) < 0) kzhs.push(kzh);
    if (!kzh || kzh !== id) continue;

    var course = {};
    var codeEl = row.querySelector("span[title][style*='font-weight']");
    if (codeEl) course.code = codeEl.getAttribute('title') || codeEl.textContent.trim();
    var nameEl = row.querySelector('span.jsmind-corse-name');
    course.name = nameEl
      ? (nameEl.getAttribute('title') || nameEl.textContent.trim())
      : '';
    if (edit) course.kch = edit.getAttribute('kch');

    var labels = row.querySelectorAll('label');
    for (var j = 0; j < labels.length; j++) {
      var t = (labels[j].textContent || '').trim();
      if (!t) continue;
      var m;
      if ((m = t.match(/学分[：:]\\s*([\\d.]+)/))) {
        course.credit = parseFloat(m[1]);
        continue;
      }
      if ((m = t.match(/学期[：:]\\s*([^】]+)/))) {
        course.semester = m[1].trim();
        continue;
      }
      if (t === '【考试】' || t === '【考查】') {
        course.examType = t.replace(/[【】]/g, '');
        continue;
      }
      if (t === '【必修】' || t === '【限选】' || t === '【任选】' || t === '【选修】') {
        course.category = t.replace(/[【】]/g, '');
        continue;
      }
      if (t.indexOf('方向') >= 0) {
        course.direction = t.replace(/[【】]/g, '');
        continue;
      }
      if (t.indexOf('学院') >= 0) {
        course.college = t.replace(/[【】]/g, '');
        continue;
      }
    }
    out.push(course);
  }
  return JSON.stringify({ kzhs: kzhs, rows: out });
})();
''';
}
