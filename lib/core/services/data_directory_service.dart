import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 数据目录的解析结果。
class DataLocation {
  const DataLocation({
    required this.directory,
    this.pendingMigrationFrom,
    this.legacyImagesConsolidated = false,
  });

  /// 当前生效的数据目录（绝对路径）。
  final String directory;

  /// 待迁移的旧数据目录，下一次启动时把其中的数据复制过来。
  final String? pendingMigrationFrom;

  /// 是否已执行过「把文档目录里的旧图片合并进数据目录」这一次性迁移。
  final bool legacyImagesConsolidated;
}

/// 本地数据目录的解析、切换与迁移。
///
/// 数据目录下固定分为三个子目录，三类数据各放一处：
///
/// ```
/// <数据目录>/
/// ├── images/     生成结果图片
/// ├── database/   SQLite 数据库
/// └── logs/       请求日志
/// ```
///
/// 默认使用系统的应用数据目录，用户可以在设置里改成 D 盘等自定义位置。
/// 自定义位置记录在系统默认目录下的一个小指针文件里：数据搬走之后，
/// 应用启动时必须先知道自己该去哪里找数据，因此这份指针不能放进数据目录。
class DataDirectoryService {
  DataDirectoryService._();

  static const String pointerFileName = 'data_location.json';
  static const String imagesDirName = 'images';
  static const String databaseDirName = 'database';
  static const String logsDirName = 'logs';

  static const String databaseFileName = 'mint_image.sqlite';
  static const String requestLogFileName = 'mint_image_request_logs.jsonl';

  /// 更早版本使用的数据库文件名，仍在数据目录根下时需要搬进 database/。
  static const String legacyDatabaseFileName = 'gpt_image_flutter.sqlite';

  static DataLocation? _current;

  /// 当前生效的数据目录，启动阶段解析完成后可同步读取。
  static DataLocation get current {
    final location = _current;
    if (location == null) {
      throw StateError('数据目录尚未初始化，请先调用 DataDirectoryService.initialize()。');
    }
    return location;
  }

  /// 数据目录绝对路径。
  static String get directoryPath => current.directory;

  /// 生成图片目录绝对路径。
  static String get imagesDirectoryPath =>
      p.join(current.directory, imagesDirName);

  /// 数据库文件绝对路径。
  static String get databaseFilePath =>
      p.join(current.directory, databaseDirName, databaseFileName);

  /// 请求日志文件绝对路径。
  static String get requestLogFilePath =>
      p.join(current.directory, logsDirName, requestLogFileName);

  /// 系统默认数据目录。
  static Future<String> defaultDirectoryPath() async {
    final directory = await getApplicationSupportDirectory();
    return p.normalize(directory.path);
  }

  /// 解析数据目录，建好三个子目录，并完成历史数据的搬迁。
  ///
  /// 解析顺序：指针文件中的自定义目录（需可用）→ 系统默认目录。
  /// 自定义目录不可用（比如 D 盘被拔掉）时回落到默认目录，
  /// 保证应用仍能启动，同时把指针改回默认，避免每次启动都重试。
  static Future<DataLocation> initialize() async {
    final defaultPath = await defaultDirectoryPath();
    final pointer = await _readPointer();
    final consolidated = pointer['legacyImagesConsolidated'] == true;

    var directoryPath = defaultPath;
    final customPath = (pointer['dataDirectory'] as String?)?.trim() ?? '';
    if (customPath.isNotEmpty) {
      if (await isUsable(customPath)) {
        directoryPath = p.normalize(customPath);
      } else {
        await _writePointer(
          dataDirectory: null,
          legacyImagesConsolidated: consolidated,
        );
      }
    }

    var location = DataLocation(
      directory: directoryPath,
      pendingMigrationFrom: (pointer['migrateFrom'] as String?)?.trim(),
      legacyImagesConsolidated: consolidated,
    );

    final migrateFrom = location.pendingMigrationFrom;
    if (migrateFrom != null &&
        migrateFrom.isNotEmpty &&
        p.normalize(migrateFrom) != directoryPath) {
      // 此刻数据库尚未打开，是复制数据库文件最安全的时机。
      await copyDirectoryContents(from: migrateFrom, to: directoryPath);
      await _writePointer(
        dataDirectory: directoryPath == defaultPath ? null : directoryPath,
        legacyImagesConsolidated: consolidated,
      );
      location = DataLocation(
        directory: directoryPath,
        legacyImagesConsolidated: consolidated,
      );
    }

    await _ensureSubdirectories(directoryPath);
    // 旧版本把数据库与日志直接放在数据目录根下，这里搬进各自的子目录。
    await _adoptLegacyRootFiles(directoryPath);

    _current = location;
    return location;
  }

