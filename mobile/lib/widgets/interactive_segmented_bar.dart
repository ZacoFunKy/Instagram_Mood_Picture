import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class InteractiveSegmentedBar extends StatelessWidget {
  final String label;
  final String emoji;
  final double value; // 0.0 to 1.0
  final Color color;
  final Function(double) onChanged;

  const InteractiveSegmentedBar({
    super.key,
    required this.label,
    required this.emoji,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(label,
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.white70,
                      letterSpacing: 1.5)),
            ]),
            Text("${(value * 10.0).toStringAsFixed(1)}",
                style: GoogleFonts.inter(
                    color: color, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onPanUpdate: (details) {
            _updateValue(context, details.localPosition.dx);
          },
          onTapDown: (details) {
            _updateValue(context, details.localPosition.dx);
          },
          child: Container(
            height: 24,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      width: constraints.maxWidth * value,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color.withOpacity(0.5), color],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: color.withOpacity(0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 2))
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _updateValue(BuildContext context, double dx) {
    // Basic approximation assuming full width minus padding
    double totalWidth = MediaQuery.of(context).size.width - 48; // 24*2 padding
    double newVal = (dx / totalWidth).clamp(0.0, 1.0);

    if (newVal != value) {
      if ((newVal - value).abs() > 0.05) HapticFeedback.lightImpact();
      onChanged(newVal);
    }
  }
}
