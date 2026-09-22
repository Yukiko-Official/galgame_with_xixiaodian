import 'package:flutter/material.dart';

import 'pages/assistant_config_page.dart';
import 'pages/assistant_page.dart';
import 'pages/login_page.dart';
import 'pages/plan_page.dart';
import 'pages/timetable_page.dart';
import 'services/assistant_service.dart';
import 'services/auth_service.dart';
import 'services/plan_service.dart';
import 'services/settings_service.dart';
import 'services/timetable_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.instance.restore();
  await SettingsService.instance.restore();
  await AssistantService.instance.restore();
  // 上次登录过的话，把该账号的缓存数据恢复出来
  if (AuthService.instance.isLoggedIn) {
    await PlanService.instance.onLoginSuccess();
    await TimetableService.instance.onLoginSuccess();
  }
  runApp(const XidianHelperApp());
}

class XidianHelperApp extends StatelessWidget {
  const XidianHelperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (BuildContext context, Widget? child) => MaterialApp(
        title: '西电助手',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.blue,
          brightness: Brightness.dark,
        ),
        themeMode: SettingsService.instance.themeMode,
        home: const HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// 培养方案在 [_pages] 里的位置，登录完会自动切过去。
  static const int _planTabIndex = 2;

  int _index = 0;

  /// 逛过的页面才真正建出来。
  ///
  /// 课表和培养方案各自内嵌一个 WebView，建一次不便宜；但切走就销毁、
  /// 切回来重建更亏。所以用 IndexedStack 留着，同时又不一上来就全建。
  final Set<int> _visited = <int>{0};

  // 四个页面按顺序对应下面的四个标签
  static const _pages = <Widget>[
    AssistantPage(),   // 0 助手
    TimetablePage(),   // 1 课表
    PlanPage(),        // 2 培养方案
    SettingsPage(),    // 3 设置
  ];

  @override
  void initState() {
    super.initState();
    // 登录成功后要自动跳到培养方案页
    PlanService.instance.addListener(_onPlanChanged);
  }

  @override
  void dispose() {
    PlanService.instance.removeListener(_onPlanChanged);
    super.dispose();
  }

  void _onPlanChanged() {
    if (!PlanService.instance.autoFetchRequested || _index == _planTabIndex) {
      return;
    }
    setState(() {
      _index = _planTabIndex;
      _visited.add(_planTabIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          for (int i = 0; i < _pages.length; i++)
            if (_visited.contains(i)) _pages[i] else const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int i) => setState(() {
          _index = i;
          _visited.add(i);
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy),
            label: '助手',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '课表',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: '培养方案',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

// ---------------- 设置页 ----------------
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  /// 打开内嵌浏览器完成统一身份认证登录。
  Future<void> _openLogin(BuildContext context) async {
    final bool? success = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (BuildContext context) => const LoginPage()),
    );
    if (success == true) {
      // 数据和账号绑定：切到这个账号的数据（有缓存就直接用）
      await PlanService.instance.onLoginSuccess();
      await TimetableService.instance.onLoginSuccess();
      if (!context.mounted) {
        return;
      }
      final bool hasPlan = PlanService.instance.tree != null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasPlan ? '登录成功，已加载培养方案' : '登录成功，正在获取培养方案…',
          ),
        ),
      );
      // 没有现成数据就自动抓一遍；切 tab 的信号统一走 requestAutoFetch
      PlanService.instance.requestAutoFetch();
    }
  }

  /// 清除本地保存的登录凭证。
  Future<void> _logout(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后需要重新登录才能同步课表与成绩。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    await AuthService.instance.logout();
    // 登录态没了，内存里的数据也跟着清掉；本地缓存按账号保留
    PlanService.instance.onLogout();
    TimetableService.instance.onLogout();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已退出登录')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[
          AuthService.instance,
          SettingsService.instance,
          AssistantService.instance,
        ]),
        builder: (BuildContext context, Widget? child) {
          final bool loggedIn = AuthService.instance.isLoggedIn;
          return ListView(
            children: [
              const SizedBox(height: 8),
              _sectionTitle('账号'),
              ListTile(
                leading: Icon(loggedIn ? Icons.verified_user : Icons.login),
                title: const Text('登录教务系统'),
                subtitle: Text(loggedIn ? '已登录统一身份认证，点击可重新登录' : '同步课表与成绩'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openLogin(context),
              ),
              if (loggedIn)
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('退出登录'),
                  subtitle: const Text('清除本地保存的登录凭证'),
                  onTap: () => _logout(context),
                ),
              const Divider(),
              _sectionTitle('助手'),
              ListTile(
                leading: const Icon(Icons.smart_toy_outlined),
                title: const Text('助手配置'),
                subtitle: Text(
                  AssistantService.instance.isConfigured
                      ? '${AssistantService.instance.provider.name}'
                            ' · ${AssistantService.instance.model}'
                      : '还没配模型，点这里挑一个',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) =>
                        const AssistantConfigPage(),
                  ),
                ),
              ),
              const Divider(),
              _sectionTitle('数据'),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('清除本地缓存'),
                subtitle: const Text('清掉已抓到的培养方案和课表，下次进页面重新获取'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _clearCache(context),
              ),
              const Divider(),
              _sectionTitle('外观'),
              ListTile(
                leading: const Icon(Icons.brightness_6),
                title: const Text('主题模式'),
                subtitle: Text(
                  SettingsService.labelOf(SettingsService.instance.themeMode),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pickTheme(context),
              ),
              const Divider(),
              _sectionTitle('关于'),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('版本'),
                subtitle: Text('0.1.0'),
              ),
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('开源许可'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: '西电助手',
                  applicationVersion: '0.1.0',
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  /// 清掉抓下来的数据缓存，勾选记录保留。
  Future<void> _clearCache(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('清除本地缓存'),
        content: const Text(
          '会清掉已经抓下来的培养方案和课表，下次进页面要重新获取。\n\n打过的勾会保留。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    await PlanService.instance.clearCache();
    await TimetableService.instance.clearCache();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缓存已清除')));
    }
  }

  /// 选主题模式。
  Future<void> _pickTheme(BuildContext context) async {
    final ThemeMode? picked = await showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 8),
            for (final ThemeMode mode in ThemeMode.values)
              ListTile(
                title: Text(SettingsService.labelOf(mode)),
                trailing: SettingsService.instance.themeMode == mode
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(mode),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) {
      await SettingsService.instance.setThemeMode(picked);
    }
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey,
        ),
      ),
    );
  }
}