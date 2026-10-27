import 'package:flutter/material.dart';
import '../utils/theme.dart';

// The grouped rows used on the settings pages (profile, account, about).

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8, left: 4),
        child: Text(text, style: TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.bold)),
      );
}

class SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const SettingsGroup(this.children, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 60, color: AppColors.border),
            children[i],
          ],
        ]),
      );
}

class SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;
  final bool external;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.trailing,
    this.danger = false,
    this.external = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: danger ? AppColors.errorText : AppColors.text)),
              if (subtitle != null)
                Text(subtitle!,
                    style: TextStyle(color: AppColors.textDim, fontSize: 12), overflow: TextOverflow.ellipsis),
            ]),
          ),
          // the value sits right next to the chevron, at most about half the row
          if (value != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.45),
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(value!,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textDim, fontSize: 14)),
              ),
            ),
          if (trailing != null) trailing!,
          if (trailing == null && onTap != null && !danger)
            Icon(external ? Icons.open_in_new_rounded : Icons.chevron_right_rounded,
                color: AppColors.textDim, size: external ? 18 : 24),
        ]),
      ),
    );
  }
}
