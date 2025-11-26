-- =====================================================
-- Supabase Storage Policies for Streamix Camera Feature
-- =====================================================
-- Run these commands in Supabase SQL Editor
-- Dashboard → SQL Editor → New Query → Paste & Run
-- =====================================================

-- Step 1: Ensure the media_files bucket exists
-- (Usually already created, but just in case)
INSERT INTO storage.buckets (id, name, public)
VALUES ('media_files', 'media_files', true)
ON CONFLICT (id) DO UPDATE
SET public = true;

-- Step 2: Allow PUBLIC READ access to all files in media_files bucket
-- This allows Image.network() to load images without authentication
CREATE POLICY IF NOT EXISTS "Allow Public Reads on Media Files"
ON storage.objects FOR SELECT
USING (bucket_id = 'media_files');

-- Step 3: Allow AUTHENTICATED users to upload files
-- This allows User B to upload captured photos
CREATE POLICY IF NOT EXISTS "Allow Authenticated Uploads"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'media_files' AND
  auth.role() = 'authenticated'
);

-- Step 4: Allow users to update their own uploads
CREATE POLICY IF NOT EXISTS "Allow Users to Update Own Files"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'media_files' AND
  auth.role() = 'authenticated'
);

-- Step 5: Allow users to delete their own uploads
CREATE POLICY IF NOT EXISTS "Allow Users to Delete Own Files"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'media_files' AND
  auth.role() = 'authenticated'
);

-- =====================================================
-- VERIFICATION QUERIES
-- =====================================================

-- Check if bucket exists and is public
SELECT id, name, public FROM storage.buckets WHERE id = 'media_files';
-- Expected: id='media_files', name='media_files', public=true

-- Check all policies on storage.objects
SELECT * FROM pg_policies WHERE tablename = 'objects';
-- Should see all 4 policies created above

-- List all files in media_files bucket (for testing)
SELECT * FROM storage.objects WHERE bucket_id = 'media_files' ORDER BY created_at DESC LIMIT 10;

-- =====================================================
-- TESTING
-- =====================================================

-- After running these policies, test by:
-- 1. Upload a photo from the app (User B side)
-- 2. Check if file appears in Supabase Dashboard → Storage → media_files
-- 3. Copy the public URL and paste in browser
-- 4. If image loads in browser → Policies work! ✅
-- 5. If 403 Forbidden → Rerun the policies above
-- 6. If 404 Not Found → File wasn't uploaded correctly

-- =====================================================
-- CLEANUP (Optional - only if you need to start fresh)
-- =====================================================

-- WARNING: This deletes all files and policies!
-- Only run this if you want to completely reset storage

-- DROP POLICY IF EXISTS "Allow Public Reads on Media Files" ON storage.objects;
-- DROP POLICY IF EXISTS "Allow Authenticated Uploads" ON storage.objects;
-- DROP POLICY IF EXISTS "Allow Users to Update Own Files" ON storage.objects;
-- DROP POLICY IF EXISTS "Allow Users to Delete Own Files" ON storage.objects;
-- DELETE FROM storage.objects WHERE bucket_id = 'media_files';

-- =====================================================
-- ALTERNATIVE: Super Permissive Policy (Quick Test)
-- =====================================================
-- If you just want to test quickly, use this single policy:

-- DROP POLICY IF EXISTS "Allow Public Reads on Media Files" ON storage.objects;
-- CREATE POLICY "Public Access to Media Files"
-- ON storage.objects
-- FOR ALL
-- USING (bucket_id = 'media_files');

-- This allows anyone to read, write, update, delete files in media_files bucket
-- ⚠️ NOT recommended for production! Use specific policies above instead.

-- =====================================================
-- SECURITY NOTES
-- =====================================================

/**
 * Current Setup:
 * - Anyone can READ files (needed for Image.network)
 * - Only authenticated users can UPLOAD
 * - Only authenticated users can UPDATE/DELETE
 * 
 * Recommended for Production:
 * - Add path-based restrictions (e.g., only allow access to public/ folder)
 * - Add user-based restrictions (only requestor/provider can access)
 * - Add expiration policies (auto-delete old files)
 * 
 * Example Path-Based Policy:
 * CREATE POLICY "Public Read on Public Folder Only"
 * ON storage.objects FOR SELECT
 * USING (
 *   bucket_id = 'media_files' AND
 *   (storage.foldername(name))[1] = 'public'
 * );
 */

-- =====================================================
-- END OF SCRIPT
-- =====================================================
