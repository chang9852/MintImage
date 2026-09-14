import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/settings_model.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/favorite_folders_provider.dart';
import '../../core/providers/image_list_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/webdav_backup_service.dart';
import '../../core/version/app_version.dart';
import '../../shared/theme.dart';
import '../logs/request_log_page.dart';
import 'api_profile_edit_page.dart';
import 'prompt_optimization_profile_edit_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppThemeTokens.canvas, AppThemeTokens.canvasTint],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            const _AppInfoCard(),
            const SizedBox(height: 12),
            _RequestTimeoutCard(
              timeoutSeconds: settings.requestTimeoutSeconds,
              onEdit: () => _editRequestTimeout(context, ref, settings),
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.receipt_long_rounded,
              title: '请求日志',
              description: '查看当前进程记录的请求、响应和错误详情。',
              actionLabel: '查看日志',
              onAction: () => _openRequestLogs(context),
            ),
            const SizedBox(height: 12),
            _DataBackupCard(
              webDavConfig: settings.webDavBackupConfig,
              onExportToFile: () => _exportBackupToFile(context, ref, settings),
              onRestoreFromFile: () =>
                  _restoreBackupFromFile(context, ref, settings),
              onEditWebDav: () => _editWebDavConfig(context, ref, settings),
              onSyncToWebDav: () => _syncBackupToWebDav(context, ref, settings),
              onRestoreFromWebDav: () =>
                  _restoreBackupFromWebDav(context, ref, settings),
            ),
            const SizedBox(height: 16),
            _SectionTitle(
              icon: Icons.auto_awesome_motion_rounded,
              title: '生图API',
            ),
            const SizedBox(height: 8),
            for (final profile in settings.profiles)
              Slidable(
                key: ValueKey('image-${profile.id}'),
                endActionPane: settings.profiles.length <= 1
                    ? null
                    : ActionPane(
                        motion: const ScrollMotion(),
                        children: [
                          SlidableAction(
                            onPressed: (_) async {
                              await ref
                                  .read(settingsProvider.notifier)
                                  .deleteProfile(profile.id);
                            },
                            backgroundColor: Colors.red.shade400,
                            foregroundColor: Colors.white,
                            icon: Icons.delete_rounded,
                            label: '删除',
                          ),
                        ],
                      ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ImageProfileCard(
                    profile: profile,
                    isActive: profile.id == settings.activeProfileId,
                    onTap: () async {
                      await ref
                          .read(settingsProvider.notifier)
                          .setActiveProfile(profile.id);
                    },
                    onEdit: () => _openImageEditor(context, profile: profile),
                  ),
                ),
              ),
            _AddConfigButton(
              icon: Icons.add_rounded,
              label: '添加生图 API',
              onTap: () => _openImageEditor(context),
            ),
            const SizedBox(height: 8),
            // 直接新增一份 xAI Grok Imagine 配置：
            // Base URL 与模型名已预填，只需补 API Key。
            _AddConfigButton(
              icon: Icons.auto_awesome_rounded,
              label: '添加 Grok Imagine 生图 API',
              onTap: () => _openImageEditor(
                context,
                initialApiMode: ImageGenerationApiMode.xaiImagine,
              ),
            ),
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 14),
            _SectionTitle(icon: Icons.auto_fix_high_rounded, title: '提示词优化API'),
            const SizedBox(height: 8),
            if (settings.promptOptimizationProfiles.isEmpty) ...[
              _EmptyConfigHint(text: '还没有提示词优化 API。添加后，首页输入框右侧会启用提示词优化。'),
              const SizedBox(height: 8),
            ],
            for (final profile in settings.promptOptimizationProfiles)
              Slidable(
                key: ValueKey('optimizer-${profile.id}'),
                endActionPane: ActionPane(
                  motion: const ScrollMotion(),
                  children: [
                    SlidableAction(
                      onPressed: (_) async {
                        await ref
                            .read(settingsProvider.notifier)
                            .deletePromptOptimizationProfile(profile.id);
                      },
                      backgroundColor: Colors.red.shade400,
                      foregroundColor: Colors.white,
                      icon: Icons.delete_rounded,
                      label: '删除',
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PromptOptimizationProfileCard(
                    profile: profile,
                    isActive:
                        profile.id ==
                        settings.activePromptOptimizationProfileId,
                    onTap: () async {
                      await ref
                          .read(settingsProvider.notifier)
                          .setActivePromptOptimizationProfile(profile.id);
                    },
                    onEdit: () => _openPromptOptimizationEditor(
                      context,
                      profile: profile,
                    ),
                  ),
                ),
              ),
            _AddConfigButton(
              icon: Icons.add_rounded,
              label: '添加提示词优化 API',
              onTap: () => _openPromptOptimizationEditor(context),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('清除历史记录'),
                      content: const Text('这会删除所有生成记录，但不会清除 API 配置。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('确认清除'),
                        ),
                      ],
                    );
                  },
                );

                if (confirmed != true || !context.mounted) {
                  return;
                }

                await ref.read(imageListProvider.notifier).clearHistory();
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('历史记录已清空。')));
              },
              icon: const Icon(Icons.delete_sweep_rounded),
              label: const Text('清除历史记录'),
              style: FilledButton.styleFrom(
                backgroundColor: AppThemeTokens.dangerSurface,
                foregroundColor: AppThemeTokens.dangerText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openImageEditor(
    BuildContext context, {
    ApiProfile? profile,
    ImageGenerationApiMode? initialApiMode,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ApiProfileEditPage(
          profile: profile,
          initialApiMode: initialApiMode,
        ),
      ),
    );
  }

  Future<void> _openPromptOptimizationEditor(
    BuildContext context, {
    PromptOptimizationProfile? profile,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PromptOptimizationProfileEditPage(profile: profile),
      ),
    );
  }

  Future<void> _editRequestTimeout(
    BuildContext context,
    WidgetRef ref,
    SettingsModel settings,
  ) async {
    final controller = TextEditingController(
      text: settings.requestTimeoutSeconds.toString(),
    );

    final timeoutSeconds = await showDialog<int>(
      context: context,
      builder: (context) {
        String? errorText;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('请求超时（秒）'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: '超时时间',
                      suffixText: '秒',
                      errorText: errorText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '默认 600 秒。生成较慢时可以适当调高。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final parsed = int.tryParse(controller.text.trim());
                    if (parsed == null || parsed <= 0) {
                      setState(() {
                        errorText = '请输入大于 0 的整数';
                      });
                      return;
                    }

                    Navigator.of(context).pop(parsed);
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    if (timeoutSeconds == null) {
      return;
    }

    await ref
        .read(settingsProvider.notifier)
        .setRequestTimeoutSeconds(timeoutSeconds);
  }

  Future<void> _exportBackupToFile(
    BuildContext context,
    WidgetRef ref,
    SettingsModel settings,
  ) async {
    final confirmed = await _confirmSensitiveBackup(context, title: '导出备份');
    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      final backup = await _runWithProgress<BackupArchiveResult>(
        context,
        message: '正在生成备份...',
        task: () => ref
            .read(backupServiceProvider)
            .createBackupArchive(settings: settings),
      );
      if (backup == null || !context.mounted) {
        return;
      }

      final savedPath = await FilePicker.saveFile(
        dialogTitle: '导出备份',
        fileName: backup.fileName,
        type: FileType.custom,
        allowedExtensions: const ['mintbackup'],
        bytes: await backup.file.readAsBytes(),
        lockParentWindow: true,
      );
      if (savedPath == null || !context.mounted) {
        return;
      }

      _showSnack(context, '备份已导出：${p.basename(savedPath)}');
      await _showBackupWarnings(context, backup.warnings);
    } catch (error) {
      if (context.mounted) {
        _showSnack(context, _errorMessage(error));
      }
    }
  }

  Future<void> _restoreBackupFromFile(
    BuildContext context,
    WidgetRef ref,
    SettingsModel settings,
  ) async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: '选择备份文件',
      type: FileType.custom,
      allowedExtensions: const ['mintbackup'],
      withData: true,
      lockParentWindow: true,
    );
    if (picked == null || picked.files.isEmpty || !context.mounted) {
      return;
    }

    final backupFile = await _fileFromPickedBackup(picked.files.single);
    if (!context.mounted) {
      return;
    }

    final confirmed = await _confirmRestore(context, source: '文件');
    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      final result = await _runWithProgress<BackupRestoreResult>(
        context,
        message: '正在恢复备份...',
        task: () => ref
            .read(backupServiceProvider)
            .restoreFromArchive(backupFile, currentSettings: settings),
      );
      if (result == null || !context.mounted) {
        return;
      }
      await _applyRestoreResult(context, ref, result);
    } catch (error) {
      if (context.mounted) {
        _showSnack(context, _errorMessage(error));
      }
    }
  }

  Future<void> _editWebDavConfig(
    BuildContext context,
    WidgetRef ref,
    SettingsModel settings,
  ) async {
    final current = settings.webDavBackupConfig;
    final baseUrlController = TextEditingController(
      text: current?.baseUrl ?? '',
    );
    final usernameController = TextEditingController(
      text: current?.username ?? '',
    );
    final passwordController = TextEditingController(
      text: current?.password ?? '',
    );
    final directoryController = TextEditingController(
      text: current?.remoteDirectory ?? 'MintImage/backups',
    );

    final config = await showDialog<WebDavBackupConfig>(
      context: context,
      builder: (context) {
        String? errorText;
        var statusIsSuccess = false;
        var testing = false;
        var passwordVisible = false;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('WebDAV 设置'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: baseUrlController,
                      decoration: const InputDecoration(
                        labelText: 'WebDAV 地址',
                        hintText: 'https://example.com:5244/',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(labelText: '用户名'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: passwordController,
                      obscureText: !passwordVisible,
                      decoration: InputDecoration(
                        labelText: '密码',
                        suffixIcon: IconButton(
                          tooltip: passwordVisible ? '隐藏密码' : '显示密码',
                          onPressed: () => setState(() {
                            passwordVisible = !passwordVisible;
                          }),
                          icon: Icon(
                            passwordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: directoryController,
                      decoration: const InputDecoration(
                        labelText: '远端目录',
                        hintText: 'MintImage/backups',
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorText!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: statusIsSuccess
                              ? AppThemeTokens.primaryStrong
                              : Colors.red.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: testing
                      ? null
                      : () async {
                          final baseUrl = baseUrlController.text.trim();
                          final remoteDirectory = directoryController.text
                              .trim();
                          final uri = Uri.tryParse(baseUrl);
                          if (uri == null ||
                              !uri.hasScheme ||
                              uri.host.isEmpty ||
                              remoteDirectory.isEmpty) {
                            setState(() {
                              statusIsSuccess = false;
                              errorText = '请填写有效的 WebDAV 地址和远端目录。';
                            });
                            return;
                          }

                          setState(() {
                            testing = true;
                            statusIsSuccess = false;
                            errorText = '正在测试连接...';
                          });
                          try {
                            await ref
                                .read(webDavBackupServiceProvider)
                                .testConnection(
                                  WebDavBackupConfig(
                                    baseUrl: baseUrl,
                                    username: usernameController.text.trim(),
                                    password: passwordController.text,
                                    remoteDirectory: remoteDirectory,
                                  ),
                                );
                            if (!context.mounted) {
                              return;
                            }
                            setState(() {
                              testing = false;
                              statusIsSuccess = true;
                              errorText = '连接成功。';
                            });
                          } catch (error) {
                            if (!context.mounted) {
                              return;
                            }
                            setState(() {
                              testing = false;
                              statusIsSuccess = false;
                              errorText = _errorMessage(error);
                            });
                          }
                        },
                  child: Text(testing ? '测试中...' : '测试连接'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: testing
                      ? null
                      : () {
                          final baseUrl = baseUrlController.text.trim();
                          final remoteDirectory = directoryController.text
                              .trim();
                          final uri = Uri.tryParse(baseUrl);
                          if (uri == null ||
                              !uri.hasScheme ||
                              uri.host.isEmpty ||
                              remoteDirectory.isEmpty) {
                            setState(() {
                              statusIsSuccess = false;
                              errorText = '请填写有效的 WebDAV 地址和远端目录。';
                            });
                            return;
                          }

                          Navigator.of(context).pop(
                            WebDavBackupConfig(
                              baseUrl: baseUrl,
                              username: usernameController.text.trim(),
                              password: passwordController.text,
                              remoteDirectory: remoteDirectory,
                            ),
                          );
                        },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    baseUrlController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    directoryController.dispose();

    if (config == null) {
      return;
    }
    await ref.read(settingsProvider.notifier).setWebDavBackupConfig(config);
  }

  Future<void> _syncBackupToWebDav(
    BuildContext context,
    WidgetRef ref,
    SettingsModel settings,
  ) async {
    final config = settings.webDavBackupConfig;
    if (config == null || !config.isConfigured) {
      _showSnack(context, '请先配置 WebDAV。');
      await _editWebDavConfig(context, ref, settings);
      return;
    }

    final confirmed = await _confirmSensitiveBackup(
      context,
      title: '同步到 WebDAV',
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    var warnings = const <String>[];
    try {
      await _runWithProgress<void>(
        context,
        message: '正在同步到 WebDAV...',
        task: () async {
          final backup = await ref
              .read(backupServiceProvider)
              .createBackupArchive(settings: settings);
          warnings = backup.warnings;
          await ref
              .read(webDavBackupServiceProvider)
              .uploadLatestBackup(backup.file, config);
        },
      );
      if (!context.mounted) {
        return;
      }
      _showSnack(context, '已同步到 WebDAV。');
      await _showBackupWarnings(context, warnings);
    } catch (error) {
      if (context.mounted) {
        _showSnack(context, _errorMessage(error));
      }
    }
  }

  Future<void> _restoreBackupFromWebDav(
    BuildContext context,
    WidgetRef ref,
    SettingsModel settings,
  ) async {
    final config = settings.webDavBackupConfig;
    if (config == null || !config.isConfigured) {
      _showSnack(context, '请先配置 WebDAV。');
      await _editWebDavConfig(context, ref, settings);
      return;
    }

    final confirmed = await _confirmRestore(context, source: 'WebDAV');
    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      final result = await _runWithProgress<BackupRestoreResult>(
        context,
        message: '正在从 WebDAV 恢复...',
        task: () async {
          final tempDirectory = await getTemporaryDirectory();
          final backupFile = await ref
              .read(webDavBackupServiceProvider)
              .downloadLatestBackup(config, tempDirectory);
          return ref
              .read(backupServiceProvider)
              .restoreFromArchive(backupFile, currentSettings: settings);
        },
      );
      if (result == null || !context.mounted) {
        return;
      }
      await _applyRestoreResult(context, ref, result);
    } catch (error) {
      if (context.mounted) {
        _showSnack(context, _errorMessage(error));
      }
    }
  }

  Future<File> _fileFromPickedBackup(PlatformFile picked) async {
    final path = picked.path;
    if (path != null) {
      return File(path);
    }

    final bytes = picked.bytes;
    if (bytes == null) {
      throw const BackupException('无法读取备份文件。');
    }

    final tempDirectory = await getTemporaryDirectory();
    final file = File(p.join(tempDirectory.path, picked.name));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _applyRestoreResult(
    BuildContext context,
    WidgetRef ref,
    BackupRestoreResult result,
  ) async {
    await ref.read(settingsProvider.notifier).replaceWith(result.settings);
    await ref.read(imageListProvider.notifier).reload();
    await ref.read(favoriteFoldersProvider.notifier).reload();
    if (!context.mounted) {
      return;
    }

    _showSnack(context, '恢复完成。安全快照：${p.basename(result.safetyBackup.path)}');
    await _showBackupWarnings(context, result.warnings);
  }

  Future<bool?> _confirmSensitiveBackup(
    BuildContext context, {
    required String title,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: const Text(
            '备份会包含 API Key、WebDAV 密码等敏感配置。当前版本不会加密备份文件，请确认只保存到可信位置。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续'),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _confirmRestore(
    BuildContext context, {
    required String source,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('从$source恢复'),
          content: const Text('恢复会替换当前设置、历史记录、收藏夹和应用内图片文件。恢复前会自动生成一份安全快照。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认恢复'),
            ),
          ],
        );
      },
    );
  }

  Future<T?> _runWithProgress<T>(
    BuildContext context, {
    required String message,
    required Future<T> Function() task,
  }) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                const SizedBox(width: 14),
                Expanded(child: Text(message)),
              ],
            ),
          ),
        );
      },
    );

    try {
      return await task();
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _showBackupWarnings(
    BuildContext context,
    List<String> warnings,
  ) async {
    if (warnings.isEmpty || !context.mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('备份提示（${warnings.length}）'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Text(warnings.take(20).join('\n')),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorMessage(Object error) {
    if (error is BackupException) {
      return error.message;
    }
    if (error is WebDavBackupException) {
      return error.message;
    }
    return '操作失败：$error';
  }

  Future<void> _openRequestLogs(BuildContext context) async {
    if (_supportsDetachedLogWindow) {
      try {
        await Process.start(Platform.resolvedExecutable, const [
          '--log-window',
        ], mode: ProcessStartMode.detached);
        return;
      } catch (_) {
        // Fall back to in-app viewing when detached launch fails.
      }
    }

    if (!context.mounted) {
      return;
    }

    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RequestLogPage()));
  }

  bool get _supportsDetachedLogWindow =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;
}

class _AppInfoCard extends StatelessWidget {
  const _AppInfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(radius: 28),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppThemeTokens.surfaceSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.info_outline_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '关于 MintImage',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _InfoRow(
            icon: Icons.sell_outlined,
            label: '版本',
            value: AppVersion.current,
          ),
          const SizedBox(height: 10),
          _InfoRow(
            icon: Icons.code_rounded,
            label: '开源地址',
            value: AppVersion.repositoryUrl,
            onTap: () => _openRepository(context),
          ),
        ],
      ),
    );
  }

  Future<void> _openRepository(BuildContext context) async {
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(AppVersion.repositoryUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }

    if (!launched && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开 GitHub 地址。')));
    }
  }
}

