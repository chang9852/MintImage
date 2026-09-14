import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mint_image/core/api/openai_client.dart';
import 'package:mint_image/core/api/prompt_optimization_api.dart';
import 'package:mint_image/core/models/generation_request.dart';
import 'package:mint_image/core/models/image_record.dart';
import 'package:mint_image/core/models/settings_model.dart';
import 'package:mint_image/core/providers/app_providers.dart';
import 'package:mint_image/core/providers/settings_provider.dart';
import 'package:mint_image/features/input/bottom_input_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('keeps prompt input and submit button at 40px', (tester) async {
    await _pumpInputBar(tester);

    final inputFinder = find.byKey(const Key('prompt-input'));
    final submitFinder = find.byKey(const Key('submit-generation-button'));
    final optimizeFinder = find.byKey(const Key('prompt-optimize-button'));

    expect(tester.getSize(inputFinder).height, moreOrLessEquals(40));
    expect(tester.getSize(submitFinder), const Size(40, 40));
    expect(
      tester.getRect(optimizeFinder).center.dy,
      moreOrLessEquals(tester.getRect(inputFinder).center.dy),
    );
  });

  testWidgets('shows clickable stop loading state while optimizing', (
    tester,
  ) async {
    final api = _BlockingPromptOptimizationApi();
    await _pumpInputBar(tester, promptOptimizationApi: api);

    await tester.enterText(find.byKey(const Key('prompt-input')), '一只白猫');
    await tester.tap(find.byKey(const Key('prompt-optimize-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('强化'));
    for (var i = 0; i < 20 && !api.started.isCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(api.started.isCompleted, isTrue);
    await tester.pump();

    expect(
      find.byKey(const Key('prompt-optimization-spinner')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('prompt-optimization-stop-square')),
      findsOneWidget,
    );
    expect(find.byTooltip('停止优化'), findsOneWidget);

    await tester.tap(find.byKey(const Key('prompt-optimize-button')));
    await api.cancelled.future;
    await tester.pump();

    expect(api.cancelled.isCompleted, isTrue);
    expect(find.byKey(const Key('prompt-optimization-spinner')), findsNothing);
    expect(find.byTooltip('优化提示词'), findsOneWidget);
  });

  testWidgets('uses last selected generation options from settings', (
    tester,
  ) async {
    GenerationRequest? submittedRequest;
    await _pumpInputBar(
      tester,
      settings: _settings.copyWith(
        lastSizePreset: SizePreset.posterLandscape,
        lastCustomWidth: 1536,
        lastCustomHeight: 1024,
        lastQuality: ImageQuality.high,
        lastOutputFormat: ImageOutputFormat.webp,
      ),
      onSubmit: (request) async {
        submittedRequest = request;
      },
    );

    expect(find.text('1536×1024'), findsOneWidget);
    expect(find.text('高'), findsOneWidget);
    expect(find.text('WEBP'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('prompt-input')), '山谷日出');
    await tester.tap(find.byKey(const Key('submit-generation-button')));
    await tester.pump();

    expect(submittedRequest, isNotNull);
    expect(submittedRequest!.sizePreset, SizePreset.posterLandscape);
    expect(submittedRequest!.customWidth, 1536);
    expect(submittedRequest!.customHeight, 1024);
    expect(submittedRequest!.quality, ImageQuality.high);
    expect(submittedRequest!.outputFormat, ImageOutputFormat.webp);
  });

  testWidgets('shift enter inserts newline without submitting', (tester) async {
    GenerationRequest? submittedRequest;
    await _pumpInputBar(
      tester,
      onSubmit: (request) async {
        submittedRequest = request;
      },
    );

    final inputFinder = find.byKey(const Key('prompt-input'));
    await tester.tap(inputFinder);
    await tester.enterText(inputFinder, '第一行');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    final input = tester.widget<TextField>(inputFinder);
    expect(input.controller!.text, '第一行\n');
    expect(submittedRequest, isNull);
  });

  testWidgets('prefill from record reuses size quality and format', (
    tester,
  ) async {
    final inputBarKey = GlobalKey<BottomInputBarState>();
    GenerationRequest? submittedRequest;
    await _pumpInputBar(
      tester,
      inputBarKey: inputBarKey,
      onSubmit: (request) async {
        submittedRequest = request;
      },
    );

    await inputBarKey.currentState!.prefillFromRecord(_webpRecord);
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit-generation-button')));
    await tester.pump();

    expect(submittedRequest, isNotNull);
    expect(submittedRequest!.prompt, '湖边木屋');
    expect(submittedRequest!.sizePreset, SizePreset.wide2k);
    expect(submittedRequest!.customWidth, 2560);
    expect(submittedRequest!.customHeight, 1440);
    expect(submittedRequest!.quality, ImageQuality.medium);
    expect(submittedRequest!.outputFormat, ImageOutputFormat.webp);
  });

  testWidgets('shows inline api source switcher and can change profile', (
    tester,
  ) async {
    await _pumpInputBar(tester, settings: _settingsWithTwoProfiles);

    expect(find.byTooltip('切换生图 API'), findsOneWidget);
    expect(find.text('API'), findsOneWidget);

    await tester.tap(find.byTooltip('切换生图 API'));
    await tester.pumpAndSettle();

    expect(find.text('备用'), findsOneWidget);

    await tester.tap(find.text('备用'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BottomInputBar)),
    );
    expect(container.read(settingsProvider).activeProfileId, 'api-2');
  });

  testWidgets('long pressing send switches api profile and submits', (
    tester,
  ) async {
    GenerationRequest? submittedRequest;
    await _pumpInputBar(
      tester,
      settings: _settingsWithThreeProfiles,
      onSubmit: (request) async {
        submittedRequest = request;
      },
    );

    await tester.enterText(find.byKey(const Key('prompt-input')), '山谷日出');
    await tester.longPress(find.byKey(const Key('submit-generation-button')));
    await tester.pumpAndSettle();

    expect(find.text('切换到API配置并发送'), findsOneWidget);
    expect(find.text('备用'), findsOneWidget);
    expect(find.text('第三'), findsOneWidget);

    await tester.tap(find.text('备用'));
    await tester.pumpAndSettle();

    expect(submittedRequest, isNotNull);
    expect(submittedRequest!.apiProfileId, 'api-2');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BottomInputBar)),
    );
    expect(container.read(settingsProvider).activeProfileId, 'api-2');
  });

  testWidgets('生图模型面板按协议分组，切换后两套选择互不影响', (tester) async {
    await _pumpInputBar(tester, settings: _settingsWithImageAndGrokProfiles);

    // 当前使用 Image 配置，模型按钮展示其模型名。
    expect(
      tester.widget<Text>(find.byKey(const Key('image-model-chip-label'))).data,
      'gpt-image-2',
    );

    await tester.tap(find.byTooltip('切换生图模型'));
    await tester.pumpAndSettle();

    expect(find.text('Image（OpenAI 图像）'), findsOneWidget);
    expect(find.text('Grok Imagine'), findsOneWidget);
    expect(find.text('grok-imagine-image-2.0'), findsOneWidget);

    await tester.tap(find.text('grok-imagine-image-2.0'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BottomInputBar)),
    );
    final settings = container.read(settingsProvider);
    expect(settings.activeProfileId, 'api-grok');
    expect(settings.activeProfile.model, 'grok-imagine-image-2.0');
    // Image 配置的模型名保持原样，两个协议的选择互不影响。
    expect(settings.profileById('api')!.model, 'gpt-image-2');
    expect(
      tester.widget<Text>(find.byKey(const Key('image-model-chip-label'))).data,
      'grok-imagine-image-2.0',
    );
  });
}

