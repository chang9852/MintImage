import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../database/favorite_folder_dao.dart';
import '../database/image_record_dao.dart';
import '../models/favorite_folder.dart';
import '../models/generation_request.dart';
import '../models/image_record.dart';
import '../models/settings_model.dart';
import '../version/app_version.dart';
import 'data_directory_service.dart';
import 'request_log_service.dart';

const _backupFormat = 'mint_image_backup';
const _backupFormatVersion = 1;
const _manifestPath = 'manifest.json';
const _settingsPath = 'settings.json';
const _imageRecordsPath = 'database/image_records.json';
const _favoriteFoldersPath = 'database/favorite_folders.json';
const _favoriteFolderItemsPath = 'database/favorite_folder_items.json';
const _requestLogsPath = 'request_logs.jsonl';

class BackupArchiveResult {
  const BackupArchiveResult({
    required this.file,
    required this.fileName,
    required this.warnings,
  });

  final File file;
  final String fileName;
  final List<String> warnings;
}

class BackupRestoreResult {
  const BackupRestoreResult({
    required this.settings,
    required this.safetyBackup,
    required this.warnings,
  });

  final SettingsModel settings;
  final File safetyBackup;
  final List<String> warnings;
}

class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BackupService {
  const BackupService({
    required AppDatabase database,
    required ImageRecordDao imageRecordDao,
    required FavoriteFolderDao favoriteFolderDao,
    required RequestLogService requestLogService,
  }) : _database = database,
       _imageRecordDao = imageRecordDao,
       _favoriteFolderDao = favoriteFolderDao,
       _requestLogService = requestLogService;

  final AppDatabase _database;
  final ImageRecordDao _imageRecordDao;
  final FavoriteFolderDao _favoriteFolderDao;
  final RequestLogService _requestLogService;

  Future<BackupArchiveResult> createBackupArchive({
    required SettingsModel settings,
  }) async {
    final records = await _imageRecordDao.loadAll();
    final favorites = await _favoriteFolderDao.loadSnapshot();
    final archive = Archive();
    final warnings = <String>[];
    final recordFiles = <String, Map<String, dynamic>>{};

    void addString(String name, String content) {
      archive.addFile(ArchiveFile.string(name, content));
    }

    Future<String?> addFileIfExists({
      required File source,
      required String archivePath,
      required String warningLabel,
    }) async {
      if (!await source.exists()) {
        warnings.add('$warningLabel 文件不存在：${source.path}');
        return null;
      }

      final bytes = await source.readAsBytes();
      archive.addFile(ArchiveFile.bytes(archivePath, bytes));
      return archivePath;
    }

    for (final record in records) {
      final fileRef = <String, dynamic>{};
      final resultPath = record.resultImagePath;
      if (resultPath != null && resultPath.isNotEmpty) {
        final source = File(resultPath);
        final archivePath =
            'files/generated_images/'
            '${_safeFileStem(record.id)}${_extensionOrDefault(resultPath)}';
        final added = await addFileIfExists(
          source: source,
          archivePath: archivePath,
          warningLabel: '生成结果 ${record.id}',
        );
        if (added != null) {
          fileRef['resultImage'] = added;
        }
      }

      final sourceArchivePaths = <String>[];
      final attachmentPaths = record.sourceAttachmentPaths;
      for (var index = 0; index < attachmentPaths.length; index++) {
        final sourcePath = attachmentPaths[index];
        if (sourcePath.isEmpty) {
          continue;
        }
        final source = File(sourcePath);
        final archivePath =
            'files/source_attachments/${_safeFileStem(record.id)}/'
            '$index${_extensionOrDefault(sourcePath)}';
        final added = await addFileIfExists(
          source: source,
          archivePath: archivePath,
          warningLabel: '源附件 ${record.id} #${index + 1}',
        );
        if (added != null) {
          sourceArchivePaths.add(added);
        }
      }
      if (sourceArchivePaths.isNotEmpty) {
        fileRef['sourceImages'] = sourceArchivePaths;
      }
      if (fileRef.isNotEmpty) {
        recordFiles[record.id] = fileRef;
      }
    }

    final manifest = {
      'format': _backupFormat,
      'formatVersion': _backupFormatVersion,
      'appVersion': AppVersion.current,
      'createdAt': DateTime.now().toIso8601String(),
      'databaseSchemaVersion': _database.schemaVersion,
      'recordCount': records.length,
      'favoriteFolderCount': favorites.folders.length,
      'favoriteMembershipCount': favorites.memberships.length,
      'recordFiles': recordFiles,
      'warnings': warnings,
    };

    addString(_manifestPath, _prettyJson(manifest));
    addString(_settingsPath, _prettyJson(settings.toJson()));
    addString(
      _imageRecordsPath,
      _prettyJson(records.map(_imageRecordToJson).toList()),
    );
    addString(
      _favoriteFoldersPath,
      _prettyJson(favorites.folders.map(_favoriteFolderToJson).toList()),
    );
    addString(
      _favoriteFolderItemsPath,
      _prettyJson(
        favorites.memberships.map(_favoriteFolderMembershipToJson).toList(),
      ),
    );

    final requestLogFile = File(_requestLogService.filePath);
    if (await requestLogFile.exists()) {
      archive.addFile(
        ArchiveFile.bytes(_requestLogsPath, await requestLogFile.readAsBytes()),
      );
    }

    final bytes = ZipEncoder().encode(archive);

    final tempDirectory = await getTemporaryDirectory();
    final backupDirectory = Directory(
      p.join(tempDirectory.path, 'mint_image_backups'),
    );
    await backupDirectory.create(recursive: true);
    final fileName =
        'mint_image_backup_${_timestampForFileName(DateTime.now())}'
        '.mintbackup';
    final file = File(p.join(backupDirectory.path, fileName));
    await file.writeAsBytes(bytes, flush: true);

    return BackupArchiveResult(
      file: file,
      fileName: fileName,
      warnings: List.unmodifiable(warnings),
    );
  }