class _DataBackupCard extends StatelessWidget {
  const _DataBackupCard({
    required this.webDavConfig,
    required this.onExportToFile,
    required this.onRestoreFromFile,
    required this.onEditWebDav,
    required this.onSyncToWebDav,
    required this.onRestoreFromWebDav,
  });

  final WebDavBackupConfig? webDavConfig;
  final VoidCallback onExportToFile;
  final VoidCallback onRestoreFromFile;
  final VoidCallback onEditWebDav;
  final VoidCallback onSyncToWebDav;
  final VoidCallback onRestoreFromWebDav;

  @override
  Widget build(BuildContext context) {
    final configured = webDavConfig?.isConfigured ?? false;
    final status = configured ? webDavConfig!.remoteDirectory : '未配置';

    return Container(
      decoration: AppDecorations.card(radius: 22),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppThemeTokens.surfaceSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.cloud_sync_rounded, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '数据备份与恢复',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'WebDAV：$status',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppThemeTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _BackupActionButton(
                icon: Icons.upload_file_rounded,
                label: '导出到文件',
                onPressed: onExportToFile,
              ),
              _BackupActionButton(
                icon: Icons.restore_page_rounded,
                label: '从文件恢复',
                onPressed: onRestoreFromFile,
              ),
              _BackupActionButton(
                icon: Icons.settings_input_component_rounded,
                label: 'WebDAV 设置',
                onPressed: onEditWebDav,
              ),
              _BackupActionButton(
                icon: Icons.cloud_upload_rounded,
                label: '同步到 WebDAV',
                onPressed: onSyncToWebDav,
              ),
              _BackupActionButton(
                icon: Icons.cloud_download_rounded,
                label: '从 WebDAV 恢复',
                onPressed: onRestoreFromWebDav,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BackupActionButton extends StatelessWidget {
  const _BackupActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        Icon(icon, size: 18, color: AppThemeTokens.primaryStrong),
        const SizedBox(width: 10),
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppThemeTokens.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: onTap == null
                  ? AppThemeTokens.textPrimary
                  : AppThemeTokens.primaryStrong,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 8),
          const Icon(
            Icons.open_in_new_rounded,
            size: 16,
            color: AppThemeTokens.primaryStrong,
          ),
        ],
      ],
    );

