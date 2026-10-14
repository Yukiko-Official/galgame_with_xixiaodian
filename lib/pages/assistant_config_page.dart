import 'package:flutter/material.dart';

import '../services/assistant_service.dart';
import '../services/settings_service.dart';

/// 西小电配置：选服务商、填 Key、选模型。
class AssistantConfigPage extends StatefulWidget {
  const AssistantConfigPage({super.key});

  @override
  State<AssistantConfigPage> createState() => _AssistantConfigPageState();
}

class _AssistantConfigPageState extends State<AssistantConfigPage> {
  final AssistantService _service = AssistantService.instance;

  late String _providerId = _service.provider.id;
  late final TextEditingController _keyController = TextEditingController(
    text: _service.apiKey,
  );
  late final TextEditingController _baseUrlController = TextEditingController(
    text: _service.customBaseUrl,
  );
  late final TextEditingController _modelController = TextEditingController(
    text: _service.model,
  );
  late final TextEditingController _promptController = TextEditingController(
    text: _service.systemPrompt,
  );
  late bool _proactiveEnabled = _service.proactiveEnabled;
  late bool _classReminderEnabled = _service.classReminderEnabled;
  late bool _jitterEnabled = _service.jitterEnabled;
  late bool _quietEnabled = _service.quietEnabled;
  late TimeOfDay _quietStart = _toTime(_service.quietStartMinutes);
  late TimeOfDay _quietEnd = _toTime(_service.quietEndMinutes);
  late int _proactiveInterval = _service.proactiveIntervalMinutes;
  late final TextEditingController _proactivePromptController =
      TextEditingController(text: _service.proactivePrompt);

  static TimeOfDay _toTime(int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  static int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  bool _testing = false;
  bool _speaking = false;
  String? _testResult;

  @override
  void dispose() {
    _keyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _promptController.dispose();
    _proactivePromptController.dispose();
    super.dispose();
  }

  AssistantProvider get _selected => assistantProviders.firstWhere(
    (AssistantProvider item) => item.id == _providerId,
    orElse: () => assistantProviders.first,
  );

  /// 把屏幕上这份配置写进 service，保存和测试都先用它。
  Future<void> _saveForm() {
    return _service.saveConfig(
      providerId: _providerId,
      apiKey: _keyController.text,
      baseUrl: _baseUrlController.text,
      model: _modelController.text,
      systemPrompt: _promptController.text,
      proactiveEnabled: _proactiveEnabled,
      proactiveIntervalMinutes: _proactiveInterval,
      proactivePrompt: _proactivePromptController.text,
      classReminderEnabled: _classReminderEnabled,
      jitterEnabled: _jitterEnabled,
      quietEnabled: _quietEnabled,
      quietStartMinutes: _toMinutes(_quietStart),
      quietEndMinutes: _toMinutes(_quietEnd),
    );
  }

  Future<void> _save() async {
    await _saveForm();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已保存')));
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    // 先把屏幕上的这份存下来，测的就是它
    await _saveForm();
    final String result = await _service.testConnection();
    if (!mounted) {
      return;
    }
    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  /// 保存后立刻让它主动说一条，方便验证效果。
  Future<void> _speakNow() async {
    setState(() => _speaking = true);
    await _saveForm();
    if (!_service.isConfigured) {
      if (mounted) {
        setState(() => _speaking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('还没配好模型，先填上面的配置')),
        );
      }
      return;
    }
    await _service.speakProactively();
    if (!mounted) {
      return;
    }
    setState(() => _speaking = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('说了，回对话页看看吧')),
    );
  }

  /// 间隔档位的显示文案。
  String _intervalLabel(int minutes) =>
      minutes >= 60 ? '${minutes ~/ 60} 小时' : '$minutes 分钟';

