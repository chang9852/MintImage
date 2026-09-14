import 'generation_request.dart';

/// Grok Imagine 图像接口（`/v1/images`）接受的宽高比取值。
///
/// xAI 的原生图像接口不接受任意像素尺寸，只接受宽高比加分辨率档位，
/// 因此本文件负责把应用内通用的像素尺寸与 xAI 参数互相换算。
const List<String> xaiImagineAspectRatios = <String>[
  '1:1',
  '16:9',
  '9:16',
  '4:3',
  '3:4',
  '3:2',
  '2:3',
  '2:1',
  '1:2',
  '19.5:9',
  '9:19.5',
  '20:9',
  '9:20',
];

/// Grok Imagine 的分辨率档位。
///
/// [apiValue] 为接口接收的小写形式，[label] 为界面展示形式，
/// [longestEdge] 用于把自定义像素尺寸换算到最近的档位。
enum XaiImagineResolution {
  oneK('1K', '1k', 1024),
  twoK('2K', '2k', 2048);

  const XaiImagineResolution(this.label, this.apiValue, this.longestEdge);

  final String label;
  final String apiValue;
  final int longestEdge;
}

/// 一个可选的 Grok Imagine 尺寸：宽高比与分辨率档位的组合。
///
/// [width] 与 [height] 是按宽高比和分辨率换算出的像素尺寸。
/// 应用内其余链路（历史记录、收藏夹、重试）都以像素尺寸描述尺寸，
/// 因此这里保留像素表示，使 Grok 的宽高比与分辨率可以原样往返。
class XaiImagineSizeOption {
  const XaiImagineSizeOption({
    required this.aspectRatio,
    required this.resolution,
    required this.width,
    required this.height,
  });

  final String aspectRatio;
  final XaiImagineResolution resolution;
  final int width;
  final int height;

  /// 界面展示文案，例如 `16:9 1K`。
  String get label => '$aspectRatio ${resolution.label}';

  /// 判断给定像素尺寸是否与本选项完全一致。
  bool matches(int width, int height) {
    return this.width == width && this.height == height;
  }
}

/// 全部 Grok Imagine 尺寸选项（13 种宽高比 × 1K/2K 共 26 项）。
final List<XaiImagineSizeOption> xaiImagineSizeOptions = _buildSizeOptions();

List<XaiImagineSizeOption> _buildSizeOptions() {
  final options = <XaiImagineSizeOption>[];
  for (final aspectRatio in xaiImagineAspectRatios) {
    for (final resolution in XaiImagineResolution.values) {
      final (width, height) = xaiImaginePixelsFor(aspectRatio, resolution);
      options.add(
        XaiImagineSizeOption(
          aspectRatio: aspectRatio,
          resolution: resolution,
          width: width,
          height: height,
        ),
      );
    }
  }
  return options;
}

/// 把宽高比与分辨率档位换算为像素尺寸。
///
/// 长边取分辨率档位的像素上限，短边按比例换算并向上取偶数，
/// 保证 `xaiImagineAspectRatioFor` 能反推出同一个宽高比。
(int, int) xaiImaginePixelsFor(
  String aspectRatio,
  XaiImagineResolution resolution,
) {
  final parts = aspectRatio.split(':');
  final ratioWidth = double.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 1;
  final ratioHeight = double.tryParse(parts.length > 1 ? parts[1] : '') ?? 1;
  final longestEdge = resolution.longestEdge;

  if (ratioWidth >= ratioHeight) {
    final shortEdge = _toEven((longestEdge * ratioHeight / ratioWidth).round());
    return (longestEdge, shortEdge);
  }

  final shortEdge = _toEven((longestEdge * ratioWidth / ratioHeight).round());
  return (shortEdge, longestEdge);
}

int _toEven(int value) {
  if (value < 2) {
    return 2;
  }
  return value.isEven ? value : value + 1;
}

/// 依据像素尺寸选出最接近的宽高比。
///
/// 尺寸为自动（宽或高为 0）时返回 `auto`，交由模型自行决定。
String xaiImagineAspectRatioFor(int width, int height) {
  if (width <= 0 || height <= 0) {
    return 'auto';
  }

  final target = width / height;
  var closest = xaiImagineAspectRatios.first;
  var closestDistance = double.infinity;

  for (final aspectRatio in xaiImagineAspectRatios) {
    final value = _ratioValue(aspectRatio);
    final distance = (value - target).abs();
    if (distance < closestDistance) {
      closestDistance = distance;
      closest = aspectRatio;
    }
  }

  return closest;
}

/// 依据像素尺寸选出分辨率档位。
///
/// 长边不超过 1536 像素时使用 1K，否则使用 2K。
/// xAI 目前最高只提供 2K，因此 4K 预设会被归入 2K。
XaiImagineResolution xaiImagineResolutionFor(int width, int height) {
  final longestEdge = width > height ? width : height;
  if (longestEdge <= 0) {
    return XaiImagineResolution.oneK;
  }
  return longestEdge <= 1536
      ? XaiImagineResolution.oneK
      : XaiImagineResolution.twoK;
}

/// 精确匹配某个 Grok Imagine 尺寸选项，没有完全一致的像素尺寸时返回 null。
XaiImagineSizeOption? xaiImagineSizeOptionFor(int width, int height) {
  for (final option in xaiImagineSizeOptions) {
    if (option.matches(width, height)) {
      return option;
    }
  }
  return null;
}

