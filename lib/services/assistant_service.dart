import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// 一个服务商预设。
class AssistantProvider {
  const AssistantProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.models,
  });

  /// 存配置用的标识。
  final String id;
  final String name;

  /// OpenAI 兼容的接口根地址，后面拼 `/chat/completions`。
  final String baseUrl;

  /// 常用模型，界面上给个下拉备选。
  final List<String> models;

  bool get isCustom => id == customId;

  static const String customId = 'custom';
}

/// 内置的服务商。都是 OpenAI 兼容的接口，走同一套请求格式。
const List<AssistantProvider> assistantProviders = <AssistantProvider>[
  AssistantProvider(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    models: <String>['deepseek-chat', 'deepseek-reasoner'],
  ),
  AssistantProvider(
    id: 'zhipu',
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    models: <String>['glm-4-flash', 'glm-4-plus', 'glm-4-air'],
  ),
  AssistantProvider(
    id: 'qwen',
    name: '通义千问',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    models: <String>['qwen-plus', 'qwen-turbo', 'qwen-max'],
  ),
  AssistantProvider(
    id: 'openai',
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    models: <String>['gpt-4o-mini', 'gpt-4o'],
  ),
  AssistantProvider(
    id: AssistantProvider.customId,
    name: '自定义（OpenAI 兼容）',
    baseUrl: '',
    models: <String>[],
  ),
];

/// 一条聊天消息。
class ChatMessage {
  ChatMessage({required this.role, required this.content});

  /// `user` 或者 `assistant`。
  final String role;
  String content;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'role': role,
    'content': content,
  };
}

/// 助手的模型配置和聊天逻辑。
class AssistantService extends ChangeNotifier {
  AssistantService._();

  /// 全局单例。
  static final AssistantService instance = AssistantService._();

  static const String _configKey = 'assistant_config';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String _providerId = 'deepseek';
  String _apiKey = '';
  String _customBaseUrl = '';
  String _model = '';

  final List<ChatMessage> _messages = <ChatMessage>[];
  bool _sending = false;
  String? _error;

  /// 当前选的服务商。
  AssistantProvider get provider => assistantProviders.firstWhere(
    (AssistantProvider item) => item.id == _providerId,
    orElse: () => assistantProviders.first,
  );

  String get apiKey => _apiKey;
  String get model => _model;
  String get customBaseUrl => _customBaseUrl;

  /// 实际用的接口根地址，自定义时用自己填的。
  String get baseUrl {
    final String raw = provider.isCustom ? _customBaseUrl : provider.baseUrl;
    return raw.replaceAll(RegExp(r'/+$'), '');
  }

  /// 配置齐了没。
  bool get isConfigured =>
      _apiKey.trim().isNotEmpty &&
      baseUrl.isNotEmpty &&
      _model.trim().isNotEmpty;

  List<ChatMessage> get messages => List<ChatMessage>.unmodifiable(_messages);
  bool get sending => _sending;
  String? get error => _error;

