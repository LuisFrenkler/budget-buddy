// Round profile picture: photo when set, else the name's first letter on the
// brand gradient. Listens to AvatarService so picks update everywhere.
import 'package:flutter/material.dart';
import '../services/avatar_service.dart';
import '../utils/theme.dart';

class UserAvatar extends StatelessWidget {
  final String? name;
  final double size;
  final double fontSize;
  final bool brandGradient;

  const UserAvatar({
    super.key,
    this.name,
    this.size = 64,
    this.fontSize = 26,
    this.brandGradient = true,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AvatarService.changed,
      builder: (_, __, ___) {
        final bytes = AvatarService.bytes();
        final initial = (name == null || name!.trim().isEmpty) ? '?' : name!.trim()[0].toUpperCase();
        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: brandGradient ? null : AppColors.surfaceAlt,
            gradient: brandGradient
                ? const LinearGradient(
                    colors: AppColors.heroBrand, begin: Alignment.topLeft, end: Alignment.bottomRight)
                : null,
            image: bytes == null
                ? null
                : DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover),
          ),
          child: bytes != null
              ? null
              : name == null
                  ? Icon(Icons.person_rounded, color: brandGradient ? Colors.white : AppColors.primary, size: size * 0.5)
                  : Text(initial,
                      style: TextStyle(
                        color: brandGradient ? Colors.white : AppColors.primary,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w800,
                      )),
        );
      },
    );
  }
}
