import 'dart:io';

import 'package:fl_clash/common/color.dart';
import 'package:fl_clash/common/preferences_storage_error.dart';
import 'package:fl_clash/common/startup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class InitLoadingScreen extends StatelessWidget {
  final ValueListenable<String> stage;

  const InitLoadingScreen({super.key, required this.stage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0787C9)),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF40B8F2),
          brightness: Brightness.dark,
        ),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.shield_outlined,
                    size: 38,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '蜂窝加速器',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 18),
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 14),
                ValueListenableBuilder<String>(
                  valueListenable: stage,
                  builder: (_, value, _) => Text(
                    value,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InitErrorScreen extends StatefulWidget {
  final Object error;
  final StackTrace stack;
  final Future<void> Function(String details)? copyDetails;

  const InitErrorScreen({
    super.key,
    required this.error,
    required this.stack,
    this.copyDetails,
  });

  @override
  State<InitErrorScreen> createState() => _InitErrorScreenState();
}

class _InitErrorScreenState extends State<InitErrorScreen> {
  bool _copying = false;

  bool get _hasStorageError {
    Object? cause = widget.error;
    while (cause is StartupStageException) {
      cause = cause.cause;
    }
    return cause is PreferenceStorageException;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('启动失败'),
        backgroundColor: colorScheme.error,
        foregroundColor: colorScheme.onError,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.report_problem,
                    color: colorScheme.error,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _hasStorageError
                          ? '本地配置无法读取或保存。请完全退出其他蜂窝客户端，检查磁盘剩余空间和配置文件的读写权限后重试。'
                          : '应用启动时遇到问题。请完全退出客户端后重试；仍无法启动时，请复制错误详情发送给客服。',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              if (_hasStorageError) ...[
                const SizedBox(height: 12),
                const Text('本次启动已停止，以免在配置无法安全读写时覆盖原文件。请复制详情发送给客服协助排查。'),
              ],
              const SizedBox(height: 24),
              _buildSectionLabel('错误详情'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.opacity50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.error.opacity50),
                ),
                child: SelectableText(
                  widget.error.toString(),
                  style: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionLabel('调用信息'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[900]
                      : Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.opacity50),
                ),
                child: SelectableText(
                  widget.stack.toString(),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _copying ? null : _copyToClipboard,
        label: Text(_copying ? '复制中…' : '复制详情'),
        icon: const Icon(Icons.copy),
        backgroundColor: colorScheme.error,
        foregroundColor: colorScheme.onError,
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }

  Future<void> _copyToClipboard() async {
    if (_copying) return;
    setState(() => _copying = true);
    try {
      final text =
          '=== 系统信息 ===\n${Platform.operatingSystem} ${Platform.operatingSystemVersion}'
          '\n\n=== 错误详情 ===\n${widget.error}'
          '\n\n=== 调用信息 ===\n${widget.stack}';
      final copyDetails = widget.copyDetails;
      if (copyDetails != null) {
        await copyDetails(text);
      } else {
        await Clipboard.setData(ClipboardData(text: text));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('错误详情已复制'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('复制失败，请手动选择并复制下方错误详情。')));
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }
}
