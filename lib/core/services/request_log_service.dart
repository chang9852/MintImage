import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'data_directory_service.dart';

enum RequestLogLevel { info, request, response, error }

class RequestLogEntry {
  const RequestLogEntry({
    required this.timestamp,
    required this.level,
    required this.title,
    required this.details,
  });

  final DateTime timestamp;
  final RequestLogLevel level;
  final String title;
  final String details;

  factory RequestLogEntry.fromJson(Map<String, dynamic> json) {
    return RequestLogEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      level: RequestLogLevel.values.firstWhere(
        (item) => item.name == json['level'],
        orElse: () => RequestLogLevel.info,
      ),
      title: json['title'] as String? ?? '',
      details: json['details'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'title': title,
      'details': details,
    };
  }
}

class RequestLogService extends ChangeNotifier {
  RequestLogService._(this._file);

  static const int _maxEntries = 1000;

  final File _file;
  final List<RequestLogEntry> _entries = <RequestLogEntry>[];
  Future<void> _writeQueue = Future<void>.value();

  List<RequestLogEntry> get entries => List.unmodifiable(_entries);

  String get filePath => _file.path;

  static Future<RequestLogService> load({bool reset = false}) async {
    // 日志与数据库、图片一起放在数据目录下，跟随用户的目录设置。
    final file = File(DataDirectoryService.requestLogFilePath);
    await file.parent.create(recursive: true);

    final service = RequestLogService._(file);
    if (reset) {
      await service.clear();
      return service;
    }
    await service.reload();
    return service;
  }

  Future<void> clear() async {
    _entries.clear();
    await _file.writeAsString('', flush: true);
    notifyListeners();
  }

  Future<void> reload() async {
    if (!await _file.exists()) {
      _entries.clear();
      notifyListeners();
      return;
    }

    final lines = await _file.readAsLines();
    final parsed = <RequestLogEntry>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      try {
        final jsonMap = jsonDecode(trimmed);
        if (jsonMap is Map) {
          parsed.add(
            RequestLogEntry.fromJson(Map<String, dynamic>.from(jsonMap)),
          );
        }
      } catch (_) {
        continue;
      }
    }

    _entries
      ..clear()
      ..addAll(_trimEntries(parsed));
    notifyListeners();
  }

  Future<void> logInfo(String title, String details) {
    return _append(
      RequestLogEntry(
        timestamp: DateTime.now(),
        level: RequestLogLevel.info,
        title: title,
        details: details,
      ),
    );
  }

  Future<void> logRequest(String title, String details) {
    return _append(
      RequestLogEntry(
        timestamp: DateTime.now(),
        level: RequestLogLevel.request,
        title: title,
        details: details,
      ),
    );
  }

  Future<void> logResponse(String title, String details) {
    return _append(
      RequestLogEntry(
        timestamp: DateTime.now(),
        level: RequestLogLevel.response,
        title: title,
        details: details,
      ),
    );
  }

  Future<void> logError(String title, String details) {
    return _append(
      RequestLogEntry(
        timestamp: DateTime.now(),
        level: RequestLogLevel.error,
        title: title,
        details: details,
      ),
    );
  }

  Future<void> _append(RequestLogEntry entry) async {
    _entries.add(entry);
    _trimEntriesInPlace();
    notifyListeners();

    _writeQueue = _writeQueue
        .then((_) async {
          await _file.writeAsString(
            '${jsonEncode(entry.toJson())}\n',
            mode: FileMode.append,
            flush: true,
          );
        })
        .catchError((_) {});

    await _writeQueue;
  }

  List<RequestLogEntry> _trimEntries(List<RequestLogEntry> entries) {
    if (entries.length <= _maxEntries) {
      return entries;
    }

    return entries.sublist(entries.length - _maxEntries);
  }

  void _trimEntriesInPlace() {
    if (_entries.length <= _maxEntries) {
      return;
    }

    _entries.removeRange(0, _entries.length - _maxEntries);
  }
}
