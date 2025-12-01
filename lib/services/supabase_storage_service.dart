import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseStorageService {
  final _supabase = Supabase.instance.client;

  /// Uploads media for a specific request and returns the public URL
  Future<String?> uploadRequestMedia(String requestId, File file, String fileExtension) async {
    try {
      print('🔵 [Storage] Starting upload for request: $requestId');
      print('🔵 [Storage] File path: ${file.path}');
      print('🔵 [Storage] File exists: ${await file.exists()}');
      
      if (!await file.exists()) {
        print('🔴 [Storage] File does not exist at path: ${file.path}');
        return null;
      }
      
      final fileSize = await file.length();
      print('🔵 [Storage] File size: $fileSize bytes');
      
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
      print('🔵 [Storage] Upload complete to Supabase');
      
      // Delay to ensure upload is fully processed
      await Future.delayed(const Duration(milliseconds: 500));

      // 3. CRITICAL FIX: Use createSignedUrl instead of getPublicUrl
      // Signed URLs work in release builds and don't require bucket to be public
      final signedUrl = await _supabase.storage
          .from('media_files')
          .createSignedUrl(filePath, 3600 * 24 * 7); // Valid for 7 days
      
      print('🔵 [Storage] Signed URL generated: $signedUrl');
      
      if (signedUrl.isEmpty) {
        print('🔴 [Storage] WARNING: Signed URL is empty! Trying public URL fallback...');
        
        // Fallback to public URL with auth header
        final publicUrl = _supabase.storage.from('media_files').getPublicUrl(filePath);
        print('🔵 [Storage] Public URL fallback: $publicUrl');
        
        if (publicUrl.isEmpty) {
          print('🔴 [Storage] Both signed and public URLs failed!');
          return null;
        }
        
        return publicUrl;
      }
      
      // Add cache-busting parameter
      final urlWithCacheBust = '$signedUrl${signedUrl.contains('?') ? '&' : '?'}t=${DateTime.now().millisecondsSinceEpoch}';
      print('🔵 [Storage] Final URL with cache-bust: $urlWithCacheBust');

      return urlWithCacheBust;

    } catch (e, stackTrace) {
      print('🔴 [Storage] Error uploading to Supabase: $e');
      print('🔴 [Storage] Stack trace: $stackTrace');
      return null;
    }
  }
}