import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

/// Media Storage Service - Handles uploads to the 'media' bucket
class MediaStorageService {
  static final MediaStorageService _instance = MediaStorageService._internal();

  factory MediaStorageService() {
    return _instance;
  }

  MediaStorageService._internal();

  final SupabaseClient _client = Supabase.instance.client;
  static const String _bucketName = 'vehicle-qr';

  String? getCurrentUserId() {
    return _client.auth.currentUser?.id;
  }

  /// Upload file to media bucket
  /// Returns the full public URL of the uploaded file
  Future<String> uploadFile({
    required File file,
    required String fileName,
    String? fileType, // e.g., 'photo', 'document', 'profile'
  }) async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) throw Exception('User not authenticated');

      // Create path: userId/fileType/fileName
      final folderPath = fileType != null ? '$userId/$fileType' : '$userId';
      final filePath = '$folderPath/$fileName';

      // Upload file
      await _client.storage.from(_bucketName).upload(
            filePath,
            file,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: false,
            ),
          );

      // Get public URL
      final publicUrl = _client.storage.from(_bucketName).getPublicUrl(filePath);
      return publicUrl;
    } catch (e) {
      print('Error uploading file to media bucket: $e');
      rethrow;
    }
  }

  /// Upload a QR code for a specific vehicle and return the file path (not full URL).
  /// The path can be used with getPublicQrUrl() to generate the public URL when needed.
  Future<String> uploadVehicleQrFile({
    required File file,
    required String vehicleId,
  }) async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) throw Exception('User not authenticated');

      final extension = file.path.split('.').last;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$extension';
      final filePath = '$userId/$vehicleId/$fileName';

      await _client.storage.from(_bucketName).upload(
            filePath,
            file,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true,
            ),
          );

      // Return just the path, not the full URL
      return filePath;
    } catch (e) {
      print('Error uploading vehicle QR file: $e');
      throw Exception('Vehicle QR upload failed: $e');
    }
  }

  /// Get public URL for a QR file path
  String getPublicQrUrl(String filePath) {
    if (filePath.isEmpty) return '';
    
    // If it's already a full URL, return it as-is
    if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
      return filePath;
    }
    
    return _client.storage.from(_bucketName).getPublicUrl(filePath);
  }

  /// Delete a QR code file by path (not URL)
  Future<void> deleteVehicleQrFile(String filePath) async {
    try {
      if (filePath.isEmpty) return;
      
      // Extract path if it's a full URL
      String pathToDelete = filePath;
      if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
        // Try to extract path from URL
        final extractedPath = getStoragePathFromUrl(filePath);
        if (extractedPath != null) {
          pathToDelete = extractedPath;
        } else {
          throw Exception('Could not extract path from QR URL');
        }
      }
      
      await deleteFile(pathToDelete);
      print('QR file deleted: $pathToDelete');
    } catch (e) {
      print('Error deleting QR file: $e');
      rethrow;
    }
  }

  /// Extract a storage path from a Supabase public URL.
  String? getStoragePathFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final publicIndex = segments.indexOf('public');
      if (publicIndex == -1) return null;
      if (publicIndex + 2 >= segments.length) return null;
      if (segments[publicIndex + 1] != _bucketName) return null;
      return segments.sublist(publicIndex + 2).join('/');
    } catch (_) {
      return null;
    }
  }

  /// Delete a file from storage by public URL.
  Future<void> deleteFileFromUrl(String url) async {
    final path = getStoragePathFromUrl(url);
    if (path == null) {
      throw Exception('Could not derive storage path from URL');
    }
    await deleteFile(path);
  }

  /// Upload multiple files
  Future<List<String>> uploadMultipleFiles({
    required List<File> files,
    required List<String> fileNames,
    String? fileType,
  }) async {
    try {
      if (files.length != fileNames.length) {
        throw Exception('Files and names length mismatch');
      }

      final urls = <String>[];
      for (int i = 0; i < files.length; i++) {
        final url = await uploadFile(
          file: files[i],
          fileName: fileNames[i],
          fileType: fileType,
        );
        urls.add(url);
      }
      return urls;
    } catch (e) {
      print('Error uploading multiple files: $e');
      rethrow;
    }
  }

  /// Delete file from media bucket
  Future<void> deleteFile(String filePath) async {
    try {
      await _client.storage.from(_bucketName).remove([filePath]);
    } catch (e) {
      print('Error deleting file from media bucket: $e');
      rethrow;
    }
  }

  /// Delete multiple files
  Future<void> deleteMultipleFiles(List<String> filePaths) async {
    try {
      await _client.storage.from(_bucketName).remove(filePaths);
    } catch (e) {
      print('Error deleting files from media bucket: $e');
      rethrow;
    }
  }

  /// List files in a specific user folder
  Future<List<FileObject>> listUserFiles({
    String? fileType,
  }) async {
    try {
      final userId = getCurrentUserId();
      if (userId == null) throw Exception('User not authenticated');

      final searchPath = fileType != null ? '$userId/$fileType' : userId;
      final files = await _client.storage.from(_bucketName).list(path: searchPath);
      return files;
    } catch (e) {
      print('Error listing files from media bucket: $e');
      return [];
    }
  }

  /// Generate a unique file name with timestamp
  String generateFileName(String originalFileName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = originalFileName.split('.').last;
    return '${originalFileName.replaceAll('.', '_')}_${timestamp}.$extension';
  }

  /// Create a signed URL that expires after a certain time (in seconds)
  Future<String> createSignedUrl({
    required String filePath,
    required int expiresIn,
  }) async {
    try {
      final signedUrl = await _client.storage
          .from(_bucketName)
          .createSignedUrl(filePath, expiresIn);
      return signedUrl;
    } catch (e) {
      print('Error creating signed URL: $e');
      rethrow;
    }
  }

  /// Get public URL for a file
  String getPublicUrl(String filePath) {
    return _client.storage.from(_bucketName).getPublicUrl(filePath);
  }
}
