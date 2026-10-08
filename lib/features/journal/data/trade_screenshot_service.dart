import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

/// Where trade screenshots live and what the client accepts.
///
/// The bucket is PRIVATE (migration 0010): `trades.screenshot_url` stores the
/// storage PATH (`<owner-uid>/<trade-id>/<millis>.<ext>`), never a public or
/// signed URL. The screen downloads bytes with the caller's own authenticated
/// session, which is what the owner-scoped storage policies authorise.
class TradeScreenshots {
  TradeScreenshots._();

  static const String bucket = 'trade-screenshots';

  /// Client-side guard: the bucket has no server-side file-size cap (see the
  /// migration notes), so the client refuses anything larger before uploading.
  static const int maxBytes = 5 * 1024 * 1024;

  static const List<String> allowedExtensions = <String>[
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  static const List<String> allowedMimeTypes = <String>[
    'image/jpeg',
    'image/png',
    'image/webp',
  ];

  /// Storage path for a new upload. The first segment is the owner's uid —
  /// the storage RLS policies match on exactly this, so it must never be
  /// anything else (no nickname, no account id).
  static String objectPath({
    required String ownerUid,
    required String tradeId,
    required String extension,
    DateTime? now,
  }) {
    final String ext = extension.toLowerCase();
    final int millis = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return '$ownerUid/$tradeId/$millis.$ext';
  }

  /// Shared validation for both the live and mock services, so mock mode
  /// refuses exactly what live mode refuses.
  static void validate({
    required String fileName,
    required String mimeType,
    required int byteLength,
  }) {
    final String ext = fileName.split('.').last.toLowerCase();
    if (!allowedExtensions.contains(ext)) {
      throw const TradeScreenshotFailure(
        'That file type is not supported. Choose a JPG, PNG or WebP image.',
      );
    }
    if (!allowedMimeTypes.contains(mimeType)) {
      throw const TradeScreenshotFailure(
        'That file type is not supported. Choose a JPG, PNG or WebP image.',
      );
    }
    if (byteLength > maxBytes) {
      throw const TradeScreenshotFailure(
        'That image is too large. Choose one under 5 MB.',
      );
    }
  }
}

/// Trader-facing failure. Never carries a raw platform/storage error string —
/// those can quote bucket paths and uids.
class TradeScreenshotFailure implements Exception {
  const TradeScreenshotFailure(this.message);

  final String message;

  @override
  String toString() => 'TradeScreenshotFailure: $message';
}

/// Uploads screenshot bytes and downloads them back for display.
///
/// Split from [TradeRepository] on purpose: the repository owns the `trades`
/// row (linking the path via `updateScreenshot`); this service owns the
/// private storage bucket.
abstract class TradeScreenshotService {
  /// Uploads [bytes] for [tradeId] and returns the storage PATH to link.
  Future<String> upload({
    required String tradeId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  });

  /// Downloads the bytes for [path], or null when there is nothing to show.
  Future<Uint8List?> download(String? path);

  /// Picks one image from the device gallery. Null when the user cancels.
  Future<PickedScreenshot?> pickFromGallery();
}

/// One image the user selected, read into memory before upload.
class PickedScreenshot {
  const PickedScreenshot({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

/// Live implementation: private-bucket upload/download under the caller uid.
class SupabaseTradeScreenshotService implements TradeScreenshotService {
  SupabaseTradeScreenshotService([SupabaseService? service])
      : _service = service ?? SupabaseService.instance;

  final SupabaseService _service;

  SupabaseClient get _client => _service.client;

  String get _uid {
    final String? id = _client.auth.currentUser?.id;
    if (id == null || id.isEmpty) {
      throw const TradeScreenshotFailure(
        'You need to be signed in to upload a screenshot.',
      );
    }
    return id;
  }

  @override
  Future<PickedScreenshot?> pickFromGallery() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Downscale chart screenshots: they stay readable well under maxBytes.
      maxWidth: 1920,
      imageQuality: 88,
    );
    if (file == null) return null;
    final Uint8List bytes = await file.readAsBytes();
    final String name = file.name.isEmpty ? 'screenshot.jpg' : file.name;
    return PickedScreenshot(
      bytes: bytes,
      fileName: name,
      mimeType: _mimeFor(name),
    );
  }

  @override
  Future<String> upload({
    required String tradeId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    TradeScreenshots.validate(
      fileName: fileName,
      mimeType: mimeType,
      byteLength: bytes.length,
    );
    final String ext = fileName.split('.').last.toLowerCase();
    final String path = TradeScreenshots.objectPath(
      ownerUid: _uid,
      tradeId: tradeId,
      extension: ext,
    );
    try {
      await _client.storage.from(TradeScreenshots.bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );
    } on StorageException {
      throw const TradeScreenshotFailure(
        'Could not upload that image. Check your connection and try again.',
      );
    } catch (_) {
      throw const TradeScreenshotFailure(
        'Could not upload that image. Check your connection and try again.',
      );
    }
    return path;
  }

  @override
  Future<Uint8List?> download(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      return await _client.storage.from(TradeScreenshots.bucket).download(
            path,
          );
    } on StorageException {
      throw const TradeScreenshotFailure(
        'Could not load that screenshot. Check your connection and try '
        'again.',
      );
    } catch (_) {
      throw const TradeScreenshotFailure(
        'Could not load that screenshot. Check your connection and try '
        'again.',
      );
    }
  }
}

/// Mock implementation: keeps bytes in memory so the whole upload → link →
/// display flow is exercisable with no backend. Paths use the same
/// `<uid>/<trade>/<millis>.<ext>` shape the live service writes.
class MockTradeScreenshotService implements TradeScreenshotService {
  final Map<String, Uint8List> stored = <String, Uint8List>{};

  @override
  Future<PickedScreenshot?> pickFromGallery() async => null;

  @override
  Future<String> upload({
    required String tradeId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    TradeScreenshots.validate(
      fileName: fileName,
      mimeType: mimeType,
      byteLength: bytes.length,
    );
    final String ext = fileName.split('.').last.toLowerCase();
    final String path = TradeScreenshots.objectPath(
      ownerUid: 'mock-uid',
      tradeId: tradeId,
      extension: ext,
    );
    stored[path] = bytes;
    return path;
  }

  @override
  Future<Uint8List?> download(String? path) async {
    if (path == null || path.isEmpty) return null;
    return stored[path];
  }
}

String _mimeFor(String fileName) {
  switch (fileName.split('.').last.toLowerCase()) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'jpg':
    case 'jpeg':
    default:
      return 'image/jpeg';
  }
}

