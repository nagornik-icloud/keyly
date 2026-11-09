import SwiftUI
import UniformTypeIdentifiers

/// Dragging list rows — ONE mechanism for the whole app.
///
/// There used to be two: snippets were dragged via `onDrag`/`onDrop` on cards, launch
/// targets via `List` + `onMove`. The difference was visible right away: one worked but
/// looked clumsy, snippets simply dragged more nicely. One concept with two
/// implementations always diverges — the only question is who notices first.
///
/// `List` does not fit technically either: it needs a container height known in advance,
/// while rows have variable height (a snippet card is an accordion).
///
/// The order changes LIVE while a row is dragged: the user sees where it will land before
/// releasing the button. Saving happens once, on `performDrop`, otherwise every mouse
/// move would write to `UserDefaults`.
struct ReorderDropDelegate<Item: Identifiable>: DropDelegate where Item.ID: Equatable {
    let targetIndex: Int
    @Binding var items: [Item]
    @Binding var draggingId: Item.ID?
    let onReorder: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingId,
              let from = items.firstIndex(where: { $0.id == draggingId }),
              from != targetIndex else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            let moved = items.remove(at: from)
            items.insert(moved, at: min(targetIndex, items.count))
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingId = nil
        onReorder()
        return true
    }
}

/// Visible drag handle.
///
/// Needed for two reasons at once. Without it the capability is INVISIBLE: only someone who
/// already knew would guess a row can be dragged. And, more importantly, the whole row used to
/// be the drag source, while it contains a hotkey recorder field (NSView). In the app list
/// this ended with the Keyly WINDOW moving instead of the row: the gesture never reached
/// `onDrag` and was picked up by `isMovableByWindowBackground`.
struct KeylyDragHandle: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.Colors.fgDim)
            .frame(width: 22, height: 26)
            .contentShape(Rectangle())
            .help("reorder.handle".loc)
    }
}

extension View {
    /// Makes the row ACCEPT drops. The source is a separate handle
    /// (`keylyDragSource`), not the whole row: the row contains other interactive controls.
    func keylyReorderTarget<Item: Identifiable>(index: Int,
                                                id: Item.ID,
                                                items: Binding<[Item]>,
                                                draggingId: Binding<Item.ID?>,
                                                onReorder: @escaping () -> Void) -> some View
    where Item.ID: Equatable {
        self
            .opacity(draggingId.wrappedValue == id ? 0.4 : 1)
            .onDrop(of: [.text],
                    delegate: ReorderDropDelegate(targetIndex: index,
                                                  items: items,
                                                  draggingId: draggingId,
                                                  onReorder: onReorder))
    }

    /// Makes the element a drag SOURCE.
    ///
    /// Attached to the WHOLE row, not the handle: with the handle the user saw three stripes
    /// being dragged while the row stayed in place until the drop — "I'm not moving the row,
    /// I'm only moving these three stripes". The handle stays as a sign that "this can be
    /// dragged", but the whole row is pulled.
    func keylyDragSource<ID: CustomStringConvertible>(id: ID,
                                                      draggingId: Binding<ID?>) -> some View {
        onDrag {
            draggingId.wrappedValue = id
            return NSItemProvider(object: id.description as NSString)
        } preview: {
            // The drag preview is the row itself: without it the system draws a snapshot of only
            // the element the gesture is attached to.
            self
        }
    }
}
