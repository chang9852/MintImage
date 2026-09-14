import 'package:dio/dio.dart';

import '../models/generation_request.dart';
import '../models/generation_result.dart';
import '../models/settings_model.dart';
import '../models/xai_imagine_params.dart';
import '../services/request_log_service.dart';
import 'openai_client.dart';
import 'responses_image_api.dart';
import 'xai_imagine_api.dart';

class ImageGenerationApi {
  const ImageGenerationApi({this.requestLogService});

  final RequestLogService? requestLogService;

  Future<List<GenerationResult>> generate(
    GenerationRequest request,
    ApiProfile profile, {
    String? responseFormat,
    required int timeoutSeconds,
    CancelToken? cancelToken,
  }) async {
    final client = OpenAiClient(
      profile,
      timeoutSeconds: timeoutSeconds,
      requestLogService: requestLogService,
    );

    // Grok Imagine 直连 api.x.ai 时使用 xAI 原生参数；
    // 指向中转站时继续走下面的 OpenAI 兼容请求体。
    if (profile.apiMode.isXaiImagine && isXaiImagineOfficialEndpoint(profile)) {
      // xAI 接受宽高比加分辨率，不接受像素尺寸、质量与输出格式，
      // 也没有流式响应，因此这里单独构造请求体。
      final body = buildXaiImagineGenerateBody(
        request: request,
        profile: profile,
      );
      final response = await client.postJson(
        xaiImagineGenerationsPath,
        body,
        cancelToken: cancelToken,
      );
      return parseXaiImagineResults(response);
    }

    if (profile.apiMode == ImageGenerationApiMode.responses) {
      final body = buildResponsesImageBody(
        request: request,
        profile: profile,
        input: request.prompt,
        action: 'generate',
      );
      final response = profile.useStreaming
          ? await client.postJsonStreaming(
              '/v1/responses',
              body,
              cancelToken: cancelToken,
            )
          : await client.postJson(
              '/v1/responses',
              body,
              cancelToken: cancelToken,
            );
      return parseResponsesImageResults(response);
    }

    // Grok 系列只接受 low/medium（且仅 2.0 支持该参数），也不接受输出格式，
    // 因此这两个字段按模型能力决定是否下发，避免被上游判定为非法参数。
    final isXaiRelay = profile.apiMode.isXaiImagine;
    final isXaiModel = isXaiImagineModelId(profile.model);
    final quality = resolveImageQualityValue(
      model: profile.model,
      quality: request.quality,
    );
    final body = <String, dynamic>{
      'model': profile.model,
      'prompt': request.prompt,
      'n': 1,
      if (quality != null) 'quality': quality,
      if (!isXaiModel) 'output_format': request.outputFormat.apiValue,
    };
    if (isXaiModel) {
      // 中转站的 Grok 渠道只接受一组固定的尺寸标记，
      // 其他像素尺寸会被拒绝（返回「aspect_ratio 不受支持」）。
      final relaySize = xaiImagineRelaySizeFor(
        request.resolvedWidth,
        request.resolvedHeight,
      );
      if (relaySize != null) {
        body['size'] = relaySize;
      }
    } else if (request.apiSize != null) {
      body['size'] = request.apiSize;
    }
    if (isXaiModel) {
      // 与实测可用的 Grok 请求体保持一致：
      // 只带 model / prompt / n / size / response_format。
      body['response_format'] = xaiImagineCompatResponseFormat;
    } else if (responseFormat != null && responseFormat.trim().isNotEmpty) {
      // GPT Image 2/2.5 and RightAPI reject the legacy response_format field.
      if (!_isGptImage2Family(profile.model) && !_isRightApiDraw(profile)) {
        body['response_format'] = responseFormat;
      }
    }

    if (_isRightApiDraw(profile)) {
      if (_isGptImage25Family(profile.model)) {
        // RightAPI currently interprets `size` as an aspect-ratio token for
        // the 2.5 channels. Those channels require the separate imageSize
        // selector instead (1K/2K/4K).
        body.remove('size');
        body['imageSize'] = _rightApiImageSize(request);
      }
      body['async'] = true;
      return _submitAndPollRightApi(
        client,
        body,
        timeoutSeconds: timeoutSeconds,
        cancelToken: cancelToken,
      );
    }

    final response = profile.useStreaming
        ? await client.postJsonStreaming(
            '/v1/images/generations',
            body,
            cancelToken: cancelToken,
            isImagesApi: true,
          )
        : await client.postJson(
            '/v1/images/generations',
            body,
            cancelToken: cancelToken,
          );

    // Grok 系列不下发输出格式，落盘扩展名改由响应头字节推断。
    return (isXaiRelay || isXaiModel)
        ? parseXaiImagineResults(response)
        : _parseResults(response);
  }

