//
//  NSView+FirstTextField.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit

extension NSView {
    func findFirstTextField() -> NSTextField? {
        if let textField = self as? NSTextField, textField.isEditable {
            return textField
        }
        for subview in subviews {
            if let found = subview.findFirstTextField() {
                return found
            }
        }
        return nil
    }
}
