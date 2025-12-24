import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: widget.color.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: widget.color.withOpacity(0.1),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(widget.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: widget.color.withOpacity(0.4)),
                ),
                child: Text(
                  '${(widget.value * 100).toInt()}%',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: widget.color,
                  ),
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
              height: 40,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: widget.color.withOpacity(0.2)),
              ),
              padding: const EdgeInsets.all(4),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      // Fill animated
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        width: constraints.maxWidth * widget.value,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              widget.color.withOpacity(0.35),
                              widget.color.withOpacity(0.15),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: widget.color.withOpacity(0.3),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      // Segments
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(10, (index) {
                          return Container(
                            width: 2,
                            color: Colors.white.withOpacity(0.15),
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
      ),
    ).animate().fadeIn().slideX();
  }
}

