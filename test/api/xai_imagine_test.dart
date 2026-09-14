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

  group('ImageGenerationApi (Grok Imagine)', () {
    test('向 /v1/images/generations 发送宽高比与分辨率请求', () async {
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
        expect(body['aspect_ratio'], '9:16');
        expect(body['resolution'], '1k');
        expect(body['response_format'], 'b64_json');
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
        _request(
          sizePreset: SizePreset.custom,
          customWidth: 576,
          customHeight: 1024,
        ),
        _profileFor(server),
        timeoutSeconds: 30,
      );

      expect(results, hasLength(1));
      expect(results.single.b64Json, _pngBase64);
      expect(results.single.fileExtension, 'png');
    });
  });

  group('ImageEditApi (Grok Imagine)', () {
    test('向 /v1/images/edits 以 JSON 发送参考图', () async {
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
          ContentType.json.mimeType,
        );

        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;

        expect(body['model'], 'grok-imagine-image-2.0');
        expect(body['aspect_ratio'], '1:1');
        expect(body['response_format'], 'b64_json');
        final image = body['image'] as Map<String, dynamic>;
        expect(image['type'], 'image_url');
        expect(image['url'], startsWith('data:image/png;base64,'));

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

ApiProfile _profileFor(HttpServer server) {
  return ApiProfile(
    id: 'default',
    name: 'Grok',
    baseUrl: 'http://${server.address.host}:${server.port}',
    apiKey: 'test-key',
    model: 'grok-imagine-image-2.0',
    apiMode: ImageGenerationApiMode.xaiImagine,
  );
}
