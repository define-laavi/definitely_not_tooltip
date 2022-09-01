import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

typedef TooltipTriggeredCallback = void Function();

enum TooltipLocation {
  bottom,
  left,
  right,
  top;
}

class DNTooltip extends StatefulWidget {
  const DNTooltip({
    super.key,
    required this.content,
    this.height,
    this.padding,
    this.margin,
    this.verticalOffset,
    this.horizontalOffset,
    this.preferedLocation,
    this.decoration,
    this.waitDuration,
    this.onTriggered,
    this.child,
  });

  final Widget content;

  final double? height;

  final EdgeInsetsGeometry? padding;

  final EdgeInsetsGeometry? margin;

  final double? verticalOffset;
  final double? horizontalOffset;

  final TooltipLocation? preferedLocation;

  final Widget? child;

  final Decoration? decoration;

  final Duration? waitDuration;

  final TooltipTriggeredCallback? onTriggered;

  static final List<DNTooltipState> _openedTooltips = <DNTooltipState>[];

  static void _concealOtherTooltips(DNTooltipState current) {
    if (_openedTooltips.isNotEmpty) {
      // Avoid concurrent modification.
      final List<DNTooltipState> openedTooltips = _openedTooltips.toList();
      for (final DNTooltipState state in openedTooltips) {
        if (state == current) {
          continue;
        }
        state._concealTooltip();
      }
    }
  }

  static void _revealLastTooltip() {
    if (_openedTooltips.isNotEmpty) {
      _openedTooltips.last._revealTooltip();
    }
  }

  static bool dismissAllToolTips() {
    if (_openedTooltips.isNotEmpty) {
      final List<DNTooltipState> openedTooltips = _openedTooltips.toList();
      for (final DNTooltipState state in openedTooltips) {
        state._dismissTooltip(immediately: true);
      }
      return true;
    }
    return false;
  }

  @override
  State<DNTooltip> createState() => DNTooltipState();
}

