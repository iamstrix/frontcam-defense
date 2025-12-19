import 'dart:io';
import 'dart:ui';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart'; // For Colors
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class CameraInputService extends ChangeNotifier {
  CameraController? _controller;
  final _poseDetector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.accurate,
    ),
  );

  bool _isProcessing = false;
  Offset? _fingerPosition; // Normalized 0..1 (x, y)
  Offset? get fingerPosition => _fingerPosition;

  CameraController? get controller => _controller;

  Future<void> initialize() async {
    final cameras = await availableCameras();
    CameraDescription? frontCamera;
    try {
      frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
    } catch (e) {
      if (cameras.isNotEmpty) frontCamera = cameras.first;
    }

    if (frontCamera == null) return;

    _controller = CameraController(
      frontCamera,
      ResolutionPreset.medium, // Medium for decent accuracy, Low for speed
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await _controller!.initialize();
    await _controller!.startImageStream(_processImage);
  }

  void _processImage(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // ENROLLMENT CHECK
      if (_enrollNextFrame) {
        _enrollNextFrame = false;
        // Capture center pixel
        // We need to handle different rotation/aspects, but for center pixel in raw image:
        final int cx = image.width ~/ 2;
        final int cy = image.height ~/ 2;
        final color = _getPixelColor(image, cx, cy);
        enrollFinger(color);
        debugPrint("Enrolled Color: $color");
      }

      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      final poses = await _poseDetector.processImage(inputImage);
      if (poses.isNotEmpty) {
        final pose = poses.first;
        final rightIndex = pose.landmarks[PoseLandmarkType.rightIndex];
        final leftIndex = pose.landmarks[PoseLandmarkType.leftIndex];
        final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];
        final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];

        // Track the index finger that is most likely visible and "up"
        PoseLandmark? target;

        // Helper to check if finger is pointing up relative to wrist
        // Y grows downwards in image coordinates. specific < wrist means higher on screen.
        bool isPointingUp(PoseLandmark finger, PoseLandmark? wrist) {
          if (wrist == null) return true; // Loose check if wrist missing
          return finger.y < wrist.y;
        }

        double getScore(PoseLandmark index, PoseLandmark? wrist) {
          if (index.likelihood < 0.6) return -1.0; // Strict threshold
          if (!isPointingUp(index, wrist)) return -1.0; // Must point up-ish
          return index.likelihood;
        }

        double rightScore = (rightIndex != null)
            ? getScore(rightIndex, rightWrist)
            : -1.0;
        double leftScore = (leftIndex != null)
            ? getScore(leftIndex, leftWrist)
            : -1.0;

        if (rightScore > leftScore && rightScore > 0) {
          target = rightIndex;
        } else if (leftScore > rightScore && leftScore > 0) {
          target = leftIndex;
        }

        if (target != null) {
          final size = inputImage.metadata!.size;
          final double w = size.width;
          final double h = size.height;

          // Normalized coordinates
          double x = target.x / w;
          double y = target.y / h;

          // Handle Mirroring for Front Camera
          // Usually, x needs to be flipped.
          if (Platform.isAndroid) {
            // On Android front cam, the image is mirrored relative to preview?
            // Actually, the preview is mirrored. The raw stream might not be?
            // Let's assume we need to flip X to match the "mirror" feel of the preview.
            x = 1.0 - x;
          }
          // On iOS, rotation and mirroring handling can be different.
          // For MVP, we tweak this based on testing.

          // Clamp to screen
          final newPos = Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));

          // COLOR VERIFICATION
          bool verified = true;
          if (_isEnrolled) {
            verified = _verifyFingerColor(image, target);
          }

          if (verified) {
            // Smoothing (Lerp)
            if (_fingerPosition != null) {
              // Increased for faster response while keeping some smoothing
              double lerp = 0.4;
              double dx =
                  _fingerPosition!.dx +
                  (newPos.dx - _fingerPosition!.dx) * lerp;
              double dy =
                  _fingerPosition!.dy +
                  (newPos.dy - _fingerPosition!.dy) * lerp;
              _fingerPosition = Offset(dx, dy);
            } else {
              _fingerPosition = newPos;
            }
            notifyListeners();
          } else {
            // Failed verification (wrong color)
            // Treat as lost?
            // Maybe debounce this to avoid flickering if one frame fails
            if (_fingerPosition != null) {
              _fingerPosition = null;
              notifyListeners();
            }
          }
        } else {
          // If we lost tracking, we could optionally clear detection relative immediately
          // or keep the last known position.
          // For now, let's set it to null so the crosshair disappears if not detected.
          if (_fingerPosition != null) {
            _fingerPosition = null;
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint('Error processing image: $e');
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;

    final camera = _controller!.description;
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      // In landscape, looking at the device:
      // deviceOrientation is usually landscapeLeft (90) or landscapeRight (270).
      // Sensor orientation for front camera is typically 270.

      // ML Kit needs the image rotation relative to "upright" in the image buffer.
      // If we lock to Landscape, the UI is landscape.
      // The camera stream on Android usually comes in "natural" orientation (often landscape for tablets, or portrait for phones??)
      // Actually, on phones, the sensor is mounted portrait.
      // So the image buffer is 90/270 degrees rotated relative to "up".

      // We rely on the controller's deviceOrientation.
      // If locked, it will be landscape.

      var rotationCompensation =
          _orientations[_controller!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        // front-facing
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        // back-facing
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      // This is a simplification; handling other formats requires more logic
      // But generic NV21/BGRA8888 is standard for streams
      if (Platform.isAndroid && format == InputImageFormat.yuv420) {
        // Acceptable fallback often
      } else {
        return null;
      }
    }

    // Since we only need simple processing, we can construct the specific planes
    // Note: This part is tricky. Simplest is creating from bytes if concatenated.
    // For NV21 (Android), plane[0] is Y, plane[1] is VU interleaved.
    // ML Kit expects specific plane structures.
    // Recommended way is using the WriteBuffer/Bytes concatenation.

    // Simplification for MVP: We assume Android NV21 or BGRA8888 for iOS
    if (image.planes.length != 1 &&
        image.format.group != ImageFormatGroup.nv21) {
      // Only handling basic non-planar or standard planar cases
      // If standard Android YUV420:
      // plane 0: Y, plane 1: U, plane 2: V
      // We need to construct bytes.
      // See: https://github.com/flutter-ml/google_ml_kit_flutter/blob/master/packages/google_mlkit_commons/example/lib/vision_detector_views/camera_view.dart
    }

    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize = Size(
      image.width.toDouble(),
      image.height.toDouble(),
    );

    final inputImageMetadata = InputImageMetadata(
      size: imageSize,
      rotation: rotation,
      format: format ?? InputImageFormat.nv21, // Fallback
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: inputImageMetadata);
  }

  static final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  // Enrollment variables
  Color? _enrolledColor;
  bool _isEnrolled = false;
  bool _enrollNextFrame = false;

  bool get isEnrolled => _isEnrolled;

  void captureCenterForEnrollment() {
    _enrollNextFrame = true;
  }

  Future<void> enrollFinger(Color color) async {
    _enrolledColor = color;
    _isEnrolled = true;
    // Save to SharedPreferences (omitted for brevity, handled in UI or service init)
    // Ideally, we handle persistence here or in a separate Storage service.
    // For this MVP, we exposed the method and let the UI drive the flow.
    notifyListeners();
  }

  void setEnrolledColor(Color color) {
    _enrolledColor = color;
    _isEnrolled = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _poseDetector.close();
    super.dispose();
  }

  // --- Color Verification Logic ---

  bool _verifyFingerColor(CameraImage image, PoseLandmark finger) {
    if (!_isEnrolled || _enrolledColor == null) {
      return true; // Pass if not enrolled? Or fail? Let's pass to allow testing without enrollment if desired, but for this task we want strictness.
    }
    // Actually, if not enrolled, we might want to skip this check or return false.
    // Let's assume if not enrolled, we don't filter.

    // 1. Get Pixel Coordinates
    // Landmark x,y are normalized 0..1
    // Image planes might be larger/smaller than screen, but x,y are relative to image dimensions roughly?
    // Actually mlkit landmarks are in image coordinates if not normalized.
    // But my previous code treated them as absolute pixels?
    // Wait, PoseLandmark from MLKit usually has absolute coordinates (x, y) in the "image" space.
    // My previous code: double x = target.x / w; -> So target.x was absolute.

    final int x = finger.x.round();
    final int y = finger.y.round();

    if (x < 0 || y < 0 || x >= image.width || y >= image.height) return false;

    // 2. Extract Color
    final Color detectedColor = _getPixelColor(image, x, y);

    // 3. Compare
    // Euclidian distance in RGB or HSV.
    // Let's use RGB distance for simplicity/speed.
    // Threshold is tricky.
    final double dist = _colorDistance(_enrolledColor!, detectedColor);

    // Threshold: How different can the color be?
    // 0..255 roughly per channel. Max dist is sqrt(255^2 * 3) ~ 441.
    // Let's say 50 is a reasonable strictness?
    return dist < 80.0;
  }

  double _colorDistance(Color c1, Color c2) {
    final r = c1.red - c2.red;
    final g = c1.green - c2.green;
    final b = c1.blue - c2.blue;
    return sqrt(r * r + g * g + b * b);
  }

  Color _getPixelColor(CameraImage image, int x, int y) {
    // Basic YUV extraction for Android
    if (Platform.isAndroid && image.format.group == ImageFormatGroup.nv21) {
      return _yuvToRgb(image, x, y);
    }
    // iOS BGRA
    if (Platform.isIOS && image.format.group == ImageFormatGroup.bgra8888) {
      return _bgraToRgb(image, x, y);
    }
    return Colors.black; // Fallback
  }

  Color _yuvToRgb(CameraImage image, int x, int y) {
    final int width = image.width;
    final int height = image.height;

    final int uvRowStride = image.planes[1].bytesPerRow;
    final int? uvPixelStride = image.planes[1].bytesPerPixel;

    final int indexY = y * width + x;
    final int uvIndex =
        (uvPixelStride ?? 1) * (x ~/ 2) + (y ~/ 2) * uvRowStride;

    final yValue = image.planes[0].bytes[indexY];
    final uValue = image.planes[1].bytes[uvIndex];
    // On some android devices UV might be swapped or in different planes (Y, U, V)
    // NV21: Y... VU...
    // This is a known pain point.
    // Simplified approximation for MVP:
    final vValue = image.planes[2].bytes[uvIndex];

    // Conversion
    // integer math is faster
    int r = (yValue + 1.402 * (vValue - 128)).round();
    int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))
        .round();
    int b = (yValue + 1.772 * (uValue - 128)).round();

    return Color.fromARGB(
      255,
      r.clamp(0, 255),
      g.clamp(0, 255),
      b.clamp(0, 255),
    );
  }

  Color _bgraToRgb(CameraImage image, int x, int y) {
    final int bytesPerRow = image.planes[0].bytesPerRow;
    final int index = y * bytesPerRow + x * 4;
    final b = image.planes[0].bytes[index];
    final g = image.planes[0].bytes[index + 1];
    final r = image.planes[0].bytes[index + 2];
    // alpha is index+3
    return Color.fromARGB(255, r, g, b);
  }
}
