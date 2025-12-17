import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class NeonBtn extends StatelessWidget {
  final VoidCallback onTap;
  final String text;
  final Color color;
  final bool isLoading;

  const NeonBtn({
    super.key,
    required this.onTap,
    required this.text,
    required this.color,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                  ),
                )
              : Text(
                  text,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    letterSpacing: 1.5,
                  ),
                ),
        ),
      ),
    );
  }
}