class DNTooltipState extends State<DNTooltip>
    with SingleTickerProviderStateMixin {
  static const double _defaultVerticalOffset = 24.0;
  static const EdgeInsetsGeometry _defaultMargin = EdgeInsets.zero;
  static const Duration _fadeInDuration = Duration(milliseconds: 150);
  static const Duration _fadeOutDuration = Duration(milliseconds: 150);
  static const Duration _defaultHoverShowDuration = Duration(milliseconds: 100);
  static const Duration _defaultWaitDuration = Duration.zero;
  late Widget _content;
  late double _height;
  late EdgeInsetsGeometry _padding;
  late EdgeInsetsGeometry _margin;
  late Decoration _decoration;
  late double _verticalOffset;
  late double _horizontalOffset;
  late TooltipLocation _preferedLocation;
  late AnimationController _controller;
  OverlayEntry? _entry;
  Timer? _dismissTimer;
  Timer? _showTimer;
  late Duration _showDuration;
  late Duration _hoverShowDuration;
  late Duration _waitDuration;
  late bool _mouseIsConnected;
  bool _pressActivated = false;
  late bool _isConcealed;
  late bool _forceRemoval;
  late bool _visible;

  @override
  void initState() {
    super.initState();
    _isConcealed = false;
    _forceRemoval = false;
    _mouseIsConnected = RendererBinding.instance.mouseTracker.mouseIsConnected;
    _controller = AnimationController(
      duration: _fadeInDuration,
      reverseDuration: _fadeOutDuration,
      vsync: this,
    )..addStatusListener(_handleStatusChanged);
    RendererBinding.instance.mouseTracker
        .addListener(_handleMouseTrackerChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TooltipVisibility.of(context);
  }

  double _getDefaultTooltipHeight() {
    final ThemeData theme = Theme.of(context);
    switch (theme.platform) {
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return 24.0;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.iOS:
        return 32.0;
    }
  }

  EdgeInsets _getDefaultPadding() {
    final ThemeData theme = Theme.of(context);
    switch (theme.platform) {
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0);
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.iOS:
        return const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0);
    }
  }

  // Forces a rebuild if a mouse has been added or removed.
  void _handleMouseTrackerChange() {
    if (!mounted) {
      return;
    }
    final bool mouseIsConnected =
        RendererBinding.instance.mouseTracker.mouseIsConnected;
    if (mouseIsConnected != _mouseIsConnected) {
      setState(() {
        _mouseIsConnected = mouseIsConnected;
      });
    }
  }

  void _handleStatusChanged(AnimationStatus status) {
    // If this tip is concealed, don't remove it, even if it is dismissed, so that we can
    // reveal it later, unless it has explicitly been hidden with _dismissTooltip.
    if (status == AnimationStatus.dismissed &&
        (_forceRemoval || !_isConcealed)) {
      _removeEntry();
    }
  }

  void _dismissTooltip({bool immediately = false}) {
    _showTimer?.cancel();
    _showTimer = null;
    if (immediately) {
      _removeEntry();
      return;
    }
    // So it will be removed when it's done reversing, regardless of whether it is
    // still concealed or not.
    _forceRemoval = true;
    if (_pressActivated) {
      _dismissTimer ??= Timer(_showDuration, _controller.reverse);
    } else {
      _dismissTimer ??= Timer(_hoverShowDuration, _controller.reverse);
    }
    _pressActivated = false;
  }

  void _showTooltip({bool immediately = false}) {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    if (immediately) {
      ensureTooltipVisible();
      return;
    }
    _showTimer ??= Timer(_waitDuration, ensureTooltipVisible);
  }

  void _concealTooltip() {
    if (_isConcealed || _forceRemoval) {
      // Already concealed, or it's being removed.
      return;
    }
    _isConcealed = true;
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _showTimer?.cancel();
    _showTimer = null;
    if (_entry != null) {
      _entry!.remove();
    }
    _controller.reverse();
  }

  void _revealTooltip() {
    if (!_isConcealed) {
      // Already uncovered.
      return;
    }
    _isConcealed = false;
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _showTimer?.cancel();
    _showTimer = null;
    if (!_entry!.mounted) {
      final OverlayState overlayState = Overlay.of(
        context,
        debugRequiredFor: widget,
      )!;
      overlayState.insert(_entry!);
    }
    _controller.forward();
  }

  /// Shows the tooltip if it is not already visible.
  ///
  /// Returns `false` when the tooltip shouldn't be shown or when the tooltip
  /// was already visible.
  bool ensureTooltipVisible() {
    if (!_visible || !mounted) {
      return false;
    }
    _showTimer?.cancel();
    _showTimer = null;
    _forceRemoval = false;
    if (_isConcealed) {
      if (_mouseIsConnected) {
        DNTooltip._concealOtherTooltips(this);
      }
      _revealTooltip();
      return true;
    }
    if (_entry != null) {
      // Stop trying to hide, if we were.
      _dismissTimer?.cancel();
      _dismissTimer = null;
      _controller.forward();
      return false; // Already visible.
    }
    _createNewEntry();
    _controller.forward();
    return true;
  }

  static final Set<DNTooltipState> _mouseIn = <DNTooltipState>{};

  void _handleMouseEnter() {
    if (mounted) {
      _showTooltip();
    }
  }

  void _handleMouseExit({bool immediately = false}) {
    if (mounted) {
      // If the tip is currently covered, we can just remove it without waiting.
      _dismissTooltip(immediately: _isConcealed || immediately);
    }
  }

  void _createNewEntry() {
    final OverlayState overlayState = Overlay.of(
      context,
      debugRequiredFor: widget,
    )!;

    final RenderBox box = context.findRenderObject()! as RenderBox;
    final Offset target = box.localToGlobal(
      box.size.center(Offset.zero),
      ancestor: overlayState.context.findRenderObject(),
    );

    // We create this widget outside of the overlay entry's builder to prevent
    // updated values from happening to leak into the overlay when the overlay
    // rebuilds.
    final Widget overlay = Directionality(
      textDirection: Directionality.of(context),
      child: _TooltipOverlay(
        content: _content,
        height: _height,
        padding: _padding,
        margin: _margin,
        onEnter: _mouseIsConnected ? (_) => _handleMouseEnter() : null,
        onExit: _mouseIsConnected ? (_) => _handleMouseExit() : null,
        decoration: _decoration,
        animation: CurvedAnimation(
          parent: _controller,
          curve: Curves.fastOutSlowIn,
        ),
        target: target,
        verticalOffset: _verticalOffset,
        horizontalOffset: _horizontalOffset,
        preferedLocation: _preferedLocation,
      ),
    );
    _entry = OverlayEntry(builder: (BuildContext context) => overlay);
    _isConcealed = false;
    overlayState.insert(_entry!);
    if (_mouseIsConnected) {
      // Hovered tooltips shouldn't show more than one at once. For example, a chip with
      // a delete icon shouldn't show both the delete icon tooltip and the chip tooltip
      // at the same time.
      DNTooltip._concealOtherTooltips(this);
    }
    assert(!DNTooltip._openedTooltips.contains(this));
    DNTooltip._openedTooltips.add(this);
  }

  void _removeEntry() {
    DNTooltip._openedTooltips.remove(this);
    _mouseIn.remove(this);
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _showTimer?.cancel();
    _showTimer = null;
    if (!_isConcealed) {
      _entry?.remove();
    }
    _isConcealed = false;
    _entry = null;
    if (_mouseIsConnected) {
      DNTooltip._revealLastTooltip();
    }
  }

  @override
  void deactivate() {
    if (_entry != null) {
      _dismissTooltip(immediately: true);
    }
    _showTimer?.cancel();
    super.deactivate();
  }

  @override
  void dispose() {
    RendererBinding.instance.mouseTracker
        .removeListener(_handleMouseTrackerChange);
    _removeEntry();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(Overlay.of(context, debugRequiredFor: widget) != null);
    final ThemeData theme = Theme.of(context);
    final TooltipThemeData tooltipTheme = TooltipTheme.of(context);
    final BoxDecoration defaultDecoration;
    if (theme.brightness == Brightness.dark) {
      defaultDecoration = BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      );
    } else {
      defaultDecoration = BoxDecoration(
        color: Colors.grey[700]!.withOpacity(0.9),
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      );
    }

    _content = widget.content;
    _height =
        widget.height ?? tooltipTheme.height ?? _getDefaultTooltipHeight();
    _padding = widget.padding ?? tooltipTheme.padding ?? _getDefaultPadding();
    _margin = widget.margin ?? tooltipTheme.margin ?? _defaultMargin;
    _verticalOffset = widget.verticalOffset ??
        tooltipTheme.verticalOffset ??
        _defaultVerticalOffset;
    _horizontalOffset = widget.horizontalOffset ?? 0;
    _preferedLocation = widget.preferedLocation ?? TooltipLocation.bottom;
    _decoration =
        widget.decoration ?? tooltipTheme.decoration ?? defaultDecoration;
    _waitDuration = widget.waitDuration ??
        tooltipTheme.waitDuration ??
        _defaultWaitDuration;
    _hoverShowDuration = _defaultHoverShowDuration;

    Widget result = Semantics(
      tooltip: null,
      child: widget.child,
    );

    // Only check for gestures if tooltip should be visible.
    if (_visible) {
      result = MouseRegion(
        onEnter: (_) => _handleMouseEnter(),
        onExit: (_) => _handleMouseExit(),
        child: result,
      );
    }

    return result;
  }
}

