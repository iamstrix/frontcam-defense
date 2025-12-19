import 'package:camera/camera.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For SystemChrome
import 'package:permission_handler/permission_handler.dart';
import 'game/defense_game.dart';
import 'game/upgrade_menu_widget.dart';
import 'services/camera_input_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // await Firebase.initializeApp(); // Requires google-services.json setup

  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: GameLauncher()),
  );
}

class GameLauncher extends StatefulWidget {
  const GameLauncher({super.key});

  @override
  State<GameLauncher> createState() => _GameLauncherState();
}

class _GameLauncherState extends State<GameLauncher> {
  final CameraInputService _cameraService = CameraInputService();
  late DefenseGame _game;
  bool _permissionGranted = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _game = DefenseGame(_cameraService);
    _init();
  }

  Future<void> _init() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      _permissionGranted = true;
      await _cameraService.initialize();
    }
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.cyan)),
      );
    }
    if (!_permissionGranted) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "Front Camera permission is required for aiming.",
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _init,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
                child: const Text(
                  "Grant Permission",
                  style: TextStyle(color: Colors.black),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // Camera Background
          if (_cameraService.controller != null &&
              _cameraService.controller!.value.isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  // Ensure we use the landscape aspect ratio
                  width:
                      _cameraService.controller!.value.previewSize!.width >
                          _cameraService.controller!.value.previewSize!.height
                      ? _cameraService.controller!.value.previewSize!.width
                      : _cameraService.controller!.value.previewSize!.height,
                  height:
                      _cameraService.controller!.value.previewSize!.width <
                          _cameraService.controller!.value.previewSize!.height
                      ? _cameraService.controller!.value.previewSize!.width
                      : _cameraService.controller!.value.previewSize!.height,
                  child: CameraPreview(_cameraService.controller!),
                ),
              ),
            ),

          // Game Layer
          GameWidget<DefenseGame>(
            game: _game,
            overlayBuilderMap: {
              'GameOver': (context, game) {
                return Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.redAccent, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "SYSTEM FAILURE",
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            fontFamily: "Courier",
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "DEFENSE BREACHED",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 30),
                        ElevatedButton(
                          onPressed: () => game.resetGame(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyan,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                          ),
                          child: const Text(
                            "REBOOT SYSTEM",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              'WaveTitle': (context, game) {
                return Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 500),
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Text(
                          "WAVE ${game.currentWave}",
                          style: TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 72 * value,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              BoxShadow(color: Colors.cyan, blurRadius: 20),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
              'UpgradeMenu': (context, game) {
                return UpgradeMenu(game: game);
              },
            },
          ),

          // Status Overlay
          Positioned(
            top: 20,
            left: 20,
            child: AnimatedBuilder(
              animation: _cameraService,
              builder: (context, _) {
                final active = _cameraService.fingerPosition != null;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.cyan.withOpacity(0.2)
                        : Colors.red.withOpacity(0.2),
                    border: Border.all(
                      color: active ? Colors.cyan : Colors.red,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        active ? Icons.gps_fixed : Icons.gps_off,
                        color: active ? Colors.cyan : Colors.red,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        active ? "SYSTEM ONLINE" : "SEARCHING TARGET...",
                        style: TextStyle(
                          color: active ? Colors.cyan : Colors.red,
                          fontWeight: FontWeight.bold,
                          fontFamily: "Courier", // Monospace for tech feel
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Instructions
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                "RAISE FINGER TO AIM",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  letterSpacing: 2,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
