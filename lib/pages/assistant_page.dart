import 'package:flutter/material.dart';

import '../services/assistant_service.dart';
import '../services/settings_service.dart';
import 'assistant_config_page.dart';

/// 助手聊天页。
class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final AssistantService _service = AssistantService.instance;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChanged);
    // 彩蛋会改标题上的名字
    SettingsService.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    SettingsService.instance.removeListener(_onChanged);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    // 回复是一点点挤出来的，每来一点就跟着滚到底
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final String text = _input.text;
    if (text.trim().isEmpty) {
      return;
    }
    _input.clear();
    await _service.send(text);
  }

  void _openConfig() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const AssistantConfigPage(),
      ),
    );
  }

  Future<void> _clear() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('清空对话'),
        content: const Text('这段聊天记录会没掉，配置不受影响。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _service.clearMessages();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(SettingsService.instance.assistantName),
        actions: <Widget>[
          IconButton(
            tooltip: '清空对话',
            onPressed: _service.messages.isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          IconButton(
            tooltip: '${SettingsService.instance.assistantName}配置',
            onPressed: _openConfig,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (!_service.isConfigured) _buildHint(),
          Expanded(
            child: _service.messages.isEmpty
                ? _buildEmpty()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: _service.messages.length,
                    itemBuilder: (BuildContext context, int index) =>
                        _buildBubble(_service.messages[index]),
                  ),
          ),
          if (_service.error != null) _buildError(),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildHint() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: InkWell(
        onTap: _openConfig,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(Icons.tune, size: 20, color: scheme.onTertiaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '还没配模型，点这里去设置',
                  style: TextStyle(color: scheme.onTertiaryContainer),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: scheme.onTertiaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.smart_toy_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              _service.isConfigured
                  ? '有什么想问的？'
                  : '先去「${SettingsService.instance.assistantName}配置」挑个模型',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(ChatMessage message) {
    final bool isUser = message.role == 'user';
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool waiting = message.content.isEmpty && _service.sending;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(
          waiting ? '正在想…' : message.content,
          style: TextStyle(
            fontSize: 15,
            height: 1.4,
            color: waiting ? Colors.grey : null,
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        _service.error!,
        style: TextStyle(fontSize: 13, color: scheme.onErrorContainer),
      ),
    );
  }

  Widget _buildInput() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (String _) => _send(),
                decoration: const InputDecoration(
                  hintText: '问点什么…',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              onPressed: _service.sending ? null : _send,
              icon: _service.sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_upward),
            ),
          ],
        ),
      ),
    );
  }
}