  Future<BackupRestoreResult> restoreFromArchive(
    File archiveFile, {
    required SettingsModel currentSettings,
  }) async {
    if (!await archiveFile.exists()) {
      throw const BackupException('备份文件不存在。');
    }

    final archive = ZipDecoder().decodeBytes(await archiveFile.readAsBytes());
    final manifest = _readJsonMap(archive, _manifestPath);
    if (manifest['format'] != _backupFormat) {
      throw const BackupException('这不是 MintImage 备份文件。');
    }
    if (manifest['formatVersion'] != _backupFormatVersion) {
      throw const BackupException('备份格式版本不支持。');
    }

    final warnings = [
      for (final item in _readList(manifest['warnings']))
        if (item is String) item,
    ];

    final safetyBackup = (await createBackupArchive(
      settings: currentSettings,
    )).file;
    final settings = SettingsModel.fromJson(
      _readJsonMap(archive, _settingsPath),
    );
    final recordFiles = _readRecordFiles(manifest['recordFiles']);
    await _prepareRestoreFileDirectories();
    final records = <ImageRecord>[];
    final recordItems = _readJsonList(archive, _imageRecordsPath);
    for (final item in recordItems) {
      if (item is! Map) {
        continue;
      }
      final record = _imageRecordFromJson(Map<String, dynamic>.from(item));
      records.add(
        await _rewriteRecordPaths(archive, record, recordFiles[record.id]),
      );
    }

    final folders = _readJsonList(archive, _favoriteFoldersPath)
        .whereType<Map>()
        .map((item) => _favoriteFolderFromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    final memberships = _readJsonList(archive, _favoriteFolderItemsPath)
        .whereType<Map>()
        .map(
          (item) => _favoriteFolderMembershipFromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);

    await _database.transaction(() async {
      await _favoriteFolderDao.replaceSnapshot(
        const FavoriteFolderSnapshot(folders: [], memberships: []),
      );
      await _imageRecordDao.replaceAll(records);
      await _favoriteFolderDao.replaceSnapshot(
        FavoriteFolderSnapshot(folders: folders, memberships: memberships),
      );
    });

    final requestLogs = archive.findFile(_requestLogsPath);
    if (requestLogs != null && requestLogs.isFile) {
      await File(
        _requestLogService.filePath,
      ).writeAsBytes(requestLogs.readBytes() ?? Uint8List(0), flush: true);
      await _requestLogService.reload();
    } else {
      await File(_requestLogService.filePath).writeAsString('', flush: true);
      await _requestLogService.reload();
    }

    return BackupRestoreResult(
      settings: settings,
      safetyBackup: safetyBackup,
      warnings: List.unmodifiable(warnings),
    );
  }

  Future<ImageRecord> _rewriteRecordPaths(
    Archive archive,
    ImageRecord record,
    Map<String, dynamic>? refs,
  ) async {
    final resultArchivePath = refs?['resultImage'] as String?;
    final resultPath = resultArchivePath == null
        ? null
        : await _extractArchiveFile(
            archive,
            resultArchivePath,
            await _generatedImageDestination(resultArchivePath),
          );

    final sourcePaths = <String>[];
    final sourceRefs = _readList(refs?['sourceImages']).whereType<String>();
    for (final sourceRef in sourceRefs) {
      final extracted = await _extractArchiveFile(
        archive,
        sourceRef,
        await _sourceAttachmentDestination(record.id, sourceRef),
      );
      if (extracted != null) {
        sourcePaths.add(extracted);
      }
    }

    return record.copyWith(
      sourceImagePath: sourcePaths.isEmpty ? null : sourcePaths.first,
      sourceImagePaths: sourcePaths,
      resultImagePath: resultPath,
      clearSourceImagePath: sourcePaths.isEmpty,
      clearResultImagePath: resultPath == null,
    );
  }

  Future<String?> _extractArchiveFile(
    Archive archive,
    String archivePath,
    File destination,
  ) async {
    final entry = archive.findFile(archivePath);
    if (entry == null || !entry.isFile) {
      return null;
    }

    final bytes = entry.readBytes();
    if (bytes == null) {
      return null;
    }

    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(bytes, flush: true);
    return destination.path;
  }

  Future<File> _generatedImageDestination(String archivePath) async {
    // 恢复的图片写回数据目录的 images/，与正常生成的图片放在一起。
    return File(
      p.join(DataDirectoryService.imagesDirectoryPath, p.basename(archivePath)),
    );
  }

  /// 恢复的参考图暂存目录。
  ///
  /// 放在 images/ 之下，使数据目录顶层保持 images、database、logs 三个文件夹。
  String get _restoredAttachmentDirectoryPath => p.join(
    DataDirectoryService.imagesDirectoryPath,
    'restored_source_attachments',
  );

  Future<void> _prepareRestoreFileDirectories() async {
    // 恢复会整份替换数据，这里先清掉旧的图片与参考图，避免残留。
    for (final path in [
      DataDirectoryService.imagesDirectoryPath,
      _restoredAttachmentDirectoryPath,
    ]) {
      final target = Directory(path);
      if (await target.exists()) {
        await target.delete(recursive: true);
      }
    }
  }

  Future<File> _sourceAttachmentDestination(
    String recordId,
    String archivePath,
  ) async {
    return File(
      p.join(
        _restoredAttachmentDirectoryPath,
        _safeFileStem(recordId),
        p.basename(archivePath),
      ),
    );
  }

  Map<String, dynamic> _readJsonMap(Archive archive, String path) {
    final file = archive.findFile(path);
    if (file == null || !file.isFile) {
      throw BackupException('备份文件缺少 $path。');
    }

    final bytes = file.readBytes();
    if (bytes == null) {
      throw BackupException('无法读取 $path。');
    }

    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw BackupException('$path 格式不正确。');
    }
    return Map<String, dynamic>.from(decoded);
  }

