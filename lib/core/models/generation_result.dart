class GenerationResult {
  const GenerationResult({
    this.b64Json,
    this.imageUrl,
    this.rawResponseValue,
    this.fileExtension,
    this.retriedWithSingleImage = false,
  });

  final String? b64Json;
  final String? imageUrl;
  final String? rawResponseValue;

  /// 服务端返回的图片真实格式对应的扩展名（不含点）。
  ///
  /// 接口无法指定输出格式时（例如 Grok Imagine），由 API 层按图片头字节推断，
  /// 避免把 JPEG/WebP 数据写成 `.png`。为空时沿用请求中选择的输出格式。
  final String? fileExtension;

  final bool retriedWithSingleImage;

  bool get hasImageData =>
      (b64Json != null && b64Json!.isNotEmpty) ||
      (imageUrl != null && imageUrl!.isNotEmpty);

  GenerationResult copyWith({
    String? b64Json,
    String? imageUrl,
    String? rawResponseValue,
    String? fileExtension,
    bool? retriedWithSingleImage,
  }) {
    return GenerationResult(
      b64Json: b64Json ?? this.b64Json,
      imageUrl: imageUrl ?? this.imageUrl,
      rawResponseValue: rawResponseValue ?? this.rawResponseValue,
      fileExtension: fileExtension ?? this.fileExtension,
      retriedWithSingleImage:
          retriedWithSingleImage ?? this.retriedWithSingleImage,
    );
  }
}
