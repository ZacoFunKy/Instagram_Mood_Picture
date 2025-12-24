import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Service for adaptive weight adjustment based on user history
/// Learns which sources are most predictive for this specific user
class AdaptiveWeightsService {
  static final AdaptiveWeightsService _instance = AdaptiveWeightsService._internal();
  factory AdaptiveWeightsService() => _instance;
  AdaptiveWeightsService._internal();

  // Default weights (same as backend)
  static const Map<String, double> defaultWeights = {
    'energy': 0.15,
    'stress': 0.15,
    'social': 0.10,
    'steps': 0.10,
  };

  /// Get current adaptive weights
  Future<Map<String, double>> getWeights() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final weightsJson = prefs.getString('adaptive_weights');
      
      if (weightsJson != null) {
        final weights = json.decode(weightsJson) as Map<String, dynamic>;
        return weights.map((key, value) => MapEntry(key, (value as num).toDouble()));
      }
    } catch (e) {
      print('⚠️ Load adaptive weights error: $e');
    }
    
    return Map.from(defaultWeights);
  }

  /// Record a prediction vs actual mood for learning
  Future<void> recordPrediction({
    required String predictedMood,
    required String actualMood,
    required double energyLevel,
    required double stressLevel,
    required double socialLevel,
    required int steps,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get history
      final historyJson = prefs.getString('prediction_history') ?? '[]';
      final history = json.decode(historyJson) as List;
      
      // Add new entry
      history.add({
        'predicted': predictedMood,
        'actual': actualMood,
        'energy': energyLevel,
        'stress': stressLevel,
        'social': socialLevel,
        'steps': steps,
        'timestamp': DateTime.now().toIso8601String(),
        'correct': predictedMood == actualMood,
      });
      
      // Keep last 100 entries
      if (history.length > 100) {
        history.removeAt(0);
      }
      
      await prefs.setString('prediction_history', json.encode(history));
      
      // Recompute weights if we have enough data
      if (history.length >= 20) {
        await _recomputeWeights(history);
      }
    } catch (e) {
      print('⚠️ Record prediction error: $e');
    }
  }

  /// Recompute weights based on prediction history
  Future<void> _recomputeWeights(List history) async {
    try {
      // Simple correlation-based weight adjustment
      // For each metric, calculate correlation with prediction accuracy
      
      final weights = Map<String, double>.from(defaultWeights);
      
      // Count correct predictions with high/low values of each metric
      int totalPredictions = history.length;
      
      Map<String, int> highCorrect = {'energy': 0, 'stress': 0, 'social': 0, 'steps': 0};
      Map<String, int> lowCorrect = {'energy': 0, 'stress': 0, 'social': 0, 'steps': 0};
      Map<String, int> highTotal = {'energy': 0, 'stress': 0, 'social': 0, 'steps': 0};
      Map<String, int> lowTotal = {'energy': 0, 'stress': 0, 'social': 0, 'steps': 0};
      
      for (final entry in history) {
        final correct = entry['correct'] as bool;
        final energy = entry['energy'] as double;
        final stress = entry['stress'] as double;
        final social = entry['social'] as double;
        final steps = entry['steps'] as int;
        
        // Energy
        if (energy > 0.6) {
          highTotal['energy'] = highTotal['energy']! + 1;
          if (correct) highCorrect['energy'] = highCorrect['energy']! + 1;
        } else if (energy < 0.4) {
          lowTotal['energy'] = lowTotal['energy']! + 1;
          if (correct) lowCorrect['energy'] = lowCorrect['energy']! + 1;
        }
        
        // Stress
        if (stress > 0.6) {
          highTotal['stress'] = highTotal['stress']! + 1;
          if (correct) highCorrect['stress'] = highCorrect['stress']! + 1;
        } else if (stress < 0.4) {
          lowTotal['stress'] = lowTotal['stress']! + 1;
          if (correct) lowCorrect['stress']!= lowCorrect['stress']! + 1;
        }
        
        // Social
        if (social > 0.6) {
          highTotal['social'] = highTotal['social']! + 1;
          if (correct) highCorrect['social'] = highCorrect['social']! + 1;
        } else if (social < 0.4) {
          lowTotal['social'] = lowTotal['social']! + 1;
          if (correct) lowCorrect['social'] = lowCorrect['social']! + 1;
        }
        
        // Steps
        if (steps >= 10000) {
          highTotal['steps'] = highTotal['steps']! + 1;
          if (correct) highCorrect['steps'] = highCorrect['steps']! + 1;
        } else if (steps < 5000) {
          lowTotal['steps'] = lowTotal['steps']! + 1;
          if (correct) lowCorrect['steps'] = lowCorrect['steps']! + 1;
        }
      }
      
      // Adjust weights based on predictive power
      for (final metric in ['energy', 'stress', 'social', 'steps']) {
        final highAcc = highTotal[metric]! > 0 
            ? highCorrect[metric]! / highTotal[metric]! 
            : 0.5;
        final lowAcc = lowTotal[metric]! > 0 
            ? lowCorrect[metric]! / lowTotal[metric]! 
            : 0.5;
        
        // Average accuracy for this metric
        final avgAcc = (highAcc + lowAcc) / 2;
        
        // Boost weight if metric is predictive (> 60% accuracy)
        if (avgAcc > 0.6) {
          weights[metric] = defaultWeights[metric]! * (1 + (avgAcc - 0.5));
        } else if (avgAcc < 0.4) {
          // Reduce weight if metric is misleading
          weights[metric] = defaultWeights[metric]! * 0.5;
        }
      }
      
      // Normalize weights to sum to 0.5 (same total as default)
      final sum = weights.values.reduce((a, b) => a + b);
      if (sum > 0) {
        weights.updateAll((key, value) => value * 0.5 / sum);
      }
      
      // Save updated weights
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('adaptive_weights', json.encode(weights));
      
      print('🎯 Adaptive weights updated: $weights');
    } catch (e) {
      print('⚠️ Recompute weights error: $e');
    }
  }

  /// Get prediction accuracy stats
  Future<Map<String, dynamic>> getAccuracyStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString('prediction_history') ?? '[]';
      final history = json.decode(historyJson) as List;
      
      if (history.isEmpty) {
        return {'accuracy': 0.0, 'total': 0};
      }
      
      final correct = history.where((e) => e['correct'] == true).length;
      final accuracy = correct / history.length;
      
      return {
        'accuracy': accuracy,
        'total': history.length,
        'correct': correct,
      };
    } catch (e) {
      print('⚠️ Get accuracy stats error: $e');
      return {'accuracy': 0.0, 'total': 0};
    }
  }

  /// Reset weights to default
  Future<void> resetWeights() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('adaptive_weights');
      await prefs.remove('prediction_history');
      print('🔄 Weights reset to default');
    } catch (e) {
      print('⚠️ Reset weights error: $e');
    }
  }
}