  List<dynamic> _readJsonList(Archive archive, String path) {
    final file = archive.findFile(path);
    if (file == null || !file.isFile) {
      return const [];
    }

    final bytes = file.readBytes();
    if (bytes == null) {
      return const [];
    }

    final decoded = jsonDecode(utf8.decode(bytes));
    return decoded is List ? decoded : const [];
  }

  Map<String, Map<String, dynamic>> _readRecordFiles(Object? rawValue) {
    if (rawValue is! Map) {
      return const {};
    }

    return {
      for (final entry in rawValue.entries)
        if (entry.key is String && entry.value is Map)
          entry.key as String: Map<String, dynamic>.from(entry.value as Map),
    };
  }
}

Map<String, dynamic> _imageRecordToJson(ImageRecord record) {
  return {
    'id': record.id,
    'prompt': record.prompt,
    'apiProfileId': record.apiProfileId,
    'sourceImagePath': record.sourceImagePath,
    'sourceImagePaths': record.sourceImagePaths,
    'resultImagePath': record.resultImagePath,
    'resultImageUrl': record.resultImageUrl,
    'resultB64': record.resultB64,
    'width': record.width,
    'height': record.height,
    'quality': record.quality,
    'outputFormat': record.outputFormat,
    'model': record.model,
    'status': record.status.storageValue,
    'errorMessage': record.errorMessage,
    'rawApiResponseValue': record.rawApiResponseValue,
    'createdAt': record.createdAt.toIso8601String(),
    'durationMs': record.durationMs,
    'usedSingleImageFallback': record.usedSingleImageFallback,
    'isFavorite': record.isFavorite,
  };
}

