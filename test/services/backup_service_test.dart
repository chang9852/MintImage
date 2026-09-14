import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mint_image/core/database/app_database.dart';
import 'package:mint_image/core/database/favorite_folder_dao.dart';
import 'package:mint_image/core/database/image_record_dao.dart';
import 'package:mint_image/core/models/favorite_folder.dart';
import 'package:mint_image/core/models/generation_request.dart';
import 'package:mint_image/core/models/image_record.dart';
import 'package:mint_image/core/models/settings_model.dart';
import 'package:mint_image/core/services/backup_service.dart';
import 'package:mint_image/core/services/data_directory_service.dart';
import 'package:mint_image/core/services/request_log_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  late Directory root;
  late PathProviderPlatform previousPathProvider;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mint_image_backup_test_');
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(root);
    // 数据库、图片与日志都落在数据目录下，先用假的 path_provider 解析出来。
    await DataDirectoryService.initialize();
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousPathProvider;
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('creates and restores a full backup archive', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    final imageDao = ImageRecordDao(database);
    final favoriteDao = FavoriteFolderDao(database);
    final requestLogs = await RequestLogService.load(reset: true);
    final service = BackupService(
      database: database,
      imageRecordDao: imageDao,
      favoriteFolderDao: favoriteDao,
      requestLogService: requestLogs,
    );

    final docs = Directory(p.join(root.path, 'documents'));
    final resultImage = File(
      p.join(docs.path, 'generated_images', 'record-1.png'),
    );
    await resultImage.parent.create(recursive: true);
    await resultImage.writeAsBytes([1, 2, 3], flush: true);
    final sourceImage = File(p.join(root.path, 'source.png'));
    await sourceImage.writeAsBytes([4, 5, 6], flush: true);

    final record = ImageRecord(
      id: 'record-1',
      prompt: 'city',
      apiProfileId: 'profile-1',
      sourceImagePath: sourceImage.path,
      sourceImagePaths: [sourceImage.path],
      resultImagePath: resultImage.path,
      resultImageUrl: null,
      resultB64: null,
      width: 1024,
      height: 1024,
      quality: ImageQuality.high.apiValue,
      outputFormat: ImageOutputFormat.png.apiValue,
      model: 'gpt-image-2',
      status: ImageRecordStatus.done,
      errorMessage: null,
      rawApiResponseValue: 'raw',
      createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      durationMs: 1200,
      usedSingleImageFallback: false,
      isFavorite: true,
    );
    await imageDao.upsert(record);
    await favoriteDao.replaceSnapshot(
      FavoriteFolderSnapshot(
        folders: [
          FavoriteFolder(
            id: defaultFavoriteFolderId,
            title: defaultFavoriteFolderTitle,
            isDefault: true,
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
          FavoriteFolder(
            id: 'folder-1',
            title: '灵感',
            isDefault: false,
            createdAt: DateTime.utc(2026, 1, 3),
          ),
        ],
        memberships: [
          FavoriteFolderMembership(
            folderId: 'folder-1',
            recordId: 'record-1',
            createdAt: DateTime.utc(2026, 1, 4),
          ),
        ],
      ),
    );
    await requestLogs.logInfo('hello', 'world');

    final settings = SettingsModel.initial().copyWith(
      profiles: [
        SettingsModel.initial().activeProfile.copyWith(
          id: 'profile-1',
          apiKey: 'secret',
        ),
      ],
      activeProfileId: 'profile-1',
      webDavBackupConfig: const WebDavBackupConfig(
        baseUrl: 'https://example.com/dav',
        username: 'user',
        password: 'pass',
        remoteDirectory: 'MintImage/backups',
      ),
    );

    final backup = await service.createBackupArchive(settings: settings);
    expect(await backup.file.exists(), isTrue);

    await imageDao.replaceAll(const []);
    await favoriteDao.replaceSnapshot(
      const FavoriteFolderSnapshot(folders: [], memberships: []),
    );
    await requestLogs.clear();

    final restored = await service.restoreFromArchive(
      backup.file,
      currentSettings: SettingsModel.initial(),
    );

    final records = await imageDao.loadAll();
    expect(records, hasLength(1));
    expect(records.single.id, 'record-1');
    expect(await File(records.single.resultImagePath!).readAsBytes(), [
      1,
      2,
      3,
    ]);
    expect(records.single.sourceImagePaths.single, isNot(sourceImage.path));
    expect(await File(records.single.sourceImagePaths.single).readAsBytes(), [
      4,
      5,
      6,
    ]);

    final favorites = await favoriteDao.loadSnapshot();
    expect(favorites.folders.map((folder) => folder.id), contains('folder-1'));
    expect(favorites.memberships, hasLength(1));
    expect(favorites.memberships.single.recordId, 'record-1');
    expect(requestLogs.entries.single.title, 'hello');
    expect(restored.settings.webDavBackupConfig?.password, 'pass');
    expect(await restored.safetyBackup.exists(), isTrue);
  });
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    return p.join(root.path, 'documents');
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return p.join(root.path, 'support');
  }

  @override
  Future<String?> getTemporaryPath() async {
    return p.join(root.path, 'temp');
  }
}
