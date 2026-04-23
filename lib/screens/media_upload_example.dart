import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/media_storage_service.dart';
import '../services/supabase_service.dart';

/// Example: Complete Media Upload Implementation with Media Bucket
class MediaUploadExample extends StatefulWidget {
  const MediaUploadExample({Key? key}) : super(key: key);

  @override
  State<MediaUploadExample> createState() => _MediaUploadExampleState();
}

class _MediaUploadExampleState extends State<MediaUploadExample> {

  final MediaStorageService _storageService = MediaStorageService();
  final SupabaseService _dbService = SupabaseService();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isUploading = false;
  File? _selectedFile;
  String? _uploadedUrl;
  double? _uploadProgress;

  /// Example 1: Simple Image Upload
  Future<void> _uploadSimpleImage() async {
    try {


      setState(() => _isUploading = true);

      if (_selectedFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an image')),
        );
        return;
      }

      // Generate unique filename
      final fileName = _storageService.generateFileName('photo.jpg');

      // Upload to media bucket
      final imageUrl = await _storageService.uploadFile(
        file: _selectedFile!,
        fileName: fileName,
        fileType: 'photos', // Creates: userId/photos/photo_xxx.jpg
      );

      setState(() => _uploadedUrl = imageUrl);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Image uploaded successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Upload failed: $e')),
      );
    } finally {
      setState(() => _isUploading = false);
    }
  }

  /// Example 2: Upload with Database Record
  Future<void> _uploadWithMetadata({
    required String description,
    required String title,
  }) async {
    try {
      setState(() => _isUploading = true);

      if (_selectedFile == null) {
        throw Exception('No file selected');
      }

      // Step 1: Upload file to media bucket
      final fileName = _storageService.generateFileName('media.jpg');
      final imageUrl = await _storageService.uploadFile(
        file: _selectedFile!,
        fileName: fileName,
        fileType: 'posts',
      );

      // Step 2: Save metadata to database
      final userId = _storageService.getCurrentUserId();
      await _dbService.addMediaPost(
        userId: userId!,
        mediaType: 'image',
        description: description,
        mediaUrl: imageUrl,
      );

      setState(() => _uploadedUrl = imageUrl);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Post created successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Failed: $e')),
      );
    } finally {
      setState(() => _isUploading = false);
    }
  }

  /// Example 3: Upload Multiple Files
  Future<void> _uploadMultipleFiles() async {
    try {
      setState(() => _isUploading = true);

      // In real scenario, let user pick multiple images
      final pickedFiles = await _imagePicker.pickMultiImage();

      if (pickedFiles.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No files selected')),
        );
        return;
      }

      final files = pickedFiles.map((xFile) => File(xFile.path)).toList();
      final fileNames = pickedFiles
          .map((xFile) => _storageService.generateFileName(
              xFile.name.isNotEmpty ? xFile.name : 'photo.jpg'))
          .toList();

      // Upload all files
      final urls = await _storageService.uploadMultipleFiles(
        files: files,
        fileNames: fileNames,
        fileType: 'gallery',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ ${urls.length} files uploaded!')),
      );

      setState(() => _uploadedUrl = urls.first);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e')),
      );
    } finally {
      setState(() => _isUploading = false);
    }
  }

  /// Example 4: List User's Files
  Future<void> _listUserFiles() async {
    try {
      final files = await _storageService.listUserFiles(fileType: 'photos');

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Your Photos'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: files.length,
              itemBuilder: (context, index) => ListTile(
                title: Text(files[index].name),
                subtitle: Text(
                  'Updated: ${files[index].updatedAt}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e')),
      );
    }
  }

  /// Pick image from gallery
  Future<void> _pickImage() async {
    try {
      final pickedFile =
          await _imagePicker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() => _selectedFile = File(pickedFile.path));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Media Upload Examples'),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image Preview
            Container(
              height: 250,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey),
              ),
              child: _selectedFile != null
                  ? Image.file(_selectedFile!, fit: BoxFit.cover)
                  : const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.image, size: 64, color: Colors.grey),
                          SizedBox(height: 10),
                          Text('No image selected'),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 20),

            // Pick Image Button
            ElevatedButton.icon(
              onPressed: _isUploading ? null : _pickImage,
              icon: const Icon(Icons.photo_library),
              label: const Text('Pick Image'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
            ),
            const SizedBox(height: 10),

            // Example 1: Simple Upload
            ElevatedButton.icon(
              onPressed: _isUploading || _selectedFile == null
                  ? null
                  : _uploadSimpleImage,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Example 1: Simple Upload'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
            ),
            const SizedBox(height: 10),

            // Example 2: Upload with Metadata
            ElevatedButton.icon(
              onPressed: _isUploading || _selectedFile == null
                  ? null
                  : () => _uploadWithMetadata(
                        description: 'Beautiful moment captured',
                        title: 'My Memory',
                      ),
              icon: const Icon(Icons.save),
              label: const Text('Example 2: Upload with Metadata'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
            ),
            const SizedBox(height: 10),

            // Example 3: Multiple Upload
            ElevatedButton.icon(
              onPressed: _isUploading ? null : _uploadMultipleFiles,
              icon: const Icon(Icons.collections),
              label: const Text('Example 3: Upload Multiple'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
            ),
            const SizedBox(height: 10),

            // Example 4: List Files
            ElevatedButton.icon(
              onPressed: _isUploading ? null : _listUserFiles,
              icon: const Icon(Icons.list),
              label: const Text('Example 4: List My Files'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
              ),
            ),
            const SizedBox(height: 20),

            // Loading Status
            if (_isUploading) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 10),
              const Text(
                'Uploading...',
                textAlign: TextAlign.center,
              ),
            ],

            // Uploaded URL Display
            if (_uploadedUrl != null) ...[
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 10),
              const Text(
                'Uploaded Successfully!',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                _uploadedUrl!,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ URL copied!')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy URL'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
