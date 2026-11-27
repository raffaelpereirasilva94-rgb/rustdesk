import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Keep native IconButton sizing, semantics, tooltip, focus and activation.
/// On Windows, paint hover only inside the actual button bounds instead of
/// Material 2's unbounded radial InkResponse. Other platforms are unchanged.
class MrDeskIconButton extends IconButton {
  const MrDeskIconButton({
    super.key,
    super.iconSize,
    super.visualDensity,
    super.padding,
    super.alignment,
    super.splashRadius,
    super.color,
    super.focusColor,
    super.hoverColor,
    super.highlightColor,
    super.splashColor,
    super.disabledColor,
    required super.onPressed,
    super.mouseCursor,
    super.focusNode,
    super.autofocus,
    super.tooltip,
    super.enableFeedback,
    super.constraints,
    super.style,
    super.isSelected,
    super.selectedIcon,
    required super.icon,
  });

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return super.build(context);
    }
    final theme = Theme.of(context);
    // Material 3 may receive an explicit ButtonStyle overlay. Suppress just
    // its hovered state, preserving keyboard focus and pressed feedback.
    final overlay = style?.overlayColor;
    final boundedStyle = overlay == null ? style : style!.copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>((states) {
        if (states.contains(MaterialState.hovered) &&
            !states.contains(MaterialState.focused) &&
            !states.contains(MaterialState.pressed)) {
          return Colors.transparent;
        }
        return overlay.resolve(states);
      }),
    );
    return _MrDeskHoverSurface(
      enabled: onPressed != null,
      hoverColor: hoverColor ?? theme.hoverColor,
      child: IconButton(
        iconSize: iconSize,
        visualDensity: visualDensity,
        padding: padding,
        alignment: alignment,
        splashRadius: splashRadius,
        color: color,
        focusColor: focusColor,
        hoverColor: Colors.transparent,
        highlightColor: highlightColor,
        splashColor: splashColor,
        disabledColor: disabledColor,
        onPressed: onPressed,
        mouseCursor: mouseCursor,
        focusNode: focusNode,
        autofocus: autofocus,
        tooltip: tooltip,
        enableFeedback: enableFeedback,
        constraints: constraints,
        style: boundedStyle,
        isSelected: isSelected,
        selectedIcon: selectedIcon,
        icon: icon,
      ),
    );
  }
}

class _MrDeskHoverSurface extends StatefulWidget {
  const _MrDeskHoverSurface({
    required this.enabled, required this.hoverColor, required this.child,
  });

  final bool enabled;
  final Color hoverColor;
  final Widget child;

  @override
  State<_MrDeskHoverSurface> createState() => _MrDeskHoverSurfaceState();
}

class _MrDeskHoverSurfaceState extends State<_MrDeskHoverSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: ColoredBox(
        color: widget.enabled && _hovered
            ? widget.hoverColor : Colors.transparent,
        // The local material and clip also contain the native focus/press ink.
        child: Material(
          type: MaterialType.transparency,
          child: widget.child,
        ),
      ),
    ),
  );
}