  /// 判断目录是否可用：能创建、能写入。
  static Future<bool> isUsable(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    try {
      final directory = Directory(trimmed);
      await directory.create(recursive: true);
      final probe = File(p.join(directory.path, '.mint_image_write_probe'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 请求把数据目录切换到 [path]，传 null 表示恢复默认目录。
  ///
  /// 这里只写指针文件，真正的搬运留到下次启动、数据库尚未打开时执行，
  /// 避免在数据库打开的状态下复制数据库文件而得到损坏的副本。
  static Future<void> switchTo(String? path) async {
    final defaultPath = await defaultDirectoryPath();
    final source = current.directory;
    final trimmed = (path ?? '').trim();
    final target = trimmed.isEmpty ? defaultPath : p.normalize(trimmed);

    await _writePointer(
      dataDirectory: target == defaultPath ? null : target,
      migrateFrom: target == source ? null : source,
      legacyImagesConsolidated: current.legacyImagesConsolidated,
    );
  }

  /// 标记「旧图片合并」已完成，避免每次启动重复扫描。
  static Future<void> markLegacyImagesConsolidated() async {
    final location = current;
    final defaultPath = await defaultDirectoryPath();
    await _writePointer(
      dataDirectory: location.directory == defaultPath
          ? null
          : location.directory,
      legacyImagesConsolidated: true,
    );
    _current = DataLocation(
      directory: location.directory,
      legacyImagesConsolidated: true,
    );
  }

  /// 把 [from] 下的所有文件复制到 [to]，已存在的文件不覆盖。
  ///
  /// 只复制不删除：迁移失败或用户反悔时原数据仍在原处。
  static Future<void> copyDirectoryContents({
    required String from,
    required String to,
  }) async {
    final source = Directory(from);
    if (!await source.exists()) {
      return;
    }

    final target = Directory(to);
    await target.create(recursive: true);

    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      final relative = p.relative(entity.path, from: from);
      final destination = File(p.join(target.path, relative));
      if (await destination.exists()) {
        continue;
      }
      await destination.parent.create(recursive: true);
      await entity.copy(destination.path);
    }
  }

  static Future<void> _ensureSubdirectories(String directoryPath) async {
    for (final name in const [imagesDirName, databaseDirName, logsDirName]) {
      try {
        await Directory(p.join(directoryPath, name)).create(recursive: true);
      } catch (_) {
        // 单个子目录建不出来时不阻断启动，后续写入时会再次尝试。
      }
    }
  }

  /// 把旧版本遗留在数据目录根下的数据库与日志搬进各自的子目录。
  ///
  /// 只复制不删除，原文件保留一份，用户确认无误后可自行清理。
  static Future<void> _adoptLegacyRootFiles(String directoryPath) async {
    for (final legacyName in const [
      databaseFileName,
      legacyDatabaseFileName,
    ]) {
      await _copyFileIfMissing(
        source: p.join(directoryPath, legacyName),
        target: p.join(directoryPath, databaseDirName, databaseFileName),
        sidecarSuffixes: const ['-wal', '-shm'],
      );
    }

    await _copyFileIfMissing(
      source: p.join(directoryPath, requestLogFileName),
      target: p.join(directoryPath, logsDirName, requestLogFileName),
    );
  }

  /// 目标不存在时，把 [source]（及其 sidecar）复制到 [target]。
  static Future<void> _copyFileIfMissing({
    required String source,
    required String target,
    List<String> sidecarSuffixes = const [],
  }) async {
    try {
      final sourceFile = File(source);
      final targetFile = File(target);
      if (await sourceFile.exists() && !await targetFile.exists()) {
        await targetFile.parent.create(recursive: true);
        await sourceFile.copy(target);
      }

      for (final suffix in sidecarSuffixes) {
        final from = File('$source$suffix');
        final to = File('$target$suffix');
        if (await from.exists() && !await to.exists()) {
          await to.parent.create(recursive: true);
          await from.copy(to.path);
        }
      }
    } catch (_) {
      // 搬迁失败不阻断启动，最坏情况是这次没带上历史数据。
    }
  }

  static Future<File> _pointerFile() async {
    final defaultPath = await defaultDirectoryPath();
    return File(p.join(defaultPath, pointerFileName));
  }

  static Future<Map<String, dynamic>> _readPointer() async {
    try {
      final file = await _pointerFile();
      if (!await file.exists()) {
        return <String, dynamic>{};
      }
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      // 指针文件损坏时按默认目录启动，不阻断应用。
      return <String, dynamic>{};
    }
  }

  static Future<void> _writePointer({
    required String? dataDirectory,
    String? migrateFrom,
    required bool legacyImagesConsolidated,
  }) async {
    try {
      final file = await _pointerFile();
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
          'dataDirectory': dataDirectory,
          if (migrateFrom != null) 'migrateFrom': migrateFrom,
          'legacyImagesConsolidated': legacyImagesConsolidated,
        }),
        flush: true,
      );
    } catch (_) {
      // 写指针失败只影响下次启动的选择，不影响本次运行。
    }
  }
}
