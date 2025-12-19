import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;

class UpgradeDefinition {
  final String id;
  final String name;
  final String description;
  final String stat;
  final double value;

  UpgradeDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.stat,
    required this.value,
  });

  factory UpgradeDefinition.fromLine(String line) {
    final parts = line.split('|');
    return UpgradeDefinition(
      id: parts[0],
      name: parts[1],
      description: parts[2],
      stat: parts[3],
      value: double.parse(parts[4]),
    );
  }
}

class UpgradeManager {
  List<UpgradeDefinition> _availableUpgrades = [];
  bool _loaded = false;

  Future<void> loadUpgrades() async {
    if (_loaded) return;
    try {
      final String content = await rootBundle.loadString(
        'assets/data/upgrades.txt',
      );
      final List<String> lines = LineSplitter.split(content).toList();
      _availableUpgrades = lines
          .where((l) => l.isNotEmpty)
          .map((l) => UpgradeDefinition.fromLine(l))
          .toList();
      _loaded = true;
    } catch (e) {
      print("Error loading upgrades: $e");
    }
  }

  List<UpgradeDefinition> getRandomUpgrades(int count) {
    if (!_loaded || _availableUpgrades.isEmpty) return [];
    final random = Random();
    final List<UpgradeDefinition> copy = List.from(_availableUpgrades);
    copy.shuffle(random);
    return copy.take(count).toList();
  }
}