Future<void> _pumpInputBar(
  WidgetTester tester, {
  PromptOptimizationApi? promptOptimizationApi,
  SettingsModel settings = _settings,
  GlobalKey<BottomInputBarState>? inputBarKey,
  Future<void> Function(GenerationRequest request)? onSubmit,
}) async {
  SharedPreferences.setMockInitialValues(const {});
  final preferences = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        initialSettingsModelProvider.overrideWithValue(settings),
        promptOptimizationApiProvider.overrideWithValue(
          promptOptimizationApi ?? const PromptOptimizationApi(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 420,
              child: BottomInputBar(
                key: inputBarKey,
                onSubmit: onSubmit ?? (request) async {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

const _apiProfile = ApiProfile(
  id: 'api',
  name: 'API',
  baseUrl: 'https://api.openai.com',
  apiKey: 'test-key',
  model: 'gpt-image-2',
);

const _promptOptimizationProfile = PromptOptimizationProfile(
  id: 'optimizer',
  name: 'Optimizer',
  baseUrl: 'https://api.openai.com',
  apiKey: 'test-key',
  model: 'gpt-5.5',
  protocol: PromptOptimizationProtocol.openAiResponses,
);

const _settings = SettingsModel(
  profiles: [_apiProfile],
  activeProfileId: 'api',
  promptOptimizationProfiles: [_promptOptimizationProfile],
  activePromptOptimizationProfileId: 'optimizer',
);

const _settingsWithTwoProfiles = SettingsModel(
  profiles: [_apiProfile, _apiProfile2],
  activeProfileId: 'api',
  promptOptimizationProfiles: [_promptOptimizationProfile],
  activePromptOptimizationProfileId: 'optimizer',
);

const _settingsWithThreeProfiles = SettingsModel(
  profiles: [_apiProfile, _apiProfile2, _apiProfile3],
  activeProfileId: 'api',
  promptOptimizationProfiles: [_promptOptimizationProfile],
  activePromptOptimizationProfileId: 'optimizer',
);

const _apiProfile2 = ApiProfile(
  id: 'api-2',
  name: '备用',
  baseUrl: 'https://api.openai.com',
  apiKey: 'test-key-2',
  model: 'gpt-image-2',
);

const _apiProfile3 = ApiProfile(
  id: 'api-3',
  name: '第三',
  baseUrl: 'https://api.openai.com',
  apiKey: 'test-key-3',
  model: 'gpt-image-2',
);

const _xaiProfile = ApiProfile(
  id: 'api-grok',
  name: 'Grok',
  baseUrl: 'https://api.x.ai',
  apiKey: 'test-key-grok',
  model: 'grok-imagine-image-2.0',
  apiMode: ImageGenerationApiMode.xaiImagine,
);

const _settingsWithImageAndGrokProfiles = SettingsModel(
  profiles: [_apiProfile, _xaiProfile],
  activeProfileId: 'api',
  promptOptimizationProfiles: [_promptOptimizationProfile],
  activePromptOptimizationProfileId: 'optimizer',
);

final _webpRecord = ImageRecord(
  id: 'record-webp',
  prompt: '湖边木屋',
  apiProfileId: 'api',
  sourceImagePath: null,
  sourceImagePaths: const [],
  resultImagePath: null,
  resultImageUrl: null,
  resultB64: null,
  width: 2560,
  height: 1440,
  quality: 'medium',
  outputFormat: 'webp',
  model: 'gpt-image-2',
  status: ImageRecordStatus.done,
  errorMessage: null,
  rawApiResponseValue: null,
  createdAt: DateTime(2026, 5, 30, 12),
  durationMs: 1200,
  usedSingleImageFallback: false,
  isFavorite: false,
);

class _BlockingPromptOptimizationApi extends PromptOptimizationApi {
  _BlockingPromptOptimizationApi();

  final Completer<void> started = Completer<void>();
  final Completer<void> cancelled = Completer<void>();
  final Completer<String> _response = Completer<String>();

  @override
  Future<String> optimize({
    required String prompt,
    required PromptOptimizationDirection direction,
    required PromptOptimizationProfile profile,
    required int timeoutSeconds,
    CancelToken? cancelToken,
  }) {
    if (!started.isCompleted) {
      started.complete();
    }

    cancelToken?.whenCancel.then((_) {
      if (!cancelled.isCompleted) {
        cancelled.complete();
      }
      if (!_response.isCompleted) {
        _response.completeError(const ApiException('请求已取消。'));
      }
    });

    return _response.future;
  }
}
