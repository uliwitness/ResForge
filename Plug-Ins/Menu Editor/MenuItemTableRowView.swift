import Cocoa

class MenuItemTableRowView : NSTableRowView {
    
    enum RowStyle {
        case titleCell
        case firstItemCell
        case lastItemCell
        case middleCell // most cells
        case onlyCell
    }
    
    enum ContentStyle {
        case normal
        case separator
    }
    
    var rowStyle = RowStyle.middleCell
    var contentStyle = ContentStyle.normal
    
    override func draw(_ dirtyRect: NSRect) {
        var box = bounds.insetBy(dx: 2, dy: 0)
        
        NSColor.black.setStroke()
        
        switch rowStyle {
            
        case .titleCell:
            box.origin.x += 16 // keep these two lines in sync with XIB "Mark" and "Shortcut" column widths.
            box.size.width -= 16 + 25;
            if !isSelected {
                NSColor.darkGray.setFill()
            } else {
                NSColor.selectedMenuItemColor.setFill()
            }
            NSBezierPath.fill(box)
        case .lastItemCell:
            box.origin.y -= 10 + 1 // 1 extra for shadow.
            box.size.height += 10
            var shadowBox = box.offsetBy(dx: 2, dy: 1)
            shadowBox.size.width -= 1
            NSColor.black.setFill()
            NSBezierPath.fill(shadowBox)
            if !isSelected {
                NSColor.white.setFill()
            } else {
                NSColor.selectedMenuItemColor.setFill()
            }
            NSBezierPath.fill(box)
            NSBezierPath.stroke(box.insetBy(dx: 0.5, dy: 0.5))
        case .firstItemCell:
            box.size.height += 20
            let shadowBox = box.offsetBy(dx: 1, dy: 2)
            NSColor.black.setFill()
            NSBezierPath.fill(shadowBox)
            if !isSelected {
                NSColor.white.setFill()
            } else {
                NSColor.selectedMenuItemColor.setFill()
            }
            NSBezierPath.fill(box)
            NSBezierPath.stroke(box.insetBy(dx: 0.5, dy: 0.5))
        case .middleCell:
            box.origin.y -= 10
            box.size.height += 20
            let shadowBox = box.offsetBy(dx: 1, dy: 1)
            NSColor.black.setFill()
            NSBezierPath.fill(shadowBox)
            if !isSelected {
                NSColor.white.setFill()
            } else {
                NSColor.selectedMenuItemColor.setFill()
            }
            NSBezierPath.fill(box)
            NSBezierPath.stroke(box.insetBy(dx: 0.5, dy: 0.5))
        case .onlyCell:
            let shadowBox = box.offsetBy(dx: 1, dy: 1)
            NSColor.black.setFill()
            NSBezierPath.fill(shadowBox)
            if !isSelected {
                NSColor.white.setFill()
            } else {
                NSColor.selectedMenuItemColor.setFill()
            }
            NSBezierPath.fill(box)
            NSBezierPath.stroke(box.insetBy(dx: 0.5, dy: 0.5))
        }
        
        if contentStyle == .separator {
            let contentBox = bounds.insetBy(dx: 2, dy: 0)
            NSColor.lightGray.setStroke()
            NSBezierPath.strokeLine(from: NSPoint(x: contentBox.minX + 1, y: trunc(contentBox.midY) + 0.5), to: NSPoint(x: contentBox.maxX - 1, y: trunc(contentBox.midY) + 0.5))
        }
    }
    
}