    if (onTap == null) {
      return content;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: content,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: AppThemeTokens.primaryStrong),
        const SizedBox(width: 7),
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppThemeTokens.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _AddConfigButton extends StatelessWidget {
  const _AddConfigButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppThemeTokens.surfaceSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppThemeTokens.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: AppThemeTokens.primaryStrong),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppThemeTokens.primaryStrong,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyConfigHint extends StatelessWidget {
  const _EmptyConfigHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeTokens.border),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppThemeTokens.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ImageProfileCard extends StatelessWidget {
  const _ImageProfileCard({
    required this.profile,
    required this.isActive,
    required this.onTap,
    required this.onEdit,
  });

  final ApiProfile profile;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final tint = isActive ? AppThemeTokens.surfaceSoft : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: AppDecorations.card(radius: 18, color: tint),
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      profile.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppThemeTokens.textPrimary,
                      ),
                    ),
                  ),
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: AppThemeTokens.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '使用中',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '编辑',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded, size: 19),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 34,
                      height: 34,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppThemeTokens.surfaceMuted,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      profile.apiMode.shortLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppThemeTokens.primaryStrong,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      profile.normalizedBaseUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppThemeTokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '模型：${profile.model}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromptOptimizationProfileCard extends StatelessWidget {
  const _PromptOptimizationProfileCard({
    required this.profile,
    required this.isActive,
    required this.onTap,
    required this.onEdit,
  });

  final PromptOptimizationProfile profile;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final tint = isActive ? AppThemeTokens.surfaceSoft : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: AppDecorations.card(radius: 18, color: tint),
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppThemeTokens.textPrimary,
                      ),
                    ),
                  ),
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: AppThemeTokens.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '使用中',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '编辑',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded, size: 19),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 34,
                      height: 34,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppThemeTokens.surfaceMuted,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      profile.protocol.label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppThemeTokens.primaryStrong,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      profile.normalizedBaseUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppThemeTokens.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '模型：${profile.model}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestTimeoutCard extends StatelessWidget {
  const _RequestTimeoutCard({
    required this.timeoutSeconds,
    required this.onEdit,
  });

  final int timeoutSeconds;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(radius: 22),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppThemeTokens.surfaceSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.timer_outlined, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Text(
                  '请求超时',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(width: 8),
                Text(
                  '$timeoutSeconds 秒',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppThemeTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonal(onPressed: onEdit, child: const Text('修改')),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(radius: 22),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppThemeTokens.surfaceSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