  /// 选免打扰的开始或结束时间。
  Future<void> _pickQuietTime({required bool isStart}) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _quietStart : _quietEnd,
      helpText: isStart ? '免打扰开始时间' : '免打扰结束时间',
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _quietStart = picked;
        } else {
          _quietEnd = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AssistantProvider selected = _selected;
    return Scaffold(
      appBar: AppBar(
        title: Text('${SettingsService.instance.assistantName}配置'),
        actions: <Widget>[
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          _label('服务商'),
          DropdownButtonFormField<String>(
            initialValue: _providerId,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: <DropdownMenuItem<String>>[
              for (final AssistantProvider item in assistantProviders)
                DropdownMenuItem<String>(
                  value: item.id,
                  child: Text(item.name),
                ),
            ],
            onChanged: (String? value) {
              if (value == null) {
                return;
              }
              setState(() {
                _providerId = value;
                final AssistantProvider next = _selected;
                if (!next.isCustom && next.models.isNotEmpty) {
                  _modelController.text = next.models.first;
                }
                _testResult = null;
              });
            },
          ),
          const SizedBox(height: 16),
          if (selected.isCustom) ...<Widget>[
            _label('接口地址'),
            TextField(
              controller: _baseUrlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                hintText: 'https://example.com/v1',
              ),
            ),
            const SizedBox(height: 16),
          ],
          _label('API Key'),
          TextField(
            controller: _keyController,
            obscureText: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              hintText: 'sk-...',
            ),
          ),
          const SizedBox(height: 16),
          _label('模型'),
          TextField(
            controller: _modelController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              hintText: 'deepseek-chat',
            ),
          ),
          if (!selected.isCustom && selected.models.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final String name in selected.models)
                  ActionChip(
                    label: Text(name),
                    onPressed: () =>
                        setState(() => _modelController.text = name),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          _label('主动消息'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _proactiveEnabled,
            onChanged: (bool value) =>
                setState(() => _proactiveEnabled = value),
            title: const Text('定时主动找你聊天'),
            subtitle: const Text('到点了它会自己发起话题，不用你先开口'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _classReminderEnabled,
            onChanged: (bool value) =>
                setState(() => _classReminderEnabled = value),
            title: const Text('附加：上课前提醒'),
            subtitle: Text(
              '课前 ${AssistantService.classReminderAhead.inMinutes} 分钟'
              '结合课表提醒你去教室，不开上面的闲聊也能单独用',
            ),
          ),
          if (_proactiveEnabled) ...<Widget>[
            const SizedBox(height: 4),
            _label('多久主动一次'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final int minutes in proactiveIntervalOptions)
                  ChoiceChip(
                    label: Text(_intervalLabel(minutes)),
                    selected: _proactiveInterval == minutes,
                    onSelected: (_) => setState(
                      () => _proactiveInterval = minutes,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _jitterEnabled,
              onChanged: (bool value) =>
                  setState(() => _jitterEnabled = value),
              title: const Text('间隔随机浮动'),
              subtitle: const Text('在设定间隔的 ±20% 之间随机，不那么机械准点'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _quietEnabled,
              onChanged: (bool value) =>
                  setState(() => _quietEnabled = value),
              title: const Text('免打扰时段'),
              subtitle: Text(
                _quietEnabled
                    ? '${_quietStart.format(context)} – '
                          '${_quietEnd.format(context)} 之间不主动搭话、不弹通知'
                    : '设定一段时间不主动搭话、不弹通知',
              ),
            ),
            if (_quietEnabled)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  children: <Widget>[
                    TextButton(
                      onPressed: () => _pickQuietTime(isStart: true),
                      child: Text('开始 ${_quietStart.format(context)}'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _pickQuietTime(isStart: false),
                      child: Text('结束 ${_quietEnd.format(context)}'),
                    ),
                  ],
                ),
              ),
            if (_quietEnabled)
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 4),
                child: Text(
                  '上课前提醒不受免打扰影响，到点照样叫你。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                _label('主动说点什么'),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(
                    () => _proactivePromptController.text =
                        defaultProactivePrompt,
                  ),
                  child: const Text('恢复默认'),
                ),
              ],
            ),
            TextField(
              controller: _proactivePromptController,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '告诉它主动搭话时该聊什么，比如提醒喝水、随机问候',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _speaking || _testing ? null : _speakNow,
              icon: _speaking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.campaign_outlined, size: 18),
              label: const Text('保存并马上说一句试试'),
            ),
          ],
          if (_proactiveEnabled || _classReminderEnabled) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '只有 App 在运行时才会到点发言；退到后台会发系统通知，'
              '完全杀掉后定时器也会停。上课提醒需要本地已有课表。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: <Widget>[
              _label('人设提示词'),
              const Spacer(),
              TextButton(
                onPressed: () => setState(
                  () => _promptController.text = defaultSystemPrompt,
                ),
                child: const Text('恢复默认'),
              ),
            ],
          ),
          TextField(
            controller: _promptController,
            minLines: 6,
            maxLines: 14,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '给西小电的 system prompt',
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('测试连通'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('保存'),
                ),
              ),
            ],
          ),
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _testResult!,
                style: TextStyle(
                  color: _testResult == '连通正常'
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                ),
              ),
            ),
          const SizedBox(height: 28),
          Text(
            'Key 只存在这台手机上。\n接口走的是 OpenAI 兼容格式，'
            '上面没列的服务商把地址填进「自定义」也能用。',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );
}
