import 'package:flutter/material.dart';

import '../services/assistant_service.dart';

/// 助手配置：选服务商、填 Key、选模型。
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

  bool _testing = false;
  String? _testResult;

  @override
  void dispose() {
    _keyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  AssistantProvider get _selected => assistantProviders.firstWhere(
    (AssistantProvider item) => item.id == _providerId,
    orElse: () => assistantProviders.first,
  );

  Future<void> _save() async {
    await _service.saveConfig(
      providerId: _providerId,
      apiKey: _keyController.text,
      baseUrl: _baseUrlController.text,
      model: _modelController.text,
    );
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
    await _service.saveConfig(
      providerId: _providerId,
      apiKey: _keyController.text,
      baseUrl: _baseUrlController.text,
      model: _modelController.text,
    );
    final String result = await _service.testConnection();
    if (!mounted) {
      return;
    }
    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AssistantProvider selected = _selected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('助手配置'),
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
