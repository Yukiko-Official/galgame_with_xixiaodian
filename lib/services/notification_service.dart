import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 本地通知。
///
/// 现在只负责一件事：助手主动发言但用户没在看聊天页时，把这句话弹成通知。
/// 内容是 App 运行期间模型到点现生成的，不再做预排系统闹钟。
class NotificationService {
  NotificationService._();

  /// 全局单例。
  static final NotificationService instance = NotificationService._();

  static const String _proactiveChannelId = 'assistant_proactive';
  static const String _proactiveChannelName = '助手主动消息';
  static const String _proactiveChannelDescription = '西小电到点主动找你聊天';

  /// 主动消息通知的 payload，点了就跳回助手页。
  static const String _proactivePayload = 'assistant';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  /// 点了主动消息通知时的回调，由外层（HomeShell）挂上切 tab 的动作。
  void Function()? onProactiveTapped;

  /// 初始化，App 启动时调一次。
  Future<void> init() async {
    if (_ready) {
      return;
    }
    tzdata.initializeTimeZones();
    // 学校在东八区，直接用这个；拿设备时区要多引一个依赖，暂时不值当
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload == _proactivePayload) {
          onProactiveTapped?.call();
        }
      },
    );
    _ready = true;
  }

  /// 申请通知权限。主动消息开着时提前要，真到点才弹得出来。
  Future<void> requestPermissions() async {
    await init();
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
  }

  /// 立刻弹一条助手主动消息通知。
  ///
  /// 内容得等模型到点现生成，所以只在 App 还活着、定时器跑得动时才发得出来。
  Future<void> showProactive(String title, String body) async {
    await init();
    // id 取时间戳搓一个，同一条不会被上一条覆盖
    final int id =
        100000 + DateTime.now().millisecondsSinceEpoch.remainder(900000);
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: _proactivePayload,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _proactiveChannelId,
          _proactiveChannelName,
          channelDescription: _proactiveChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