  /// 从本地恢复配置，App 启动时调一次。
  Future<void> restore() async {
    try {
      final String? raw = await _storage.read(key: _configKey);
      if (raw != null && raw.isNotEmpty) {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _providerId = '${decoded['provider'] ?? _providerId}';
          _apiKey = '${decoded['apiKey'] ?? ''}';
          _customBaseUrl = '${decoded['baseUrl'] ?? ''}';
          _model = '${decoded['model'] ?? ''}';
        }
      }
    } catch (_) {}
    if (_model.isEmpty && provider.models.isNotEmpty) {
      _model = provider.models.first;
    }
    notifyListeners();
  }

  /// 存下配置。
  Future<void> saveConfig({
    required String providerId,
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    _providerId = providerId;
    _apiKey = apiKey.trim();
    _customBaseUrl = baseUrl.trim();
    _model = model.trim();
    notifyListeners();
    try {
      await _storage.write(
        key: _configKey,
        value: jsonEncode(<String, dynamic>{
          'provider': _providerId,
          'apiKey': _apiKey,
          'baseUrl': _customBaseUrl,
          'model': _model,
        }),
      );
    } catch (_) {}
  }

  /// 清掉聊天记录。
  void clearMessages() {
    _messages.clear();
    _error = null;
    notifyListeners();
  }

  /// 发一条消息，回复边收边显示。
  Future<void> send(String text) async {
    final String content = text.trim();
    if (content.isEmpty || _sending) {
      return;
    }
    if (!isConfigured) {
      _error = '还没配好模型，先去「设置 → 助手配置」填一下';
      notifyListeners();
      return;
    }

    _error = null;
    _messages.add(ChatMessage(role: 'user', content: content));
    final ChatMessage reply = ChatMessage(role: 'assistant', content: '');
    _messages.add(reply);
    _sending = true;
    notifyListeners();

    final http.Client client = http.Client();
    try {
      final http.Request request = http.Request(
        'POST',
        Uri.parse('$baseUrl/chat/completions'),
      )
        ..headers['Content-Type'] = 'application/json'
        ..headers['Authorization'] = 'Bearer $_apiKey'
        ..body = jsonEncode(<String, dynamic>{
          'model': _model,
          'stream': true,
          'messages': _messages
              // 正等着填内容的那条空回复不能发出去
              .where((ChatMessage item) => !identical(item, reply))
              .map((ChatMessage item) => item.toJson())
              .toList(),
        });

      final http.StreamedResponse response = await client.send(request);
      if (response.statusCode != 200) {
        final String body = await response.stream.bytesToString();
        throw StateError('接口返回 ${response.statusCode}：${_shorten(body)}');
      }

      await for (final String line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (!line.startsWith('data:')) {
          continue;
        }
        final String payload = line.substring(5).trim();
        if (payload.isEmpty) {
          continue;
        }
        if (payload == '[DONE]') {
          break;
        }
        try {
          final Object? chunk = jsonDecode(payload);
          if (chunk is! Map) {
            continue;
          }
          final List<dynamic> choices =
              (chunk['choices'] as List<dynamic>?) ?? const <dynamic>[];
          if (choices.isEmpty) {
            continue;
          }
          final Map<String, dynamic> delta =
              (choices.first['delta'] as Map<String, dynamic>?) ??
              <String, dynamic>{};
          final Object? piece = delta['content'];
          if (piece is String && piece.isNotEmpty) {
            reply.content += piece;
            notifyListeners();
          }
        } catch (_) {
          // 单个分片解析失败就跳过，不打断整段回复
        }
      }

      if (reply.content.isEmpty) {
        reply.content = '（模型没有返回内容）';
      }
    } catch (e) {
      // 一个字都没收到就把这条空气泡撤掉
      if (reply.content.isEmpty) {
        _messages.remove(reply);
      }
      _error = e is StateError ? e.message : '$e';
    } finally {
      client.close();
      _sending = false;
      notifyListeners();
    }
  }

  /// 简单探一下配置能不能用。
  Future<String> testConnection() async {
    if (!isConfigured) {
      return '还没配好，先选服务商、填 Key、选模型';
    }
    final http.Client client = http.Client();
    try {
      final http.Response response = await client.post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode(<String, dynamic>{
          'model': _model,
          'max_tokens': 8,
          'messages': <Map<String, String>>[
            <String, String>{'role': 'user', 'content': '你好'},
          ],
        }),
      );
      if (response.statusCode == 200) {
        return '连通正常';
      }
      return '接口返回 ${response.statusCode}：${_shorten(response.body)}';
    } catch (e) {
      return '连不上：$e';
    } finally {
      client.close();
    }
  }

  /// 报错信息太长了就压成一行截断。
  static String _shorten(String text) {
    final String oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return oneLine.length <= 200 ? oneLine : '${oneLine.substring(0, 200)}…';
  }
}
