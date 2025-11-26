import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseStorageService {
  final _supabase = Supabase.instance.client;

  /// Uploads media for a specific request and returns the public URL
  Future<String?> uploadRequestMedia(String requestId, File file, String fileExtension) async {
    try {
      print('🔵 [Storage] Starting upload for request: $requestId');
      
      // 1. Create a unique file path
      final filePath =
          'public/$requestId/media_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      print('🔵 [Storage] Upload path: $filePath');

      // 2. Upload the file to the 'media_files' bucket
      await _supabase.storage.from('media_files').upload(
        filePath,
        file,
        fileOptions: const FileOptions(upsert: true),
      );
      print('🔵 [Storage] Upload complete');

      // 3. Get the public URL for the file we just uploaded
      final publicUrl = _supabase.storage.from('media_files').getPublicUrl(filePath);
      print('🔵 [Storage] Public URL: $publicUrl');

      return publicUrl;

    } catch (e) {
      print('🔴 [Storage] Error uploading to Supabase: $e');
      return null;
    }
  }
}