class _TooltipPositionDelegate extends SingleChildLayoutDelegate {
  _TooltipPositionDelegate({
    required this.target,
    required this.verticalOffset,
    required this.horizontalOffset,
    required this.preferedLocation,
  });

  final Offset target;
  final double verticalOffset;
  final double horizontalOffset;
  final TooltipLocation preferedLocation;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return positionDependentBox(
        size: size,
        childSize: childSize,
        target: target,
        verticalOffset: verticalOffset,
        horizontalOffset: horizontalOffset,
        preferedLocation: preferedLocation);
  }

  @override
  bool shouldRelayout(_TooltipPositionDelegate oldDelegate) {
    return target != oldDelegate.target ||
        verticalOffset != oldDelegate.verticalOffset ||
        horizontalOffset != oldDelegate.horizontalOffset;
  }
}

class _TooltipOverlay extends StatelessWidget {
  const _TooltipOverlay({
    required this.height,
    required this.content,
    this.padding,
    this.margin,
    this.decoration,
    required this.animation,
    required this.target,
    required this.verticalOffset,
    required this.horizontalOffset,
    required this.preferedLocation,
    this.onEnter,
    this.onExit,
  });

  final Widget content;
  final double height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Decoration? decoration;
  final Animation<double> animation;
  final Offset target;
  final double verticalOffset;
  final double horizontalOffset;
  final TooltipLocation preferedLocation;
  final PointerEnterEventListener? onEnter;
  final PointerExitEventListener? onExit;

