import 'package:flutter_test/flutter_test.dart';
import 'package:mint_image/core/models/generation_request.dart';
import 'package:mint_image/core/models/xai_imagine_params.dart';

void main() {
  group('xaiImagineSizeOptions', () {
    test('覆盖全部宽高比与分辨率档位', () {
      expect(xaiImagineAspectRatios, hasLength(13));
      expect(xaiImagineSizeOptions, hasLength(26));
    });

    test('每个选项都能反解回自己的宽高比与分辨率', () {
      // 像素尺寸是 Grok 参数的唯一载体，必须能原样往返，
      // 否则历史记录与重试会发送错误的宽高比。
      for (final option in xaiImagineSizeOptions) {
        expect(
          xaiImagineAspectRatioFor(option.width, option.height),
          option.aspectRatio,
          reason: '${option.label} 反解宽高比失败',
        );
        expect(
          xaiImagineResolutionFor(option.width, option.height),
          option.resolution,
          reason: '${option.label} 反解分辨率失败',
        );
      }
    });

    test('长边等于分辨率档位上限且短边为偶数', () {
      for (final option in xaiImagineSizeOptions) {
        final longest = option.width > option.height
            ? option.width
            : option.height;
        expect(longest, option.resolution.longestEdge);
        expect(option.width.isEven, isTrue);
        expect(option.height.isEven, isTrue);
      }
    });
  });

  group('xaiImagineAspectRatioFor', () {
    test('自动尺寸返回 auto', () {
      expect(xaiImagineAspectRatioFor(0, 0), 'auto');
      expect(xaiImagineAspectRatioFor(1024, 0), 'auto');
    });

    test('按最接近的比例换算常见尺寸', () {
      expect(xaiImagineAspectRatioFor(1024, 1024), '1:1');
      expect(xaiImagineAspectRatioFor(1920, 1080), '16:9');
      expect(xaiImagineAspectRatioFor(1024, 768), '4:3');
      expect(xaiImagineAspectRatioFor(1024, 1536), '2:3');
      expect(xaiImagineAspectRatioFor(1536, 1024), '3:2');
    });

    test('把应用内置的非常规比例归到最接近的档位', () {
      // 21:9 不在 xAI 支持列表内，应归到最接近的 20:9。
      expect(xaiImagineAspectRatioFor(1792, 768), '20:9');
      // 4K 竖版预设仍然按 9:16 处理。
      expect(xaiImagineAspectRatioFor(2160, 3840), '9:16');
    });
  });

  group('xaiImagineResolutionFor', () {
    test('长边不超过 1536 使用 1K', () {
      expect(xaiImagineResolutionFor(1024, 1024), XaiImagineResolution.oneK);
      expect(xaiImagineResolutionFor(1536, 1024), XaiImagineResolution.oneK);
    });

    test('长边超过 1536 使用 2K，4K 预设收敛到 2K', () {
      expect(xaiImagineResolutionFor(2048, 2048), XaiImagineResolution.twoK);
      expect(xaiImagineResolutionFor(3840, 2160), XaiImagineResolution.twoK);
      expect(xaiImagineResolutionFor(2160, 3840), XaiImagineResolution.twoK);
    });

    test('自动尺寸默认使用 1K', () {
      expect(xaiImagineResolutionFor(0, 0), XaiImagineResolution.oneK);
    });
  });

  group('xaiImagineSizeLabel', () {
    test('精确命中选项时展示宽高比与档位', () {
      expect(xaiImagineSizeLabel(1024, 1024), '1:1 1K');
      expect(xaiImagineSizeLabel(2048, 2048), '1:1 2K');
    });

    test('自动尺寸展示为自动', () {
      expect(xaiImagineSizeLabel(0, 0), '自动');
    });

    test('未命中选项时展示换算后的实际参数', () {
      expect(xaiImagineSizeLabel(3840, 2160), '16:9 2K');
    });
  });

  group('xaiImagineSizeOptionFor', () {
    test('命中时返回对应选项', () {
      final option = xaiImagineSizeOptionFor(1024, 1024);
      expect(option, isNotNull);
      expect(option!.aspectRatio, '1:1');
      expect(option.resolution, XaiImagineResolution.oneK);
    });

    test('未命中时返回 null', () {
      expect(xaiImagineSizeOptionFor(3840, 2160), isNull);
    });
  });

  group('xaiImagineQualityValue', () {
    test('低档映射为 low', () {
      expect(xaiImagineQualityValue(ImageQuality.low), 'low');
    });

    test('自动、中、高三档都回落到 medium', () {
      expect(xaiImagineQualityValue(ImageQuality.auto), 'medium');
      expect(xaiImagineQualityValue(ImageQuality.medium), 'medium');
      expect(xaiImagineQualityValue(ImageQuality.high), 'medium');
    });
  });

  group('xaiImagineSupportsQuality', () {
    test('2.0 系列支持 quality 参数', () {
      expect(xaiImagineSupportsQuality('grok-imagine-image-2.0'), isTrue);
    });

    test('更早的型号不支持 quality 参数', () {
      expect(xaiImagineSupportsQuality('grok-imagine-image'), isFalse);
      expect(xaiImagineSupportsQuality('grok-imagine-image-quality'), isFalse);
    });
  });

  group('isXaiImagineModelId', () {
    test('识别 Grok 系列模型', () {
      expect(isXaiImagineModelId('grok-imagine-image-2.0'), isTrue);
      expect(isXaiImagineModelId('grok-imagine-image-lite'), isTrue);
      expect(isXaiImagineModelId(' Grok-Imagine-Image '), isTrue);
    });

    test('其他模型返回 false', () {
      expect(isXaiImagineModelId('gpt-image-2'), isFalse);
      expect(isXaiImagineModelId('gpt-image-2.5-sunburst'), isFalse);
      expect(isXaiImagineModelId(''), isFalse);
    });
  });

  group('resolveImageQualityValue', () {
    test('非 Grok 模型沿用应用内的三档取值', () {
      expect(
        resolveImageQualityValue(
          model: 'gpt-image-2',
          quality: ImageQuality.auto,
        ),
        'auto',
      );
      expect(
        resolveImageQualityValue(
          model: 'gpt-image-2',
          quality: ImageQuality.high,
        ),
        'high',
      );
    });

    test('Grok 2.0 只下发 low 或 medium', () {
      // 自动与高清都不是 Grok 的合法取值，统一回落到 medium。
      for (final quality in const [
        ImageQuality.auto,
        ImageQuality.medium,
        ImageQuality.high,
      ]) {
        expect(
          resolveImageQualityValue(
            model: 'grok-imagine-image-2.0',
            quality: quality,
          ),
          'medium',
          reason: quality.name,
        );
      }
      expect(
        resolveImageQualityValue(
          model: 'grok-imagine-image-2.0',
          quality: ImageQuality.low,
        ),
        'low',
      );
    });

    test('2.0 之前的 Grok 型号不下发 quality', () {
      for (final model in const [
        'grok-imagine-image',
        'grok-imagine-image-lite',
      ]) {
        expect(
          resolveImageQualityValue(model: model, quality: ImageQuality.medium),
          isNull,
          reason: model,
        );
      }
    });

    test('可选档位不包含 Grok 不支持的高清', () {
      expect(xaiImagineQualityOptions, isNot(contains(ImageQuality.high)));
    });
  });
}
