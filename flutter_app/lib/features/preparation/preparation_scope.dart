import 'package:flutter/widgets.dart';

import 'preparation_controller.dart';

class PreparationScope extends InheritedNotifier<PreparationController> {
  const PreparationScope({
    required PreparationController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);
  static PreparationController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PreparationScope>()?.notifier;
}
