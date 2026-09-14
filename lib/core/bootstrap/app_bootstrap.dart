import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../database/favorite_folder_dao.dart';
import '../database/image_record_dao.dart';
import '../models/image_record.dart';
import '../models/settings_model.dart';
import '../providers/settings_provider.dart';
import '../services/data_directory_service.dart';

class AppBootstrap {
  AppBootstrap({
    required this.database,
    required this.imageRecordDao,
    required this.favoriteFolderDao,
    required this.sharedPreferences,
    required this.initialSettings,
    required this.initialRecords,
    required this.initialFavoriteFolderSnapshot,
  });

  final AppDatabase database;
  final ImageRecordDao imageRecordDao;
  final FavoriteFolderDao favoriteFolderDao;
  final SharedPreferences sharedPreferences;
  final SettingsModel initialSettings;
  final List<ImageRecord> initialRecords;
  final FavoriteFolderSnapshot initialFavoriteFolderSnapshot;

  static Future<AppBootstrap> load() async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final database = AppDatabase();
    final imageRecordDao = ImageRecordDao(database);
    final favoriteFolderDao = FavoriteFolderDao(database);
    await favoriteFolderDao.ensureDefaultFolderAndMigrateLegacyFavorites();
    // 历史版本的生成图片放在系统文档目录，这里合并进数据目录的 images/，
    // 并把记录里的路径一并改写，使所有数据集中在数据目录下。
    await _consolidateLegacyImages(imageRecordDao);

    return AppBootstrap(
      database: database,
      imageRecordDao: imageRecordDao,
      favoriteFolderDao: favoriteFolderDao,
      sharedPreferences: sharedPreferences,
      initialSettings: SettingsController.loadFromPreferences(
        sharedPreferences,
      ),
      initialRecords: await _loadRecoveredRecords(imageRecordDao),
      initialFavoriteFolderSnapshot: await favoriteFolderDao.loadSnapshot(),
    );
  }

  static Future<List<ImageRecord>> _loadRecoveredRecords(
    ImageRecordDao imageRecordDao,
  ) async {
    final storedRecords = await imageRecordDao.loadAll();
    var hasRecoveredRecords = false;
    final recoveredRecords = <ImageRecord>[];

    for (final record in storedRecords) {
      final recoveredRecord = record.recoverInterruptedGeneration();
      if (!identical(recoveredRecord, record)) {
        hasRecoveredRecords = true;
      }
      recoveredRecords.add(recoveredRecord);
    }

    if (hasRecoveredRecords) {
      await imageRecordDao.upsertAll(recoveredRecords);
    }

    return recoveredRecords;
  }

  /// 把历史版本遗留在「文档/generated_images」里的生成图片合并进数据目录。
  ///
  /// 早期版本把图片放在系统文档目录，数据库里存的是绝对路径；
  /// 这里把文件复制到 `<数据目录>/images/` 并改写记录路径，
  /// 使图片、数据库与日志集中在一处。只复制不删除，原文件保留。
  ///
  /// 迁移失败时不会打标记，下次启动会重试。
  static Future<void> _consolidateLegacyImages(
    ImageRecordDao imageRecordDao,
  ) async {
    if (DataDirectoryService.current.legacyImagesConsolidated) {
      return;
    }

    try {
      final documents = await getApplicationDocumentsDirectory();
      final legacyDirectory = p.normalize(
        p.join(documents.path, 'generated_images'),
      );
      final targetDirectory = p.normalize(
        DataDirectoryService.imagesDirectoryPath,
      );

      if (legacyDirectory != targetDirectory &&
          await Directory(legacyDirectory).exists()) {
        final replacements = <String, String>{};
        for (final record in await imageRecordDao.loadAll()) {
          final currentPath = record.resultImagePath;
          if (currentPath == null ||
              currentPath.isEmpty ||
              !p.isWithin(legacyDirectory, currentPath)) {
            continue;
          }

          final destination = p.join(targetDirectory, p.basename(currentPath));
          final targetFile = File(destination);
          final sourceFile = File(currentPath);

          if (await targetFile.exists()) {
            replacements[currentPath] = destination;
            continue;
          }
          if (!await sourceFile.exists()) {
            continue;
          }

          await targetFile.parent.create(recursive: true);
          await sourceFile.copy(destination);
          replacements[currentPath] = destination;
        }

        await imageRecordDao.updateResultImagePaths(replacements);
      }

      await DataDirectoryService.markLegacyImagesConsolidated();
    } catch (_) {
      // 合并失败不影响启动：历史图片留在原处，记录路径也保持不变。
    }
  }
}