ImageRecord _imageRecordFromJson(Map<String, dynamic> json) {
  return ImageRecord(
    id: json['id'] as String,
    prompt: json['prompt'] as String? ?? '',
    apiProfileId: json['apiProfileId'] as String? ?? '',
    sourceImagePath: json['sourceImagePath'] as String?,
    sourceImagePaths: _readList(
      json['sourceImagePaths'],
    ).whereType<String>().toList(),
    resultImagePath: json['resultImagePath'] as String?,
    resultImageUrl: json['resultImageUrl'] as String?,
    resultB64: json['resultB64'] as String?,
    width: _readInt(json['width']),
    height: _readInt(json['height']),
    quality: json['quality'] as String? ?? ImageQuality.auto.apiValue,
    outputFormat:
        json['outputFormat'] as String? ?? ImageOutputFormat.png.apiValue,
    model: json['model'] as String? ?? '',
    status: ImageRecordStatus.fromStorageValue(json['status'] as String? ?? ''),
    errorMessage: json['errorMessage'] as String?,
    rawApiResponseValue: json['rawApiResponseValue'] as String?,
    createdAt: _readDateTime(json['createdAt']),
    durationMs: _readNullableInt(json['durationMs']),
    usedSingleImageFallback: _readBool(json['usedSingleImageFallback']),
    isFavorite: _readBool(json['isFavorite']),
  );
}

Map<String, dynamic> _favoriteFolderToJson(FavoriteFolder folder) {
  return {
    'id': folder.id,
    'title': folder.title,
    'isDefault': folder.isDefault,
    'createdAt': folder.createdAt.toIso8601String(),
  };
}

FavoriteFolder _favoriteFolderFromJson(Map<String, dynamic> json) {
  return FavoriteFolder(
    id: json['id'] as String,
    title: json['title'] as String? ?? defaultFavoriteFolderTitle,
    isDefault: _readBool(json['isDefault']),
    createdAt: _readDateTime(json['createdAt']),
  );
}

Map<String, dynamic> _favoriteFolderMembershipToJson(
  FavoriteFolderMembership membership,
) {
  return {
    'folderId': membership.folderId,
    'recordId': membership.recordId,
    'createdAt': membership.createdAt.toIso8601String(),
  };
}

FavoriteFolderMembership _favoriteFolderMembershipFromJson(
  Map<String, dynamic> json,
) {
  return FavoriteFolderMembership(
    folderId: json['folderId'] as String,
    recordId: json['recordId'] as String,
    createdAt: _readDateTime(json['createdAt']),
  );
}

String _prettyJson(Object? value) {
  return const JsonEncoder.withIndent('  ').convert(value);
}

List<dynamic> _readList(Object? value) {
  return value is List ? value : const [];
}

int _readInt(Object? value) {
  return _readNullableInt(value) ?? 0;
}

int? _readNullableInt(Object? value) {
  return switch (value) {
    int item => item,
    num item => item.toInt(),
    String item => int.tryParse(item),
    _ => null,
  };
}

bool _readBool(Object? value) {
  return switch (value) {
    bool item => item,
    num item => item != 0,
    String item => item == 'true',
    _ => false,
  };
}

DateTime _readDateTime(Object? value) {
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

String _extensionOrDefault(String filePath) {
  final extension = p.extension(filePath);
  return extension.isEmpty ? '.png' : extension;
}

String _safeFileStem(String value) {
  return value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
}

String _timestampForFileName(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}${two(value.month)}${two(value.day)}_'
      '${two(value.hour)}${two(value.minute)}${two(value.second)}';
}