/// 界面展示用的尺寸文案。
///
/// 优先使用精确匹配的选项，其次按换算结果展示实际会发送的宽高比与分辨率。
String xaiImagineSizeLabel(int width, int height) {
  if (width <= 0 || height <= 0) {
    return '自动';
  }

  final option = xaiImagineSizeOptionFor(width, height);
  if (option != null) {
    return option.label;
  }

  final aspectRatio = xaiImagineAspectRatioFor(width, height);
  final resolution = xaiImagineResolutionFor(width, height);
  return '$aspectRatio ${resolution.label}';
}

/// 把应用内的三档质量映射到 Grok Imagine 的 `quality` 参数。
///
/// xAI 只提供 low 与 medium，自动与高清统一回落到 medium。
String xaiImagineQualityValue(ImageQuality quality) {
  return switch (quality) {
    ImageQuality.low => 'low',
    ImageQuality.auto || ImageQuality.medium || ImageQuality.high => 'medium',
  };
}

/// Grok Imagine 的 `quality` 参数自 2.0 起才被接口接受。
///
/// 对更早的 `grok-imagine-image` / `grok-imagine-image-quality`
/// 不能下发该参数，否则会被判定为未知字段。
bool xaiImagineSupportsQuality(String model) {
  return model.trim().toLowerCase().contains('2.0');
}

/// 中转站的 Grok 图像渠道接受的固定 `size` 取值及其对应宽高比。
///
/// 该渠道只认识这一组尺寸标记，其他像素尺寸会被直接拒绝
/// （返回「aspect_ratio 不受支持」），因此需要把应用内的任意像素尺寸
/// 换算到其中最近的取值。
const Map<String, String> _xaiImagineRelaySizes = <String, String>{
  '1024x1024': '1:1',
  '1280x720': '16:9',
  '720x1280': '9:16',
  '1536x1024': '3:2',
  '1024x1536': '2:3',
};

/// 把像素尺寸换算成中转站接受的 `size` 取值。
///
/// 尺寸为自动（宽或高为 0）时返回 null，表示不下发该字段、
/// 由上游自行决定，避免下发未被接受的取值。
String? xaiImagineRelaySizeFor(int width, int height) {
  if (width <= 0 || height <= 0) {
    return null;
  }

  final target = width / height;
  String? closest;
  var closestDistance = double.infinity;

  for (final entry in _xaiImagineRelaySizes.entries) {
    final distance = (_ratioValue(entry.value) - target).abs();
    if (distance < closestDistance) {
      closestDistance = distance;
      closest = entry.key;
    }
  }

  return closest;
}

/// Grok Imagine 单次请求的最小超时时间（秒）。
///
/// 该系列每次生成都会先经过一遍提示词重写模型，提示词越长耗时越久，
/// 实测常常需要数分钟。即便设置里的超时更短，也按这个下限执行，
/// 避免把仍在生成中的请求提前中断。
const int grokImagineMinRequestTimeoutSeconds = 1200;

/// 计算模型实际使用的请求超时（秒）。
///
/// 只有 Grok 系列会被抬到 [grokImagineMinRequestTimeoutSeconds] 下限，
/// 其余模型沿用设置里的取值。
int resolveRequestTimeoutSeconds(int configuredSeconds, String model) {
  if (!isXaiImagineModelId(model)) {
    return configuredSeconds;
  }
  return configuredSeconds < grokImagineMinRequestTimeoutSeconds
      ? grokImagineMinRequestTimeoutSeconds
      : configuredSeconds;
}

/// 判断模型名是否属于 xAI Grok 图像模型。
///
/// 模型名以 `grok` 开头即视为 Grok 系列，这样后续新增
/// `grok-imagine-*` 型号时无需再改判断逻辑。
bool isXaiImagineModelId(String model) {
  return model.trim().toLowerCase().startsWith('grok');
}

/// 界面中可供选择的 Grok 质量档位。
///
/// Grok 只接受 `low` 与 `medium`，因此不提供「高」。
const List<ImageQuality> xaiImagineQualityOptions = <ImageQuality>[
  ImageQuality.auto,
  ImageQuality.low,
  ImageQuality.medium,
];

/// 计算最终下发到接口的 `quality` 取值，返回 null 表示不下发该字段。
///
/// Grok 系列只接受 `low` 与 `medium`：应用里的「自动」与「高」都不是合法取值，
/// 因此自动回落到 `medium`（界面也不提供「高」）。
/// 该参数仅 2.0 支持，更早的型号一律不下发。
/// 其余模型沿用应用内的三档取值。
String? resolveImageQualityValue({
  required String model,
  required ImageQuality quality,
}) {
  if (!isXaiImagineModelId(model)) {
    return quality.apiValue;
  }
  if (!xaiImagineSupportsQuality(model)) {
    return null;
  }
  return xaiImagineQualityValue(quality);
}

double _ratioValue(String aspectRatio) {
  final parts = aspectRatio.split(':');
  final ratioWidth = double.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 1;
  final ratioHeight = double.tryParse(parts.length > 1 ? parts[1] : '') ?? 1;
  if (ratioHeight == 0) {
    return double.infinity;
  }
  return ratioWidth / ratioHeight;
}
