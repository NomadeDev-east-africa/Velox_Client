import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nomade_client/theme/app_colors.dart';

class OnboardContent extends StatelessWidget {
  const OnboardContent({
    super.key,
    required this.illustration,
    required this.title,
    required this.text,
    required this.c,
  });

  final String? illustration, title, text;
  final AppColors c;

  /// Met en avant le mot « Velox » en vert (couleur de marque) dans le titre.
  TextSpan _titleSpans() {
    final parts = (title ?? '').split('Velox');
    final spans = <TextSpan>[];
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) spans.add(TextSpan(text: parts[i]));
      if (i < parts.length - 1) {
        spans.add(TextSpan(
          text: 'Velox',
          style: TextStyle(color: c.primary),
        ));
      }
    }
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: [
          Expanded(
            child: SvgPicture.asset(
              illustration!,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 40),
          Text.rich(
            _titleSpans(),
            style: GoogleFonts.poppins(
              color: c.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 24,
              letterSpacing: -0.5,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            text!,
            style: GoogleFonts.inter(
              color: c.onSurfaceVariant,
              height: 1.6,
              fontSize: 15,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}