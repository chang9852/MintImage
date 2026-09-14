import 'dart:convert';

import '../models/generation_request.dart';
import '../models/generation_result.dart';
import '../models/settings_model.dart';
import '../models/xai_imagine_params.dart';
import 'openai_client.dart';

/// Grok Imagine 文生图端点。
const String xaiImagineGenerationsPath = '/v1/images/generations';

/// Grok Imagine 图生图端点。
const String xaiImagineEditsPath = '/v1/images/edits';

/// xAI 官方图像接口的主机名。
const String xaiImagineOfficialHost = 'api.x.ai';

/// 单次请求最多携带的参考图数量，超出部分会被丢弃。
///
/// xAI 的多图编辑最多接受 3 张参考图。
const int xaiImagineMaxReferenceImages = 3;

/// 判断配置是否直连 xAI 官方端点。
bool isXaiImagineOfficialEndpoint(ApiProfile profile) {
  return isXaiImagineOfficialBaseUrl(profile.normalizedBaseUrl);
}

/// 判断 Base URL 是否指向 xAI 官方端点。
///
/// 只有直连官方端点时才发送 xAI 原生的 `aspect_ratio` 与 `resolution`。
/// 中转站（New API 等）把 Grok 图像模型暴露成 OpenAI 形状的接口，
/// 既不认识这两个参数，也需要 `size`，因此对非官方地址改用
/// OpenAI 兼容的请求体与 multipart 图生图表单。
bool isXaiImagineOfficialBaseUrl(String baseUrl) {
  final raw = baseUrl.trim().toLowerCase();
  if (raw.isEmpty) {
    return false;
  }

  // 允许只填主机名，缺少协议时按 https 补全后再解析。
  final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
  final host = uri?.host.toLowerCase() ?? '';
  return host == xaiImagineOfficialHost || host.endsWith('.x.ai');
}

/// 构造 Grok Imagine 文生图请求体。
///
/// 与 OpenAI 的 `/v1/images/generations` 不同，xAI 不接受像素尺寸与输出格式，
/// 只接受 `aspect_ratio` 加 `resolution`。
Map<String, dynamic> buildXaiImagineGenerateBody({
  required GenerationRequest request,
  required ApiProfile profile,
}) {
  return _buildXaiImagineBody(request: request, profile: profile);
}

/// 构造 Grok Imagine 图生图请求体。
///
/// [referenceDataUrls] 为参考图的 data URL 列表，超过 3 张时只取前 3 张。
/// 单张参考图使用 `image` 字段，多张参考图使用 `images` 字段。
Map<String, dynamic> buildXaiImagineEditBody({
  required GenerationRequest request,
  required ApiProfile profile,
  required List<String> referenceDataUrls,
}) {
  if (referenceDataUrls.isEmpty) {
    throw const ApiException('图生图请求缺少附件。');
  }

  final references = referenceDataUrls
      .take(xaiImagineMaxReferenceImages)
      .toList();
  final body = _buildXaiImagineBody(request: request, profile: profile);
  if (references.length == 1) {
    body['image'] = buildXaiImagineImageReference(references.first);
  } else {
    body['images'] = references.map(buildXaiImagineImageReference).toList();
  }
  return body;
}

/// 构造单张参考图的引用对象。
///
/// xAI 的 2.0 接口按 `{url}` 解析，而 1.x 与 OpenAI 风格按 `{type, url}` 解析，
/// 这里同时给出两个字段以兼容两种校验。
Map<String, dynamic> buildXaiImagineImageReference(String dataUrl) {
  return <String, dynamic>{'type': 'image_url', 'url': dataUrl};
}

/// 解析 Grok Imagine 的响应体。
///
/// xAI 返回的是 OpenAI Images 兼容结构 `{data: [{b64_json} | {url}]}`；
/// 请求时已指定 `response_format: b64_json`，这里仍兼容 `url` 以便排查问题。
List<GenerationResult> parseXaiImagineResults(Map<String, dynamic> response) {
  final payload = response['data'];
  if (payload is! List) {
    throw const ApiException('接口响应缺少图片数据。');
  }

  return payload.map((item) {
    final map = Map<String, dynamic>.from(item as Map);
    final b64Json = map['b64_json'] as String?;
    final imageUrl = map['url'] as String?;
    return GenerationResult(
      b64Json: b64Json,
      imageUrl: imageUrl,
      rawResponseValue: b64Json ?? imageUrl,
      fileExtension: xaiImagineFileExtension(b64Json),
    );
  }).toList();
}

/// 依据图片头字节推断真实图片格式对应的扩展名。
///
/// 解码 base64 的前 16 个字符得到 12 个字节，足以覆盖
/// PNG / JPEG / WebP / GIF 的魔数。无法识别时返回 null。
String? xaiImagineFileExtension(String? b64Json) {
  final value = (b64Json ?? '').trim();
  if (value.length < 16) {
    return null;
  }

  final head = _decodeBase64Head(value);
  if (head == null) {
    return null;
  }

  if (_startsWith(head, const [0x89, 0x50, 0x4E, 0x47])) {
    return 'png';
  }
  if (_startsWith(head, const [0xFF, 0xD8, 0xFF])) {
    return 'jpg';
  }
  if (head.length >= 12 &&
      _startsWith(head, const [0x52, 0x49, 0x46, 0x46]) &&
      head[8] == 0x57 &&
      head[9] == 0x45 &&
      head[10] == 0x42 &&
      head[11] == 0x50) {
    return 'webp';
  }
  if (_startsWith(head, const [0x47, 0x49, 0x46])) {
    return 'gif';
  }

  return null;
}

/// 解码 base64 字符串的前 16 个字符（即前 12 个字节）。
List<int>? _decodeBase64Head(String value) {
  try {
    return base64Decode(value.substring(0, 16));
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _buildXaiImagineBody({
  required GenerationRequest request,
  required ApiProfile profile,
}) {
  final width = request.resolvedWidth;
  final height = request.resolvedHeight;
  return <String, dynamic>{
    'model': profile.model,
    'prompt': request.prompt,
    'n': 1,
    'resolution': xaiImagineResolutionFor(width, height).apiValue,
    if (xaiImagineSupportsQuality(profile.model))
      'quality': xaiImagineQualityValue(request.quality),
    'response_format': 'b64_json',
    'aspect_ratio': xaiImagineAspectRatioFor(width, height),
  };
}

bool _startsWith(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) {
    return false;
  }
  for (var index = 0; index < prefix.length; index++) {
    if (bytes[index] != prefix[index]) {
      return false;
    }
  }
  return true;
}
