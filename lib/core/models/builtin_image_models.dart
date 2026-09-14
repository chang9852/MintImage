/// xAI Grok Imagine 的内置图像模型候选。
///
/// xAI 的 `/v1/models` 不一定返回图像模型，内置候选项可以保证
/// 不联网也能在设置页的模型下拉里直接选中。
const List<String> xaiImagineModelIds = <String>[
  'grok-imagine-image-2.0',
  'grok-imagine-image-quality',
  'grok-imagine-image',
];
