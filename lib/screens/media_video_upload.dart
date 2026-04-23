import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../services/enhanced_supabase_service.dart';
import '../services/thumbnail_generation_service.dart';

class VideoUploadPage extends StatefulWidget {
  const VideoUploadPage({Key? key}) : super(key: key);

  @override
  State<VideoUploadPage> createState() => _VideoUploadPageState();
}

class _VideoUploadPageState extends State<VideoUploadPage> {
  late TextEditingController _descriptionController;


  bool _isUploading = false;
  double _uploadProgress = 0.0;

  Uint8List? _selectedVideoBytes;
  String? _selectedVideoName;

  Uint8List? _thumbnailBytes;
  String? _thumbnailError;
  String? _uploadError;

  final EnhancedSupabaseService _supabaseService = EnhancedSupabaseService();
  final ThumbnailGenerationService _thumbnailService = ThumbnailGenerationService();
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  /// Pick video
  Future<void> _pickVideo() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();

        setState(() {
          _selectedVideoBytes = bytes;
          _selectedVideoName = pickedFile.name;
          _thumbnailBytes = null;
          _thumbnailError = null;
          _uploadError = null;
        });

        await _generateThumbnail();
      }
    } catch (e) {
      _showError('Error picking video: $e');
    }
  }

  /// Generate thumbnail
  Future<void> _generateThumbnail() async {
    if (_selectedVideoBytes == null) return;

    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );

      await tempFile.writeAsBytes(_selectedVideoBytes!);

      final thumbnail = await _thumbnailService.createOptimizedThumbnail(
        videoPath: tempFile.path,
        timeMs: 1000,
        maxWidth: 320,
        maxHeight: 240,
        quality: 75,
      );

      await tempFile.delete();

      setState(() {
        _thumbnailBytes = thumbnail;
        _thumbnailError = thumbnail == null
            ? 'Failed to generate thumbnail'
            : null;
      });
    } catch (e) {
      setState(() {
        _thumbnailError = 'Thumbnail error: $e';
      });
    }
  }

  /// Upload video
  Future<void> _uploadVideo() async {
    if (_selectedVideoBytes == null) {
      _showError('Please select a video first');
      return;
    }

    if (_descriptionController.text.isEmpty) {
      _showError('Please enter a description');
      return;
    }

    if (_thumbnailBytes == null) {
      _showError('Please wait for thumbnail');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      // Simulated progress
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        setState(() {
          _uploadProgress = (i + 1) / 10;
        });
      }

      // 🔥 IMPORTANT: send bytes (not File)
      final result = await _supabaseService.uploadVideoPost(
        videoBytes: _selectedVideoBytes!,
        videoFileName: 'video_${DateTime.now().millisecondsSinceEpoch}.mp4',
        description: _descriptionController.text,
        thumbnailBytes: _thumbnailBytes!,
      );

      if (mounted && result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.pushNamed(context, '/media-success');
      }
    } catch (e) {
      _showError('Upload failed: $e');
    } finally {
      setState(() {
        _isUploading = false;
        _uploadProgress = 0.0;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Upload'),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Preview
            Container(
              height: 220,
              width: double.infinity,
              color: Colors.grey.shade300,
              child: _selectedVideoBytes == null
                  ? const Center(child: Text('No video selected'))
                  : const Center(child: Icon(Icons.play_circle, size: 60)),
            ),

            const SizedBox(height: 10),

            ElevatedButton(
              onPressed: _isUploading ? null : _pickVideo,
              child: const Text('Select Video'),
            ),

            const SizedBox(height: 10),

            if (_thumbnailBytes != null)
              Image.memory(_thumbnailBytes!, height: 120),

            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter description',
                ),
              ),
            ),

            if (_isUploading)
              LinearPercentIndicator(
                lineHeight: 8,
                percent: _uploadProgress,
              ),

            const SizedBox(height: 10),

            ElevatedButton(
              onPressed: _isUploading ? null : _uploadVideo,
              child: const Text('Upload Video'),
            ),
          ],
        ),
      ),
    );
  }
}