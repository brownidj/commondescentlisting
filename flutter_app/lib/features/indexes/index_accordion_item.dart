import 'package:flutter/material.dart';

/// Parent-owned selection survives lazy-list disposal without restoring an old
/// ExpansionTile flag from PageStorage when another entry has been opened.
class IndexAccordionItem extends StatefulWidget {
  const IndexAccordionItem({
    required this.expanded,
    required this.onExpansionChanged,
    required this.title,
    this.subtitle,
    required this.children,
    super.key,
  });
  final bool expanded;
  final ValueChanged<bool> onExpansionChanged;
  final Widget title;
  final Widget? subtitle;
  final List<Widget> children;

  @override
  State<IndexAccordionItem> createState() => _IndexAccordionItemState();
}

class _IndexAccordionItemState extends State<IndexAccordionItem> {
  final _controller = ExpansibleController();
  final _bucket = PageStorageBucket();

  @override
  void didUpdateWidget(covariant IndexAccordionItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded != oldWidget.expanded) {
      if (widget.expanded) {
        _controller.expand();
      } else {
        _controller.collapse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageStorage(
    bucket: _bucket,
    child: ExpansionTile(
      controller: _controller,
      initiallyExpanded: widget.expanded,
      onExpansionChanged: widget.onExpansionChanged,
      title: widget.title,
      subtitle: widget.subtitle,
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      childrenPadding: const EdgeInsets.all(16),
      children: widget.children,
    ),
  );
}
