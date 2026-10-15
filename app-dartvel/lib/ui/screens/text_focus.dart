// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// Keyboard focus for the text fields of a functional widget. A Dartvel input
// (`DVText(value, DVModifier().input(...))`) owns its FocusNode, so a screen
// that used to hold one (Ctrl+K into the search field, autofocus on a paste
// box) finds the field's EditableText below it instead.

import 'package:flutter/widgets.dart';

/// Puts the keyboard focus in the first text field under [context], in tree
/// order. False when there is none.
bool focusFirstTextField(BuildContext context) {
  FocusNode? found;
  void visit(Element element) {
    if (found != null) return;
    final Widget widget = element.widget;
    if (widget is EditableText) {
      found = widget.focusNode;
      return;
    }
    element.visitChildren(visit);
  }

  context.visitChildElements(visit);
  found?.requestFocus();
  return found != null;
}