  @override
  Widget build(BuildContext context) {
    Widget result = IgnorePointer(
        child: ScaleTransition(
      scale: animation,
      child: FadeTransition(
        opacity: animation,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: Container(
            decoration: decoration,
            padding: padding,
            margin: margin,
            child: Center(
              widthFactor: 1.0,
              heightFactor: 1.0,
              child: Material(child: content),
            ),
          ),
        ),
      ),
    ));
    if (onEnter != null || onExit != null) {
      result = MouseRegion(
        onEnter: onEnter,
        onExit: onExit,
        child: result,
      );
    }
    return Positioned.fill(
      bottom: MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0.0,
      child: CustomSingleChildLayout(
        delegate: _TooltipPositionDelegate(
          target: target,
          verticalOffset: verticalOffset,
          horizontalOffset: horizontalOffset,
          preferedLocation: preferedLocation,
        ),
        child: result,
      ),
    );
  }
}

Offset positionDependentBox({
  required Size size,
  required Size childSize,
  required Offset target,
  required TooltipLocation preferedLocation,
  double verticalOffset = 0.0,
  double horizontalOffset = 0.0,
  double margin = 10.0,
}) {
  // VERTICAL DIRECTION
  bool preferBelow = preferedLocation == TooltipLocation.bottom;
  bool preferVertical = preferBelow || preferedLocation == TooltipLocation.top;
  if (preferVertical) {
    final bool fitsBelow =
        target.dy + verticalOffset + childSize.height <= size.height - margin;
    final bool fitsAbove =
        target.dy - verticalOffset - childSize.height >= margin;

    final bool tooltipBelow =
        preferBelow ? fitsBelow || !fitsAbove : !(fitsAbove || !fitsBelow);
    double y;
    if (tooltipBelow) {
      y = math.min(target.dy + verticalOffset, size.height - margin);
    } else {
      y = math.max(target.dy - verticalOffset - childSize.height, margin);
    }
    // HORIZONTAL DIRECTION
    double x;
    if (size.width - margin * 2.0 < childSize.width) {
      x = (size.width - childSize.width) / 2.0;
    } else {
      final double normalizedTargetX =
          clampDouble(target.dx, margin, size.width - margin);
      final double edge = margin + childSize.width / 2.0;
      if (normalizedTargetX < edge) {
        x = margin;
      } else if (normalizedTargetX > size.width - edge) {
        x = size.width - margin - childSize.width;
      } else {
        x = normalizedTargetX - childSize.width / 2.0;
      }
    }
    return Offset(x, y);
  } else {
    bool preferRight = preferedLocation == TooltipLocation.right;
    final bool fitsRight =
        target.dx + horizontalOffset + childSize.width <= size.width - margin;
    final bool fitsLeft =
        target.dx - horizontalOffset - childSize.width >= margin;
    final bool tooltipRight =
        preferRight ? fitsRight || !fitsLeft : !(fitsLeft || !fitsRight);

    double x;
    if (tooltipRight) {
      x = math.min(target.dx + horizontalOffset, size.width - margin);
    } else {
      x = math.max(target.dx - horizontalOffset - childSize.width, margin);
    }

    double y;
    if (size.height - margin * 2.0 < childSize.height) {
      y = (size.height - childSize.height) / 2.0;
    } else {
      final double normalizedTargetY =
          clampDouble(target.dy, margin, size.height - margin);
      final double edge = margin + childSize.height / 2.0;
      if (normalizedTargetY < edge) {
        y = margin;
      } else if (normalizedTargetY > size.height - edge) {
        y = size.height - margin - childSize.height;
      } else {
        y = normalizedTargetY - childSize.height / 2.0;
      }
    }
    return Offset(x, y);
  }
}
