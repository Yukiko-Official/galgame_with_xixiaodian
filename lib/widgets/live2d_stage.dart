import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_live2d/flutter_live2d.dart';

import '../services/live2d_actor.dart';
import '../services/settings_service.dart';

/// 助手页上的桌宠。
///
/// 把模型铺在给定的区域里，跟着 [Live2DActor] 换表情、做动作。加载不出来就
/// 显示一行提示，不挡着聊天。
class Live2DStage extends StatefulWidget {
  const Live2DStage({super.key});

  @override
  State<Live2DStage> createState() => _Live2DStageState();
}

class _Live2DStageState extends State<Live2DStage> {
  final Live2DViewController _controller = Live2DViewController();

  /// 模型准备好了没。加载期间的指令先跳过，加载完再补一次当前状态。
  bool _ready = false;

  /// 加载失败的原因，非空就换成文字提示。
  String? _error;

  /// 已经播到第几个动作请求，免得 rebuild 时把同一个动作反复播。
  int _appliedSeq = 0;

  /// 当前装着的是哪套模型。设置里换了模型就跟它比一比，决定要不要重新加载。
  Live2DVariant? _loaded;

  @override
  void initState() {
    super.initState();
    Live2DActor.instance.addListener(_onChanged);
    SettingsService.instance.addListener(_onSettingsChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    Live2DActor.instance.removeListener(_onChanged);
    SettingsService.instance.removeListener(_onSettingsChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (SettingsService.instance.live2dVariant != _loaded) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final Live2DVariant variant = SettingsService.instance.live2dVariant;
    try {
      await _controller.whenAttached;
      // 换模型时先把手上这套卸掉，免得两套资源叠在一起
      if (_loaded != null) {
        await _controller.unloadModel();
        _loaded = null;
        if (mounted) {
          setState(() {
            _ready = false;
            _error = null;
          });
        }
      }
      // 原生侧有个竞态：loadModel 请求可能赶在 surface 尺寸就绪之前被处理，那时它
      // 会直接返回 false——不是路径或资源的问题。等一小会儿再试就好了。
      bool ok = false;
      for (int attempt = 0; attempt < 5 && !ok; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        ok = await _controller.loadModel(
          modelDir: variant.modelDir,
          modelFileName: variant.modelFileName,
        );
      }
      if (!mounted) {
        return;
      }
      if (!ok) {
        setState(() => _error = '桌宠模型没能加载出来');
        return;
      }
      _loaded = variant;
      setState(() => _ready = true);
      // 加载这段时间里 AI 可能已经说过话了，补一次让桌宠跟上当前状态
      await _sync();
    } catch (e) {
      if (mounted) {
        setState(() => _error = '桌宠加载失败：$e');
      }
    }
  }

  void _onChanged() {
    unawaited(_sync());
  }

  /// 把桌宠的当前状态同步到模型上。
  Future<void> _sync() async {
    if (!_ready || !mounted) {
      return;
    }
    final Live2DActor actor = Live2DActor.instance;
    try {
      await _controller.setExpression(actor.emotion.expressionIndex);
      final String? motion = actor.motion;
      if (motion != null && actor.motionSeq != _appliedSeq) {
        _appliedSeq = actor.motionSeq;
        await _controller.startMotion(group: motion);
      }
    } catch (_) {
      // 这一次没同步上就算了，状态再变还会重来
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? error = _error;
    if (error != null) {
      return Center(
        child: Text(
          error,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    }
    // 模型加载要编译几十个着色器，得等几秒。这期间给个提示，别让那块地方空着，
    // 不然看着像是坏了。
    return Stack(
      children: <Widget>[
        Live2DView(controller: _controller),
        if (!_ready)
          const Center(
            child: Text(
              '桌宠加载中…',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
      ],
    );
  }
}
