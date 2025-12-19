import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flame/game.dart';
import '../game/defense_game.dart';
import '../game/upgrade_manager.dart';

class UpgradeMenu extends StatefulWidget {
  final DefenseGame game;

  const UpgradeMenu({super.key, required this.game});

  @override
  State<UpgradeMenu> createState() => _UpgradeMenuState();
}

class _UpgradeMenuState extends State<UpgradeMenu> {
  List<UpgradeDefinition>? _upgrades;
  Timer? _timer;

  // Hover Logic
  int? _hoveredIndex;
  int _ticksHovered = 0;
  // Threshold: 3 seconds. Timer runs every 100ms. So 30 ticks.
  static const int _requiredTicks = 30;

  @override
  void initState() {
    super.initState();
    _upgrades = widget.game.upgradeManager.getRandomUpgrades(3);

    // Start Ticker
    _timer = Timer.periodic(const Duration(milliseconds: 100), _checkHover);
  }

  void _checkHover(Timer timer) {
    if (!mounted) return;

    // Get Crosshair Position from Game
    // Game is fullscreen, so 0,0 is top left.
    // However, crosshair.position is in "Game World Coordinates".
    // For a base FlameGame, world matches screen size usually if using Camera?
    // DefenseGame uses default camera with viewport matching screen size.
    // So crosshair.position (Vector2) should map to screen Offset.

    final crosshairPos = widget.game.crosshair.position;
    final screenOffset = Offset(crosshairPos.x, crosshairPos.y);

    int? currentlyHovered;

    // We assume 3 cards laid out. We need to know their Rects.
    // Since determining exact RenderBox bounds dynamically is tricky without keys or hit testing...
    // simpler approach: Hardcode regions or use LayoutBuilder + geometry?
    // Using hitTest is most robust if we have keys.
    // OR: Use 'MouseRegion' logic but manual?

    // Let's rely on keys for the 3 cards.
    for (int i = 0; i < (_upgrades?.length ?? 0); i++) {
      final key = _cardKeys[i];
      final context = key.currentContext;
      if (context != null) {
        final box = context.findRenderObject() as RenderBox;
        final position = box.localToGlobal(Offset.zero);
        final size = box.size;
        final rect = position & size;

        if (rect.contains(screenOffset)) {
          currentlyHovered = i;
          break;
        }
      }
    }

    if (currentlyHovered == _hoveredIndex) {
      if (currentlyHovered != null) {
        _ticksHovered++;
        if (_ticksHovered >= _requiredTicks) {
          // Select!
          _selectUpgrade(currentlyHovered);
        }
      }
    } else {
      // Reset
      _hoveredIndex = currentlyHovered;
      _ticksHovered = 0;
    }

    setState(() {}); // Repaint for progress bar
  }

  void _selectUpgrade(int index) {
    if (_upgrades == null) return;
    _timer?.cancel();
    widget.game.applyUpgrade(_upgrades![index]);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  final List<GlobalKey> _cardKeys = [GlobalKey(), GlobalKey(), GlobalKey()];

  @override
  Widget build(BuildContext context) {
    if (_upgrades == null) return const SizedBox.shrink();

    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        color: Colors.black.withOpacity(0.8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_upgrades!.length, (index) {
            final up = _upgrades![index];
            final isHovered = _hoveredIndex == index;
            final progress = isHovered ? (_ticksHovered / _requiredTicks) : 0.0;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: GestureDetector(
                onTap: () => _selectUpgrade(index),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Container(
                      key: _cardKeys[index],
                      width: 200,
                      height: 300,
                      decoration: BoxDecoration(
                        color: isHovered
                            ? Colors.indigo.shade800
                            : Colors.indigo.shade900.withOpacity(0.9),
                        border: Border.all(
                          color: isHovered ? Colors.yellowAccent : Colors.cyan,
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: (isHovered ? Colors.yellow : Colors.cyan)
                                .withOpacity(0.4),
                            blurRadius: isHovered ? 20 : 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            up.name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            up.description,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          const Text(
                            "Hover to Select",
                            style: TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Progress Bar
                    if (isHovered)
                      Container(
                        width: 200,
                        height: 10,
                        margin: const EdgeInsets.only(bottom: 20),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.grey,
                          valueColor: const AlwaysStoppedAnimation(
                            Colors.yellowAccent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
