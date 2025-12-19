import 'dart:math';
import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';
import '../services/camera_input_service.dart';
import 'upgrade_manager.dart';

enum GameState { playing, upgrading, gameOver }

class DefenseGame extends FlameGame with HasCollisionDetection {
  final CameraInputService cameraInput;
  late Tower tower;
  late Crosshair crosshair; // Expose for UI
  late UpgradeManager upgradeManager;

  // Wave System
  int currentWave = 1;
  int enemiesSpawned = 0;
  int enemiesToSpawn = 5;
  GameState gameState = GameState.playing;

  DefenseGame(this.cameraInput);

  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async {
    upgradeManager = UpgradeManager();
    await upgradeManager.loadUpgrades();

    tower = Tower();
    tower.position = size / 2;
    add(tower);

    crosshair = Crosshair();
    add(crosshair);

    startWave(1);
    add(EnemySpawner());
  }

  void startWave(int wave) {
    currentWave = wave;
    enemiesSpawned = 0;
    // Scale enemies count: 5, 7, 9...
    enemiesToSpawn = 5 + (currentWave - 1) * 2;
    gameState = GameState.playing;
    overlays.remove('UpgradeMenu');

    // Show Wave Title
    overlays.add('WaveTitle');
    Future.delayed(
      const Duration(seconds: 2),
      () => overlays.remove('WaveTitle'),
    );
  }

  void onWaveComplete() {
    gameState = GameState.upgrading;
    overlays.add('UpgradeMenu');
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Always update Input/Crosshair
    if (cameraInput.fingerPosition != null) {
      final target = Vector2(
        cameraInput.fingerPosition!.dx * size.x,
        cameraInput.fingerPosition!.dy * size.y,
      );

      // Visual Smoothing
      final double smoothSpeed = 25.0;
      final double t = (smoothSpeed * dt).clamp(0.0, 1.0);
      crosshair.position.lerp(target, t);
      crosshair.opacity = 1.0;

      // Only face/shoot if playing
      if (gameState == GameState.playing) {
        tower.lookAt(crosshair.position);
        tower.tryShoot(this, crosshair.position);

        // Check if on target
        bool hit = false;
        // Optimization: Use functional approach or loop
        for (final enemy in children.whereType<Enemy>()) {
          // 50 is a rough radius combining crosshair and enemy size
          if (enemy.position.distanceTo(crosshair.position) < 50) {
            hit = true;
            break;
          }
        }
        crosshair.isOnTarget = hit;
      }
    } else {
      crosshair.opacity = 0.0;
    }

    // Game Logic only if Playing
    if (gameState == GameState.playing) {
      // Check Wave Completion
      if (enemiesSpawned >= enemiesToSpawn) {
        if (children.whereType<Enemy>().isEmpty) {
          onWaveComplete();
        }
      }
    }
  }

  void gameOver() {
    gameState = GameState.gameOver;
    overlays.add('GameOver');
  }

  void resetGame() {
    currentWave = 1;
    tower.reset();
    children.whereType<Enemy>().forEach((e) => e.removeFromParent());
    children.whereType<Bullet>().forEach((b) => b.removeFromParent());
    overlays.remove('GameOver');
    startWave(1);
  }

  void applyUpgrade(UpgradeDefinition upgrade) {
    tower.applyUpgrade(upgrade);
    startWave(currentWave + 1);
  }
}

class Crosshair extends CircleComponent {
  bool isOnTarget = false;

  Crosshair()
    : super(
        radius: 15, // Smaller radius
        anchor: Anchor.center,
      );

  @override
  void render(Canvas canvas) {
    // super.render(canvas); // Removing white circle

    final color = isOnTarget
        ? const Color(0xFF8B0000)
        : const Color(0xFF00FF00); // Deep Red or Bright Green
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final double r = radius;
    final double bracketLen = r * 0.6; // Length of the corner arms

    // Top Left
    canvas.drawLine(Offset(0, 0), Offset(bracketLen, 0), paint);
    canvas.drawLine(Offset(0, 0), Offset(0, bracketLen), paint);

    // Top Right
    canvas.drawLine(Offset(r * 2, 0), Offset(r * 2 - bracketLen, 0), paint);
    canvas.drawLine(Offset(r * 2, 0), Offset(r * 2, bracketLen), paint);

    // Bottom Left
    canvas.drawLine(Offset(0, r * 2), Offset(bracketLen, r * 2), paint);
    canvas.drawLine(Offset(0, r * 2), Offset(0, r * 2 - bracketLen), paint);

    // Bottom Right
    canvas.drawLine(
      Offset(r * 2, r * 2),
      Offset(r * 2 - bracketLen, r * 2),
      paint,
    );
    canvas.drawLine(
      Offset(r * 2, r * 2),
      Offset(r * 2, r * 2 - bracketLen),
      paint,
    );

    // Inner dot
    canvas.drawCircle(Offset(r, r), 6, Paint()..color = color);
  }
}

class Tower extends PositionComponent with HasGameRef<DefenseGame> {
  double _shootTimer = 0;

  // Stats
  double fireRate = 0.5; // Seconds per shot (lower is faster)
  double damage = 1.0;
  double bulletSpeed = 600.0;

  int maxHp = 5;
  late int hp;

  final Paint _glowPaint = Paint()
    ..color = Colors.cyanAccent.withOpacity(0.6)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
  final Paint _corePaint = Paint()..color = Colors.cyan;

