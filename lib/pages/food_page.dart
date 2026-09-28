import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 「今天吃什么」页。
///
/// 就是个 WebView 套壳：内容全在自建的站点上，这边只负责打开、给个进度条，
/// 加载不出来的时候让人能重试一次。
class FoodPage extends StatefulWidget {
  const FoodPage({super.key});

  /// 站点地址。换地方改这里，别忘了同步改
  /// `android/app/src/main/res/xml/network_security_config.xml` 里的明文白名单，
  /// 不然 Android 会把 http 请求拦掉。
  static const String url = 'http://47.76.117.170:114/index.php';

  @override
  State<FoodPage> createState() => _FoodPageState();
}

class _FoodPageState extends State<FoodPage> {
  InAppWebViewController? _controller;

  /// 加载进度，到 1 就把进度条收起来。
  double _progress = 0;

  /// 主页面的加载错误，非空就把整页换成错误提示。
  String? _error;

  /// 重新加载：失败后点「重试」、或者点右上角的刷新都走这里。
  Future<void> _reload() async {
    setState(() {
      _error = null;
      _progress = 0;
    });
    final InAppWebViewController? controller = _controller;
    if (controller == null) {
      return;
    }
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(FoodPage.url)));
  }

  @override
  Widget build(BuildContext context) {
    final String? error = _error;
    return Scaffold(
      appBar: AppBar(
        title: const Text('今天吃什么'),
        bottom: error == null && _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress),
              )
            : null,
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: error == null ? _buildWebView() : _buildError(error),
    );
  }

  Widget _buildWebView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(FoodPage.url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        thirdPartyCookiesEnabled: true,
      ),
      onWebViewCreated: (InAppWebViewController controller) {
        _controller = controller;
      },
      onProgressChanged: (InAppWebViewController controller, int progress) {
        setState(() => _progress = progress / 100);
      },
      onReceivedError: (
        InAppWebViewController controller,
        WebResourceRequest request,
        WebResourceError error,
      ) {
        // 图片、脚本这类子资源挂了不影响用，只有主页面出错才整页提示
        if (request.isForMainFrame == true) {
          setState(() => _error = '页面没能打开（${error.description}）');
        }
      },
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.cloud_off,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
