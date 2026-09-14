import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mint_image/core/services/data_directory_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('未初始化时读取数据目录会抛错', () {
    // 数据目录必须在启动阶段解析完成，避免各服务拿到不确定的路径。
    expect(() => DataDirectoryService.directoryPath, throwsStateError);
  });

  group('DataDirectoryService.isUsable', () {
    test('可创建且可写入的目录返回 true', () async {
      final directory = await Directory.systemTemp.createTemp('mint_data');
      addTearDown(() => directory.delete(recursive: true));

      // 不存在的子目录也会被创建，便于用户直接填一个还没建的路径。
      expect(
        await DataDirectoryService.isUsable(p.join(directory.path, 'nested')),
        isTrue,
      );
    });

    test('空路径返回 false', () async {
      expect(await DataDirectoryService.isUsable('   '), isFalse);
    });
  });

  group('DataDirectoryService.copyDirectoryContents', () {
    test('递归复制文件，且不覆盖目标已存在的同名文件', () async {
      final root = await Directory.systemTemp.createTemp('mint_copy');
      addTearDown(() => root.delete(recursive: true));

      final source = Directory(p.join(root.path, 'source'));
      final target = Directory(p.join(root.path, 'target'));
      await File(
        p.join(source.path, 'root.txt'),
      ).create(recursive: true).then((file) => file.writeAsString('root'));
      await File(
        p.join(source.path, 'database', 'mint_image.sqlite'),
      ).create(recursive: true).then((file) => file.writeAsString('new'));

      // 目标目录里已有一份数据库，迁移时必须保留它。
      await File(
        p.join(target.path, 'database', 'mint_image.sqlite'),
      ).create(recursive: true).then((file) => file.writeAsString('keep'));

      await DataDirectoryService.copyDirectoryContents(
        from: source.path,
        to: target.path,
      );

      expect(
        await File(p.join(target.path, 'root.txt')).readAsString(),
        'root',
      );
      expect(
        await File(
          p.join(target.path, 'database', 'mint_image.sqlite'),
        ).readAsString(),
        'keep',
      );
    });

    test('来源目录不存在时安静返回', () async {
      final root = await Directory.systemTemp.createTemp('mint_copy_absent');
      addTearDown(() => root.delete(recursive: true));

      await DataDirectoryService.copyDirectoryContents(
        from: p.join(root.path, 'missing'),
        to: p.join(root.path, 'target'),
      );

      expect(await Directory(p.join(root.path, 'target')).exists(), isFalse);
    });
  });
}
