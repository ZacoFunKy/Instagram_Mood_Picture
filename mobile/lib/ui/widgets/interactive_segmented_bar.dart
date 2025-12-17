import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class InteractiveSegmentedBar extends StatefulWidget {
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
  State<InteractiveSegmentedBar> createState() =>
      _InteractiveSegmentedBarState();
}

class _InteractiveSegmentedBarState extends State<InteractiveSegmentedBar> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(widget.emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
            Text(
              "${(widget.value * 100).toInt()}%",
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: widget.color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onHorizontalDragUpdate: (details) {
            RenderBox box = context.findRenderObject() as RenderBox;
            double width = box.size.width;
            double dx = details.localPosition.dx;
            double newValue = (dx / width).clamp(0.0, 1.0);
            double snapped = (newValue * 20).round() / 20;
            if (snapped != widget.value) {
              HapticFeedback.selectionClick();
              widget.onChanged(snapped);
            }
          },
          onTapUp: (details) {
            RenderBox box = context.findRenderObject() as RenderBox;
            double width = box.size.width;
            double dx = details.localPosition.dx;
            double newValue = (dx / width).clamp(0.0, 1.0);
            double snapped = (newValue * 20).round() / 20;
            HapticFeedback.selectionClick();
            widget.onChanged(snapped);
          },
          child: Container(
            height: 32,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            padding: const EdgeInsets.all(4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    // Fill
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      width: constraints.maxWidth * widget.value,
                      decoration: BoxDecoration(
                        color: widget.color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    // Bars/Segments
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(10, (index) {
                        return Container(
                          width: 2,
                          color: Colors.black12,
                        );
                      }),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
