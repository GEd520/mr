import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

/// 全局背景图片组件 - 使用 GlobalKey 保持状态
class ThemedBackground extends StatefulWidget {
  final Widget child;

  const ThemedBackground({
    super.key,
    required this.child,
  });

  @override
  State<ThemedBackground> createState() => ThemedBackgroundState();
}

class ThemedBackgroundState extends State<ThemedBackground> {
  // 使用静态 GlobalKey 确保背景图片不会被重建
  static final GlobalKey _backgroundKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 背景图片层 - 使用 GlobalKey 保持状态
        Positioned.fill(
          key: _backgroundKey,
          child: const _BackgroundLayer(),
        ),
        // 内容层
        widget.child,
      ],
    );
  }
}

/// 背景层组件
class _BackgroundLayer extends StatelessWidget {
  const _BackgroundLayer();

  @override
  Widget build(BuildContext context) {
    final backgroundImage = context.select<AppProvider, String?>(
      (provider) => provider.currentBackgroundImage,
    );
    final backgroundBlur = context.select<AppProvider, int>(
      (provider) => provider.currentBackgroundBlur,
    );
    final brightness = context.select<AppProvider, Brightness>(
      (provider) => provider.themeMode == ThemeMode.dark
          ? Brightness.dark
          : Brightness.light,
    );

    if (backgroundImage == null || backgroundImage.isEmpty) {
      return const SizedBox.shrink();
    }

    return _BackgroundImageWidget(
      imagePath: backgroundImage,
      blur: backgroundBlur,
      brightness: brightness,
    );
  }
}

/// 背景图片组件 - 使用 StatefulWidget 和 didUpdateWidget 避免重建
class _BackgroundImageWidget extends StatefulWidget {
  final String imagePath;
  final int blur;
  final Brightness brightness;

  const _BackgroundImageWidget({
    required this.imagePath,
    required this.blur,
    required this.brightness,
  });

  @override
  State<_BackgroundImageWidget> createState() => _BackgroundImageWidgetState();
}

class _BackgroundImageWidgetState extends State<_BackgroundImageWidget> {
  // 静态缓存 ImageProvider
  static final Map<String, ImageProvider> _imageProviderCache = {};
  // 当前显示的图片路径
  String? _currentImagePath;
  ImageProvider? _currentImageProvider;

  @override
  void initState() {
    super.initState();
    _updateImageProvider();
  }

  @override
  void didUpdateWidget(_BackgroundImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只有图片路径变化时才更新 ImageProvider
    if (oldWidget.imagePath != widget.imagePath) {
      _updateImageProvider();
    }
  }

  void _updateImageProvider() {
    if (_currentImagePath == widget.imagePath && _currentImageProvider != null) {
      return; // 没有变化，不需要更新
    }

    _currentImagePath = widget.imagePath;

    if (_imageProviderCache.containsKey(widget.imagePath)) {
      _currentImageProvider = _imageProviderCache[widget.imagePath]!;
    } else {
      if (widget.imagePath.startsWith('http://') ||
          widget.imagePath.startsWith('https://')) {
        _currentImageProvider = NetworkImage(widget.imagePath);
      } else if (widget.imagePath.startsWith('assets://')) {
        _currentImageProvider =
            AssetImage(widget.imagePath.replaceFirst('assets://', ''));
      } else {
        _currentImageProvider = FileImage(File(widget.imagePath));
      }
      _imageProviderCache[widget.imagePath] = _currentImageProvider!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_currentImageProvider == null) {
      return Container(color: colorScheme.background);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // 背景图片
        Image(
          image: _currentImageProvider!,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) {
            return Container(color: colorScheme.background);
          },
        ),
        // 渐变遮罩
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _getOverlayGradientColors(),
              stops: const [0.0, 0.3, 0.7, 1.0],
            ),
          ),
        ),
        // 模糊效果
        if (widget.blur > 0)
          ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: widget.blur.toDouble(),
              sigmaY: widget.blur.toDouble(),
            ),
            child: Container(color: Colors.transparent),
          ),
      ],
    );
  }

  List<Color> _getOverlayGradientColors() {
    if (widget.brightness == Brightness.dark) {
      return [
        Colors.black.withOpacity(0.15),
        Colors.black.withOpacity(0.20),
        Colors.black.withOpacity(0.25),
        Colors.black.withOpacity(0.30),
      ];
    } else {
      return [
        Colors.white.withOpacity(0.10),
        Colors.white.withOpacity(0.15),
        Colors.white.withOpacity(0.20),
        Colors.white.withOpacity(0.25),
      ];
    }
  }
}

/// 背景图片预览组件 - 用于主题设置页面预览
class BackgroundImagePreview extends StatelessWidget {
  final String? imagePath;
  final int blur;
  final double width;
  final double height;

  const BackgroundImagePreview({
    super.key,
    this.imagePath,
    this.blur = 0,
    this.width = 100,
    this.height = 150,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (imagePath == null || imagePath!.isEmpty) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.image_not_supported_outlined,
          color: colorScheme.onSurfaceVariant,
          size: 32,
        ),
      );
    }

    ImageProvider imageProvider;

    try {
      if (imagePath!.startsWith('http://') || imagePath!.startsWith('https://')) {
        imageProvider = NetworkImage(imagePath!);
      } else if (imagePath!.startsWith('assets://')) {
        imageProvider = AssetImage(imagePath!.replaceFirst('assets://', ''));
      } else {
        imageProvider = FileImage(File(imagePath!));
      }

      Widget imageWidget = Image(
        image: imageProvider,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.broken_image_outlined,
              color: colorScheme.onSurfaceVariant,
              size: 32,
            ),
          );
        },
      );

      if (blur > 0) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: width,
            height: height,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: blur.toDouble(),
                sigmaY: blur.toDouble(),
              ),
              child: imageWidget,
            ),
          ),
        );
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: width,
          height: height,
          child: imageWidget,
        ),
      );
    } catch (e) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.error_outline,
          color: colorScheme.onSurfaceVariant,
          size: 32,
        ),
      );
    }
  }
}