  bool _isRightApiDraw(ApiProfile profile) {
    final uri = Uri.tryParse(profile.normalizedBaseUrl);
    return uri != null &&
        uri.host.toLowerCase() == 'www.rightapi.ai' &&
        uri.path.toLowerCase().endsWith('/draw');
  }

  bool _isGptImage2Family(String model) {
    final value = model.trim().toLowerCase();
    return value == 'gpt-image-2' || value.startsWith('gpt-image-2.5-');
  }

  bool _isGptImage25Family(String model) {
    return model.trim().toLowerCase().startsWith('gpt-image-2.5-');
  }

  String _rightApiImageSize(GenerationRequest request) {
    final longestEdge = request.resolvedWidth > request.resolvedHeight
        ? request.resolvedWidth
        : request.resolvedHeight;
    if (longestEdge <= 1024) {
      return '1K';
    }
    if (longestEdge <= 2048) {
      return '2K';
    }
    return '4K';
  }

  Future<List<GenerationResult>> _submitAndPollRightApi(
    OpenAiClient client,
    Map<String, dynamic> body, {
    required int timeoutSeconds,
    CancelToken? cancelToken,
  }) async {
    final submitted = await client.postJson(
      '/v1/images/generations',
      body,
      cancelToken: cancelToken,
    );
    final taskId = submitted['task_id'];
    if (taskId is! String || taskId.trim().isEmpty) {
      // Some deployments return a synchronous Images response despite async=true.
      if (submitted['data'] is List) {
        return _parseResults(submitted);
      }
      throw const ApiException('RightAPI 异步提交未返回 task_id。');
    }

    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final task = await client.getJson(
        _rightApiTaskPath(taskId),
        cancelToken: cancelToken,
      );
      // RightAPI returns the final Images payload without a status field.
      if (task['data'] is List) {
        return _parseResults(task);
      }
      final status = task['status']?.toString().toLowerCase();
      if (status == 'completed') {
        return _parseResults(task);
      }
      if (status == 'failed' || status == 'cancelled') {
        throw ApiException(_rightApiTaskError(task));
      }
    }
    throw const ApiException('RightAPI 异步任务轮询超时。');
  }

  String _rightApiTaskPath(String taskId) {
    // OpenAiClient's base URL is /draw; task lookup is site-level, so use an
    // absolute URL understood by Dio.
    return 'https://www.rightapi.ai/v1/tasks/${Uri.encodeComponent(taskId)}';
  }

  String _rightApiTaskError(Map<String, dynamic> task) {
    final error = task['error'];
    if (error is Map && error['message'] is String) {
      return 'RightAPI 任务失败：${error['message']}';
    }
    return 'RightAPI 任务失败。';
  }

  List<GenerationResult> _parseResults(Map<String, dynamic> response) {
    final payload = response['data'];
    if (payload is! List) {
      throw const ApiException('接口响应缺少图片数据。');
    }

    return payload.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      final rawResponseValue =
          map['b64_json'] as String? ?? map['url'] as String?;
      return GenerationResult(
        b64Json: map['b64_json'] as String?,
        imageUrl: map['url'] as String?,
        rawResponseValue: rawResponseValue,
      );
    }).toList();
  }
}
