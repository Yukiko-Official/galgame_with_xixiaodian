import 'package:flutter/foundation.dart';

/// 桌宠能表现的情绪。
///
/// 下标对应 ariu 这套模型 `model3.json` 里 Expressions 的顺序。那套模型原始的配置
/// 压根没声明表情（它是给 VTube Studio 用的，表情靠热键切），这边是后补进去的。
///
/// 素材不全，得留意：这套模型只有「爱心眼 / 黑化 / 圈圈眼」三个算情绪向的表情，
/// 剩下七个都是换装。所以 sad 和 surprised 暂时都指向那个空表情（切过去等于回到
/// 平静），happy 和 shy 共用爱心眼。想补齐的话，做几个新的 .exp3.json 挂进
/// model3.json 再改这里就行。
enum Live2DEmotion {
  neutral('neutral', 0, '平静'),
  happy('happy', 1, '开心'),
  angry('angry', 3, '生气'),
  sad('sad', 2, '难过'),
  surprised('surprised', 4, '惊讶'),
  shy('shy', 5, '害羞'),
  confused('confused', 6, '困惑');

  const Live2DEmotion(this.id, this.expressionIndex, this.label);

  /// 提示词里用的名字，模型输出的就是它。
  final String id;

  /// 表情在模型里的下标。
  final int expressionIndex;

  /// 给人看的说明。
  final String label;

  /// 按 [id] 找回情绪，认不出就当作平静。
  static Live2DEmotion byId(String id) => values.firstWhere(
    (Live2DEmotion item) => item.id == id.toLowerCase(),
    orElse: () => neutral,
  );
}

/// 模型能播的动作组，别的名字一律不认。
///
/// ariu 这套模型没带动作文件（没有 motions/ 目录），所以这里是空的——标记里就算写了
/// 动作也播不出来，只会换表情。以后换成带动作的模型（比如 Haru 的 Idle / TapBody）
/// 再把映射填回来。
const Map<String, String> live2dMotionGroups = <String, String>{};

/// 一次要执行的指令。
class Live2DAct {
  const Live2DAct({required this.emotion, this.motion});

  final Live2DEmotion emotion;

  /// 动作组名，null 表示只换表情不动。
  final String? motion;
}

/// 桌宠的状态。
///
/// 表情是**状态**（切换后一直保持），动作是**事件**（播一次就完），所以动作带一个
/// 自增序号：界面按序号判断「这是新请求」，rebuild 时就不会把同一个动作反复播。
class Live2DActor extends ChangeNotifier {
  Live2DActor._();

  /// 全局单例，桌宠状态在 App 内共享一份。
  static final Live2DActor instance = Live2DActor._();

  /// 模型放在 assets 里的位置。
  static const String modelDir = 'assets/live2d/ariu/';
  static const String modelFileName = 'ariu.model3.json';

  /// 回复里的控制标记，形如 `[act:happy]` 或者 `[act:angry,tap]`。
  static final RegExp _markPattern = RegExp(
    r'\[\s*act\s*:\s*([a-zA-Z]+)\s*(?:[,，]\s*([a-zA-Z]+)\s*)?\]',
  );

  Live2DEmotion _emotion = Live2DEmotion.neutral;
  String? _motion;
  int _motionSeq = 0;

  /// 当前表情。
  Live2DEmotion get emotion => _emotion;

  /// 最近一次要播的动作组，没有就是 null。
  String? get motion => _motion;

  /// 动作请求的序号，每来一次新的就加一。
  int get motionSeq => _motionSeq;

  /// 执行一条指令。
  void apply(Live2DAct act) {
    _emotion = act.emotion;
    if (act.motion != null) {
      _motion = act.motion;
      _motionSeq++;
    }
    notifyListeners();
  }

  /// 回到平静。
  void reset() {
    _emotion = Live2DEmotion.neutral;
    _motion = null;
    notifyListeners();
  }

  /// 把回复里累积的原文拆成「能显示的文本」和「要执行的指令」。
  ///
  /// [streaming] 为 true 表示回复还没收完，末尾可能是半截标记（比如 `[act:hap`），
  /// 这种残片先扣着不显示，免得聊天气泡里闪出标记。
  static (String, List<Live2DAct>) parse(
    String raw, {
    required bool streaming,
  }) {
    final List<Live2DAct> acts = <Live2DAct>[];
    final StringBuffer visible = StringBuffer();
    int cursor = 0;

    for (final RegExpMatch match in _markPattern.allMatches(raw)) {
      visible.write(raw.substring(cursor, match.start));
      final String? motion = match.group(2);
      acts.add(
        Live2DAct(
          emotion: Live2DEmotion.byId(match.group(1)!),
          motion: motion == null
              ? null
              : live2dMotionGroups[motion.toLowerCase()],
        ),
      );
      cursor = match.end;
    }

    String tail = raw.substring(cursor);
    if (streaming) {
      final int open = tail.lastIndexOf('[');
      if (open >= 0 && _looksLikePartialMark(tail.substring(open))) {
        tail = tail.substring(0, open);
      }
    }
    visible.write(tail);
    return (visible.toString(), acts);
  }

  /// [tail] 像不像一个还没传完的标记开头。
  ///
  /// 只认 `[`、`[a`、`[act`、`[act:hap` 这一路前缀，普通文本里的方括号不受影响。
  static bool _looksLikePartialMark(String tail) {
    if (tail.contains(']')) {
      return false;
    }
    const String prefix = '[act:';
    final String body = tail.toLowerCase();
    if (prefix.startsWith(body)) {
      return true;
    }
    return body.startsWith(prefix) &&
        RegExp(r'^[a-z,\s]*$').hasMatch(body.substring(prefix.length));
  }
}
