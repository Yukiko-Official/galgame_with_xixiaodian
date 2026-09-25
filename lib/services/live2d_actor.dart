import 'package:flutter/foundation.dart';

/// 可选的桌宠模型。
///
/// 每个模型一套 assets：文件放 `assets/live2d/<id>/`，目录要在 pubspec.yaml 里声明。
/// 加新模型时，把文件放进去、往这里补一项、再到设置页的选项里去（选项直接遍历
/// [values]，不用另外改）。
enum Live2DVariant {
  nailong(
    'nailong',
    '奶蛙',
    'assets/live2d/nailong/',
    'nailong.model3.json',
    hasMotions: false,
  ),
  xxd(
    'xxd',
    '西小电',
    'assets/live2d/xxd/',
    'xxd.model3.json',
    hasMotions: true,
  );

  const Live2DVariant(
    this.id,
    this.label,
    this.modelDir,
    this.modelFileName, {
    required this.hasMotions,
  });

  /// 存本地用的标识，改了相当于换一个设置项。
  final String id;

  /// 给人看的名字，设置页里显示它。
  final String label;

  /// 模型在 assets 里的目录（带尾斜杠）和入口文件名。
  final String modelDir;
  final String modelFileName;

  /// 这套模型带动作文件没。没有的话提示词里就不提动作了——写了也播不出来，
  /// 白占 token。
  final bool hasMotions;

  /// 按 id 找回模型，认不出就用默认那套。
  static Live2DVariant byId(String? id) => values.firstWhere(
    (Live2DVariant item) => item.id == id,
    orElse: () => defaultVariant,
  );

  /// 没选过、或者存的值认不出来时用哪套。
  static const Live2DVariant defaultVariant = xxd;
}

/// 桌宠能表现的情绪。
///
/// 下标对应模型 `model3.json` 里 Expressions 的顺序，而两个模型能表达的**不一样**：
///
/// - 奶蛙：只挂了一条作者给的「去水印」表情，它把 `ParamAngleX7`（模型里就叫
///   「水印开关」）加到 2.0 把水印藏起来，所以下面全都指向 0——不会变脸，但水印关着。
/// - 西小电：压根没声明 Expressions。表情调用会被原生侧忽略掉（下标越界直接 return，
///   不报错），它靠自带的 Idle / Nod / Shake 动作来表现。
///
/// 想给某个模型加表情：做几个情绪向的 .exp3.json 放进对应的 `assets/live2d/<模型>/`，
/// 挂到它 model3.json 的 Expressions 后面，再把下面的下标填回去。**奶蛙的下标 0 必须
/// 留给去水印**，挪走它水印就会露出来（直接 `setParameter` 是没用的，会被每帧的
/// LoadParameters 冲掉）。
enum Live2DEmotion {
  neutral('neutral', 0, '平静'),
  happy('happy', 0, '开心'),
  angry('angry', 0, '生气'),
  sad('sad', 0, '难过'),
  surprised('surprised', 0, '惊讶'),
  shy('shy', 0, '害羞'),
  confused('confused', 0, '困惑');

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

/// 提示词里写的动作名 → 模型 `model3.json` 里 Motion 组的名字。
///
/// 认不出的名字一律不播。模型没这组动作时原生侧本来就会忽略掉（`GetMotionCount`
/// 是 0 就直接 return），所以这张表可以给所有模型共用：西小电带 Idle / Blink /
/// Nod / Shake，奶蛙一个动作文件都没有，标记里写了动作也只会换个表情。
/// Idle 不列进来——那是模型空闲时自己循环播的，不用指挥。
const Map<String, String> live2dMotionGroups = <String, String>{
  'nod': 'Nod',
  'shake': 'Shake',
  'blink': 'Blink',
};

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