  Tower() : super(size: Vector2(50, 50), anchor: Anchor.center) {
    hp = maxHp;
  }

  void applyUpgrade(UpgradeDefinition up) {
    if (up.stat == 'damage') damage += up.value;
    if (up.stat == 'fireRate') {
      fireRate += up.value;
      if (fireRate < 0.1) fireRate = 0.1; // Cap speed
    }
    if (up.stat == 'speed') bulletSpeed += up.value;
  }

  @override
  void render(Canvas canvas) {
    canvas.drawCircle(Offset(width / 2, height / 2), 25, _glowPaint);
    canvas.drawCircle(Offset(width / 2, height / 2), 15, _corePaint);

    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(width / 2, height / 2),
      Offset(width, height / 2),
      paint,
    );

    // HP Bar
    final hpPercent = hp / maxHp;
    canvas.drawRect(
      Rect.fromLTWH(0, -10, size.x, 5),
      Paint()..color = Colors.grey.withOpacity(0.5),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, -10, size.x * hpPercent, 5),
      Paint()..color = hpPercent > 0.3 ? Colors.green : Colors.red,
    );
  }

  void takeDamage(int amount) {
    hp -= amount;
    if (hp <= 0) {
      hp = 0;
      gameRef.gameOver();
    }
  }

  void reset() {
    hp = maxHp;
    // Reset stats? Or keep upgrades? Rogue-lites usually reset on Death.
    damage = 1.0;
    fireRate = 0.5;
    bulletSpeed = 600.0;
  }

  void tryShoot(DefenseGame game, Vector2 target) {
    if (_shootTimer >= fireRate) {
      _shootTimer = 0;
      final direction = (target - position).normalized();
      final startPos = position + direction * 25;
      game.add(Bullet(startPos, direction, damage, bulletSpeed));
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _shootTimer += dt;
  }
}

class Bullet extends CircleComponent
    with CollisionCallbacks, HasGameRef<DefenseGame> {
  final Vector2 direction;
  final double speed;
  final double damage;

  Bullet(Vector2 position, this.direction, this.damage, this.speed)
    : super(
        radius: 5,
        position: position,
        anchor: Anchor.center,
        paint: Paint()
          ..color = Colors.yellowAccent
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      ) {
    add(CircleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);
    position += direction * speed * dt;
    if (position.x < -100 ||
        position.x > gameRef.size.x + 100 ||
        position.y < -100 ||
        position.y > gameRef.size.y + 100) {
      removeFromParent();
    }
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Enemy) {
      removeFromParent();
      other.takeDamage(damage);
    }
  }
}

class Enemy extends RectangleComponent
    with CollisionCallbacks, HasGameRef<DefenseGame> {
  final Vector2 targetPosition;
  final double speed = 100;
  double hp;

  Enemy(Vector2 startPosition, this.targetPosition, this.hp)
    : super(
        position: startPosition,
        size: Vector2(30, 30),
        anchor: Anchor.center,
        paint: Paint()..color = Colors.redAccent,
      ) {
    add(RectangleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);
    Vector2 dir = (targetPosition - position).normalized();
    position += dir * speed * dt;
    angle += dt * 2;

    if (position.distanceTo(targetPosition) < 25) {
      if (gameRef.tower.hp > 0) gameRef.tower.takeDamage(1);
      removeFromParent();
    }
  }

  void takeDamage(double amount) {
    hp -= amount;
    if (hp <= 0) {
      removeFromParent();
    } else {
      add(
        ColorEffect(
          Colors.white,
          EffectController(duration: 0.1, alternate: true, repeatCount: 1),
        ),
      );
    }
  }
}

class EnemySpawner extends Component with HasGameRef<DefenseGame> {
  double _timer = 0;
  double _interval = 2.0;

  @override
  void update(double dt) {
    if (gameRef.gameState != GameState.playing) return;
    if (gameRef.enemiesSpawned >= gameRef.enemiesToSpawn) return;

    _timer += dt;
    // Scale interval inversely with wave? Or keep constant?
    // Let's speed up slightly every wave
    final waveInterval = max(0.5, 2.0 - (gameRef.currentWave * 0.1));

    if (_timer >= waveInterval) {
      _timer = 0;
      spawnEnemy();
    }
  }

  void spawnEnemy() {
    final gameSize = gameRef.size;
    final random = Random();
    int side = random.nextInt(4);
    Vector2 startPos = Vector2.zero();

    switch (side) {
      case 0:
        startPos = Vector2(random.nextDouble() * gameSize.x, -50);
        break;
      case 1:
        startPos = Vector2(gameSize.x + 50, random.nextDouble() * gameSize.y);
        break;
      case 2:
        startPos = Vector2(random.nextDouble() * gameSize.x, gameSize.y + 50);
        break;
      case 3:
        startPos = Vector2(-50, random.nextDouble() * gameSize.y);
        break;
    }

    // HP Calculation:
    // Wave 1: 2 HP (2 shots of 1 dmg)
    // Scale slowly.
    // Wave 1: 2
    // Wave 2: 2.5 (3 shots?)
    // Wave 5: 4
    double waveHp = 2.0 + (gameRef.currentWave - 1) * 0.5;

    gameRef.add(Enemy(startPos, gameRef.size / 2, waveHp));
    gameRef.enemiesSpawned++;
  }
}
