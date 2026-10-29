import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

/// 面向用户的导出错误，message 可以直接显示在界面上。
class ShareImageException implements Exception {
  const ShareImageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 把海报 widget 渲染成 PNG，再保存到相册或交给系统分享面板。
class ShareImage {
  const ShareImage._();

  /// 默认 3 倍密度：360pt 宽的海报导出为约 1080px 宽的图片。
  static Future<Uint8List> capture(
    GlobalKey boundaryKey, {
    double pixelRatio = 3,
  }) async {
    final object = boundaryKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) {
      throw const ShareImageException('分享图还没准备好，请稍后重试');
    }
    final image = await object.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw const ShareImageException('导出图片失败');
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// 保存到系统相册。iOS 写入「最近项目」，Android 写入 Pictures。
  ///
  /// [name] 不要带扩展名。
  static Future<void> saveToGallery(Uint8List png, {required String name}) async {
    try {
      if (!await Gal.hasAccess()) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          throw const ShareImageException('没有相册权限，请到「设置 › 摩倾 › 照片」中允许写入');
        }
      }
      await Gal.putImageBytes(png, name: name);
    } on GalException catch (error) {
      throw ShareImageException(switch (error.type) {
        GalExceptionType.accessDenied => '没有相册权限，请到「设置 › 摩倾 › 照片」中允许写入',
        GalExceptionType.notEnoughSpace => '设备存储空间不足，无法保存图片',
        GalExceptionType.notSupportedFormat => '图片格式不受支持',
        GalExceptionType.unexpected => '保存失败，请稍后重试',
      });
    }
  }

  /// 打开系统相册，方便用户直接去微信 / 抖音里选图。
  static Future<void> openGallery() async {
    try {
      await Gal.open();
    } on GalException {
      // 打不开相册不是致命错误，忽略即可。
    }
  }

  static Future<void> share({
    required Uint8List png,
    required String fileName,
    String? subject,
    String? text,
    Rect? sharePositionOrigin,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(png, mimeType: 'image/png', name: fileName)],
        subject: subject,
        text: text,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}
