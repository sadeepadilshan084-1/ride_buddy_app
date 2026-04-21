import 'package:share_plus/share_plus.dart';
import 'dart:io';

/// Service for handling app sharing functionality with native share sheet
///
/// The native share sheet shows all apps installed on the device that support
/// sharing. Different devices will show different apps based on:
/// 1. What apps are installed
/// 2. Android version (Android 11+ has stricter visibility rules)
/// 3. Device manufacturer customizations
/// 4. User settings and parental controls
class ShareService {
  // App branding
  static const String appName = 'Ride Buddy';
  static const String appDescription =
      'Ride Buddy - Your smart ride-sharing companion app. '
      'Share rides, save money, and connect with your community!';
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.ridebuddy.app';
  static const String appStoreUrl = 'https://apps.apple.com/app/ride-buddy';

  /// Shares the app with default message using native share sheet
  ///
  /// Returns [ShareResult] with the status of the share operation
  /// Status can be:
  /// - success: App was successfully shared
  /// - dismissed: User closed the share dialog
  /// - unavailable: No sharing apps available (rare)
  static Future<void> shareApp() async {
    final message = _buildShareMessage();

    try {
      await Share.share(message, subject: appName);
    } catch (e) {
      rethrow;
    }
  }

  /// Shares the app along with an image file
  ///
  /// [imagePath]: Absolute path to the image file to share
  /// Returns [ShareResultStatus] indicating success or dismissal
  static Future<ShareResultStatus> shareAppWithImage(String imagePath) async {
    try {
      final xFile = XFile(imagePath);
      final message = _buildShareMessage();

      final result = await Share.shareXFiles(
        [xFile],
        text: message,
        subject: appName,
      );

      return result.status;
    } catch (e) {
      rethrow;
    }
  }

  /// Shares multiple images along with app message
  ///
  /// [imagePaths]: List of absolute paths to image files
  /// Returns [ShareResultStatus] indicating success or dismissal
  static Future<ShareResultStatus> shareAppWithMultipleImages(
      List<String> imagePaths,
      ) async {
    try {
      final xFiles = imagePaths.map((path) => XFile(path)).toList();
      final message = _buildShareMessage();

      final result = await Share.shareXFiles(
        xFiles,
        text: message,
        subject: appName,
      );

      return result.status;
    } catch (e) {
      rethrow;
    }
  }

  /// Shares plain text message
  ///
  /// [text]: The text message to share
  /// [subject]: Optional subject line
  static Future<void> shareText(String text, {String? subject}) async {
    try {
      await Share.share(text, subject: subject ?? appName);
    } catch (e) {
      rethrow;
    }
  }

  /// Gets the appropriate app store URL based on platform
  static String getAppStoreUrl() {
    if (Platform.isIOS) {
      return appStoreUrl;
    } else if (Platform.isAndroid) {
      return playStoreUrl;
    }
    return playStoreUrl; // Default to Play Store
  }

  /// Builds the share message with app details
  static String _buildShareMessage() {
    final appStoreUrl = getAppStoreUrl();
    return '''
Check out Ride Buddy! 🚗

$appDescription

Download now: $appStoreUrl

#RideBuddy #RideSharing #StaySafe
    ''';
  }

  /// Provides information about app visibility across different devices
  ///
  /// This explains why different phones show different sharing apps:
  static const String visibilityExplanation = '''
Why Different Phones Show Different Sharing Apps:

1. INSTALLED APPS
   Different devices have different apps installed. Your phone might have
   WhatsApp, Telegram, and Signal, while another user might have completely
   different apps. The share sheet only shows apps that can handle sharing.

2. ANDROID VERSION DIFFERENCES
   - Android 10 and earlier: Apps can see all installed packages
   - Android 11+: System enforces "package visibility" restrictions
   - Target API level affects which apps your app can query
   - Users on older Android versions will see more apps

3. QUERY_ALL_PACKAGES PERMISSION
   The Android manifest includes <uses-permission> for QUERY_ALL_PACKAGES.
   This helps your app discover all available sharing apps on Android 11+.
   Without it, only a limited set of apps would be visible.

4. DEVICE MANUFACTURER CUSTOMIZATION
   Different manufacturers (Samsung, Xiaomi, OnePlus, etc.) may:
   - Pre-install manufacturer-specific apps
   - Hide or disable certain apps by default
   - Use custom system modifications

5. USER SETTINGS & PARENTAL CONTROLS
   Users can:
   - Disable/hide apps they don't use
   - Use parental controls to restrict apps
   - Use app management features to block apps
   - These settings affect what's visible in share dialogs

6. APP MANAGER SETTINGS
   Some devices have app managers that can:
   - Freeze/suspend unused apps (won't appear in share)
   - Restrict app visibility
   - Disable apps temporarily

IMPLICATIONS FOR PLAY STORE:
When you publish on Play Store, each user will see their unique set of
sharing apps based on their device, installed apps, and settings.
This is NORMAL and EXPECTED behavior.

The system automatically shows the right apps for each user's device,
which provides the best user experience for sharing.
''';
}
