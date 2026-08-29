import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/material.dart';

const fengWoAccountAvatarAsset = 'assets/images/avatar/fengwo_robot.png';

class FengWoAccountAvatar extends StatelessWidget {
  final double size;

  const FengWoAccountAvatar({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Image.asset(
        fengWoAccountAvatarAsset,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: AppLocalizations.of(context).personalCenter,
      ),
    );
  }
}
