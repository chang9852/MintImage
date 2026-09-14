import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mint_image/core/api/image_edit_api.dart';
import 'package:mint_image/core/api/image_generation_api.dart';
import 'package:mint_image/core/api/openai_client.dart';
import 'package:mint_image/core/api/xai_imagine_api.dart';
import 'package:mint_image/core/models/generation_request.dart';
import 'package:mint_image/core/models/settings_model.dart';

/// 一组足够长的图片头字节，便于按魔数推断格式。
final String _pngBase64 = base64Encode(
  <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x00],
);
final String _jpegBase64 = base64Encode(
  <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
);
final String _webpBase64 = base64Encode(
  <int>[0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50],
);
final String _gifBase64 = base64Encode(
  <int>[0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
);

void main() {
  group('buildXaiImagineGenerateBody', () {
    test('发送宽高比与分辨率，不发送像素尺寸与输出格式', () {
      final body = buildXaiImagineGenerateBody(
        request: _request(
          sizePreset: SizePreset.custom,
          customWidth: 1024,
          customHeight: 576,
          quality: ImageQuality.low,
        ),
        profile: _profile(model: 'grok-imagine-image-2.0'),
      );

      expect(body['model'], 'grok-imagine-image-2.0');
      expect(body['prompt'], 'a red apple');
      expect(body['n'], 1);
      expect(body['aspect_ratio'], '16:9');
      expect(body['resolution'], '1k');
      expect(body['quality'], 'low');
      expect(body['response_format'], 'b64_json');
      expect(body.containsKey('size'), isFalse);
      expect(body.containsKey('output_format'), isFalse);
    });

    test('自动尺寸传 auto 且分辨率回落 1K', () {
      final body = buildXaiImagineGenerateBody(
        request: _request(sizePreset: SizePreset.auto),
        profile: _profile(model: 'grok-imagine-image-2.0'),
      );

      expect(body['aspect_ratio'], 'auto');
      expect(body['resolution'], '1k');
    });

    test('4K 预设收敛到 2K', () {
      final body = buildXaiImagineGenerateBody(
        request: _request(sizePreset: SizePreset.wide4k),
        profile: _profile(model: 'grok-imagine-image-2.0'),
      );

      expect(body['aspect_ratio'], '16:9');
      expect(body['resolution'], '2k');
    });

    test('2.0 之前的型号不发送 quality', () {
      for (final model in const [
        'grok-imagine-image',
        'grok-imagine-image-quality',
      ]) {
        final body = buildXaiImagineGenerateBody(
          request: _request(),
          profile: _profile(model: model),
        );
        expect(body.containsKey('quality'), isFalse, reason: model);
      }
    });

    test('高清档回落到 medium', () {
      final body = buildXaiImagineGenerateBody(
        request: _request(quality: ImageQuality.high),
        profile: _profile(model: 'grok-imagine-image-2.0'),
      );

      expect(body['quality'], 'medium');
    });
  });

  group('buildXaiImagineEditBody', () {
    test('单张参考图使用 image 字段并带 type 与 url', () {
      final body = buildXaiImagineEditBody(
        request: _request(imagePaths: const ['a.png']),
        profile: _profile(model: 'grok-imagine-image-2.0'),
        referenceDataUrls: const ['data:image/png;base64,AAAA'],
      );

      final image = body['image'];
      expect(image, isA<Map<String, dynamic>>());
      expect((image as Map)['type'], 'image_url');
      expect(image['url'], 'data:image/png;base64,AAAA');
      expect(body.containsKey('images'), isFalse);
      expect(body['aspect_ratio'], '1:1');
    });

    test('多张参考图使用 images 字段', () {
      final body = buildXaiImagineEditBody(
        request: _request(imagePaths: const ['a.png', 'b.png', 'c.png']),
        profile: _profile(model: 'grok-imagine-image-2.0'),
        referenceDataUrls: const [
          'data:image/png;base64,AAAA',
          'data:image/png;base64,BBBB',
          'data:image/png;base64,CCCC',
        ],
      );

      final images = body['images'];
      expect(images, isA<List<dynamic>>());
      expect(images as List<dynamic>, hasLength(3));
      expect(body.containsKey('image'), isFalse);
    });

    test('超过 3 张参考图时只取前 3 张', () {
      final body = buildXaiImagineEditBody(
        request: _request(
          imagePaths: const ['a.png', 'b.png', 'c.png', 'd.png', 'e.png'],
        ),
        profile: _profile(model: 'grok-imagine-image-2.0'),
        referenceDataUrls: const [
          'data:image/png;base64,AAAA',
          'data:image/png;base64,BBBB',
          'data:image/png;base64,CCCC',
          'data:image/png;base64,DDDD',
          'data:image/png;base64,EEEE',
        ],
      );

      final images = body['images'] as List<dynamic>;
      expect(images, hasLength(xaiImagineMaxReferenceImages));
      expect((images.last as Map)['url'], 'data:image/png;base64,CCCC');
    });

    test('缺少参考图时抛出 ApiException', () {
      expect(
        () => buildXaiImagineEditBody(
          request: _request(),
          profile: _profile(model: 'grok-imagine-image-2.0'),
          referenceDataUrls: const [],
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('xaiImagineFileExtension', () {
    test('按魔数识别常见格式', () {
      expect(xaiImagineFileExtension(_pngBase64), 'png');
      expect(xaiImagineFileExtension(_jpegBase64), 'jpg');
      expect(xaiImagineFileExtension(_webpBase64), 'webp');
      expect(xaiImagineFileExtension(_gifBase64), 'gif');
    });

    test('无法识别或数据过短时返回 null', () {
      expect(xaiImagineFileExtension(null), isNull);
      expect(xaiImagineFileExtension(''), isNull);
      expect(xaiImagineFileExtension('AAAA'), isNull);
      expect(xaiImagineFileExtension(base64Encode(const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])), isNull);
    });
  });

  group('parseXaiImagineResults', () {
    test('解析 b64_json 并推断格式', () {
      final results = parseXaiImagineResults({
        'data': [
          {'b64_json': _pngBase64},
        ],
      });

      expect(results, hasLength(1));
      expect(results.single.b64Json, _pngBase64);
      expect(results.single.fileExtension, 'png');
      expect(results.single.rawResponseValue, _pngBase64);
    });

    test('兼容 url 形式的响应', () {
      final results = parseXaiImagineResults({
        'data': [
          {'url': 'https://files-cdn.x.ai/abc.png'},
        ],
      });

      expect(results.single.b64Json, isNull);
      expect(results.single.imageUrl, 'https://files-cdn.x.ai/abc.png');
      expect(results.single.fileExtension, isNull);
    });

    test('缺少 data 时抛出 ApiException', () {
      expect(
        () => parseXaiImagineResults(<String, dynamic>{'error': 'boom'}),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('isXaiImagineOfficialBaseUrl', () {
    test('识别 xAI 官方端点', () {
      expect(isXaiImagineOfficialBaseUrl('https://api.x.ai'), isTrue);
      expect(isXaiImagineOfficialBaseUrl('https://api.x.ai/'), isTrue);
      expect(isXaiImagineOfficialBaseUrl('api.x.ai'), isTrue);
      expect(isXaiImagineOfficialBaseUrl('https://API.X.AI'), isTrue);
    });

    test('中转站等非官方地址返回 false', () {
      expect(isXaiImagineOfficialBaseUrl('https://api.catcat.top'), isFalse);
      expect(isXaiImagineOfficialBaseUrl('https://example.com/xai'), isFalse);
      expect(isXaiImagineOfficialBaseUrl(''), isFalse);
    });
  });

  group('ImageGenerationApi (Grok Imagine 经中转站)', () {
    test('改用 OpenAI 兼容格式：发 size，不发 xAI 原生参数', () async {
      final server = await _startServer((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/v1/images/generations');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer test-key',
        );

        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;

        expect(body['model'], 'grok-imagine-image-2.0');
        expect(body['prompt'], 'a red apple');
        expect(body['n'], 1);
        expect(body['size'], '1536x1024');
        // 中转站不认识 xAI 原生参数，也不接受质量与输出格式。
        expect(body.containsKey('aspect_ratio'), isFalse);
        expect(body.containsKey('resolution'), isFalse);
        expect(body.containsKey('quality'), isFalse);
        expect(body.containsKey('output_format'), isFalse);

        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {'b64_json': _pngBase64},
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final results = await const ImageGenerationApi().generate(
        _request(sizePreset: SizePreset.posterLandscape),
        _profileFor(server),
        timeoutSeconds: 30,
      );

      expect(results, hasLength(1));
      expect(results.single.b64Json, _pngBase64);
      expect(results.single.fileExtension, 'png');
    });
  });

  group('ImageEditApi (Grok Imagine 经中转站)', () {
    test('改用 multipart 表单上传参考图，不发质量与输出格式', () async {
      final directory = await Directory.systemTemp.createTemp('mint_xai');
      addTearDown(() => directory.delete(recursive: true));
      final imageFile = File('${directory.path}/input.png');
      await imageFile.writeAsBytes(
        <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      );

      final server = await _startServer((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/v1/images/edits');
        expect(
          request.headers.contentType?.mimeType,
          contains('multipart/form-data'),
        );

        final payload = utf8.decode(
          await _collectBytes(request),
          allowMalformed: true,
        );
        expect(payload, contains('name="model"'));
        expect(payload, contains('grok-imagine-image-2.0'));
        expect(payload, contains('name="image[]"'));
        expect(payload, contains('name="size"'));
        expect(payload, contains('1024x1024'));
        // 中转站上的 Grok 模型不接受质量与输出格式。
        expect(payload, isNot(contains('name="quality"')));
        expect(payload, isNot(contains('name="output_format"')));

        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {'b64_json': _jpegBase64},
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final results = await const ImageEditApi().edit(
        _request(imagePaths: [imageFile.path]),
        _profileFor(server),
        timeoutSeconds: 30,
      );

      expect(results, hasLength(1));
      expect(results.single.fileExtension, 'jpg');
    });
  });

  group('Grok 模型走 OpenAI 兼容协议时的质量与格式字段', () {
    test('自动质量映射为 medium，且不下发输出格式与 response_format', () async {
      final body = await _captureGenerateBody(
        request: _request(quality: ImageQuality.auto),
        model: 'grok-imagine-image-2.0',
        apiMode: ImageGenerationApiMode.images,
        responseFormat: 'url',
      );

      expect(body['model'], 'grok-imagine-image-2.0');
      expect(body['quality'], 'medium');
      expect(body['size'], '1024x1024');
      expect(body.containsKey('output_format'), isFalse);
      expect(body.containsKey('response_format'), isFalse);
    });

    test('高清档回落到 medium，低档透传 low', () async {
      final high = await _captureGenerateBody(
        request: _request(quality: ImageQuality.high),
        model: 'grok-imagine-image-2.0',
        apiMode: ImageGenerationApiMode.images,
      );
      expect(high['quality'], 'medium');

      final low = await _captureGenerateBody(
        request: _request(quality: ImageQuality.low),
        model: 'grok-imagine-image-2.0',
        apiMode: ImageGenerationApiMode.images,
      );
      expect(low['quality'], 'low');
    });

    test('2.0 之前的 Grok 型号不下发 quality', () async {
      final body = await _captureGenerateBody(
        request: _request(quality: ImageQuality.medium),
        model: 'grok-imagine-image-lite',
        apiMode: ImageGenerationApiMode.images,
      );

      expect(body.containsKey('quality'), isFalse);
    });

    test('非 Grok 模型仍按原样发送质量与输出格式', () async {
      final body = await _captureGenerateBody(
        request: _request(quality: ImageQuality.high),
        model: 'gpt-image-2.5-flare',
        apiMode: ImageGenerationApiMode.images,
      );

      expect(body['quality'], 'high');
      expect(body['output_format'], 'png');
    });
  });
}

/// 用给定的请求与配置发起一次生图，并返回服务端实际收到的请求体。
Future<Map<String, dynamic>> _captureGenerateBody({
  required GenerationRequest request,
  required String model,
  required ImageGenerationApiMode apiMode,
  String? responseFormat,
}) async {
  Map<String, dynamic>? captured;
  final server = await _startServer((httpRequest) async {
    captured =
        jsonDecode(await utf8.decoder.bind(httpRequest).join())
            as Map<String, dynamic>;
    httpRequest.response.headers.contentType = ContentType.json;
    httpRequest.response.write(
      jsonEncode({
        'data': [
          {'b64_json': _pngBase64},
        ],
      }),
    );
    await httpRequest.response.close();
  });

  try {
    await const ImageGenerationApi().generate(
      request,
      _profileFor(server, model: model, apiMode: apiMode),
      responseFormat: responseFormat,
      timeoutSeconds: 30,
    );
  } finally {
    await server.close();
  }

  final body = captured;
  if (body == null) {
    throw StateError('测试服务端没有收到请求。');
  }
  return body;
}

Future<List<int>> _collectBytes(HttpRequest request) async {
  final bytes = <int>[];
  await for (final chunk in request) {
    bytes.addAll(chunk);
  }
  return bytes;
}

GenerationRequest _request({
  List<String> imagePaths = const [],
  SizePreset sizePreset = SizePreset.square1k,
  int customWidth = 1024,
  int customHeight = 1024,
  ImageQuality quality = ImageQuality.auto,
}) {
  return GenerationRequest(
    prompt: 'a red apple',
    imagePaths: imagePaths,
    sizePreset: sizePreset,
    customWidth: customWidth,
    customHeight: customHeight,
    quality: quality,
    count: 1,
    apiProfileId: 'default',
  );
}

ApiProfile _profile({String model = 'grok-imagine-image-2.0'}) {
  return ApiProfile(
    id: 'default',
    name: 'Grok',
    baseUrl: 'https://api.x.ai',
    apiKey: 'test-key',
    model: model,
    apiMode: ImageGenerationApiMode.xaiImagine,
  );
}

Future<HttpServer> _startServer(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(
    server.forEach((request) async {
      await handler(request);
    }),
  );
  return server;
}

ApiProfile _profileFor(
  HttpServer server, {
  String model = 'grok-imagine-image-2.0',
  ImageGenerationApiMode apiMode = ImageGenerationApiMode.xaiImagine,
}) {
  return ApiProfile(
    id: 'default',
    name: 'Grok',
    baseUrl: 'http://${server.address.host}:${server.port}',
    apiKey: 'test-key',
    model: model,
    apiMode: apiMode,
  );
}
