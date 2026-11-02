import 'package:flutter/material.dart';

/// Holds each page stationary during playback and retains three passages when
/// advancing. Two lazy slivers permit distant seeks without height estimates.
class TranscriptPassageList extends StatefulWidget {
  const TranscriptPassageList({
    required this.itemCount,
    required this.itemBuilder,
    required this.followIndex,
    required this.resetToken,
    super.key,
  });

  /// Item zero is the header; subsequent items are transcript passages.
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final int? followIndex;
  final int resetToken;

  @override
  State<TranscriptPassageList> createState() => _TranscriptPassageListState();
}

class _TranscriptPassageListState extends State<TranscriptPassageList> {
  final _scroll = ScrollController(keepScrollOffset: false);
  final _centerKey = UniqueKey();
  final _viewportKey = GlobalKey();
  final _items = <int, BuildContext>{};
  late int _pivot;
  int _generation = 0;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _pivot = widget.followIndex ?? 0;
  }

  @override
  void didUpdateWidget(covariant TranscriptPassageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Moving the highlight alone does not change the page anchor.
    if (widget.resetToken != oldWidget.resetToken ||
        _pivot >= widget.itemCount) {
      _pivot = widget.followIndex ?? 0;
      _generation++;
      _items.clear();
    }
  }

  void _showPage(int first) {
    setState(() {
      _pivot = first;
      _generation++;
      _items.clear();
    });
  }

  void _scheduleFollow() {
    if (_scheduled || widget.followIndex == null) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || widget.followIndex == null || !_scroll.hasClients) return;
      final viewport = _viewportKey.currentContext?.findRenderObject();
      if (viewport is! RenderBox ||
          !viewport.hasSize ||
          viewport.size.height <= 0) {
        return;
      }
      final height = viewport.size.height;
      final target = widget.followIndex!;
      _items.removeWhere((_, context) => !context.mounted);
      final fullyVisible = <int>[];
      var targetVisible = false;
      for (final entry in _items.entries) {
        if (entry.key == 0) continue;
        final render = entry.value.findRenderObject();
        if (render is! RenderBox || !render.attached || !render.hasSize) {
          continue;
        }
        final top = render.localToGlobal(Offset.zero, ancestor: viewport).dy;
        final bottom = top + render.size.height;
        final full = top >= -0.5 && bottom <= height + 0.5;
        if (full) fullyVisible.add(entry.key);
        // A passage taller than the viewport cannot fit. Keep it still while
        // visible instead of repeatedly trying to fit it on a new page.
        if (entry.key == target &&
            (full ||
                (render.size.height > height && top < height && bottom > 0))) {
          targetVisible = true;
        }
      }
      if (!targetVisible) {
        // Opening, seeks, resuming after browsing, or a very small viewport.
        _showPage(target);
        return;
      }
      fullyVisible.sort();
      if (fullyVisible.length >= 4 &&
          target >= fullyVisible[fullyVisible.length - 2] &&
          fullyVisible.last < widget.itemCount - 1) {
        final overlapStart = fullyVisible[fullyVisible.length - 3];
        if (overlapStart > _pivot) _showPage(overlapStart);
      }
    });
  }

  Widget _item(BuildContext context, int index) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Builder(
      builder: (context) {
        _items[index] = context;
        return widget.itemBuilder(context, index);
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    _scheduleFollow();
    return ClipRect(
      key: _viewportKey,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _scheduleFollow();
          return false;
        },
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (_) {
            _scheduleFollow();
            return false;
          },
          child: CustomScrollView(
            key: ValueKey(_generation),
            controller: _scroll,
            center: _centerKey,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _item(context, _pivot - index - 1),
                  childCount: _pivot,
                ),
              ),
              SliverList(
                key: _centerKey,
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _item(context, _pivot + index),
                  childCount: widget.itemCount - _pivot,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }
}
