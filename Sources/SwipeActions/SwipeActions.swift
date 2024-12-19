//
//  SwipeActions.swift
//
//
//  Created by Kristian Kiraly on 2/7/24.
//

import SwiftUI

fileprivate extension CGSize {
    static func +(lhs: CGSize, rhs: CGSize) -> CGSize {
        return CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
}

fileprivate struct Offset: Equatable {
    var current: CGSize
    var stored: CGSize
    
    init() {
        current = .zero
        stored = .zero
    }
    
    var totalWidth: CGFloat {
        current.width + stored.width
    }
}

fileprivate extension String {
    var renderedWidth: CGFloat {
        let font = UIFont.systemFont(ofSize: 17)
        
        let attributes: [NSAttributedString.Key : Any] = [.font : font]
        
        let nsString = self as NSString
        
        return nsString.size(withAttributes: attributes).width
    }
}

fileprivate struct DragGestureStorage: Equatable {
    var dragOffset: CGSize
    var predictedDragEnd: CGSize
    
    var isDragging: Bool {
        dragOffset != .zero && predictedDragEnd != .zero
    }
}

fileprivate enum SwipeDirection {
    case left
    case right
    
    init(oldGestureStorage: DragGestureStorage, newGestureStorage: DragGestureStorage) {
        //-35 - -25 = -10 > right
        //35 - 45 = -10 > right
        //35 - 25 = 10 < left
        //-35 - -45 = 10 < left
        if oldGestureStorage.dragOffset.width - newGestureStorage.dragOffset.width < 0 {
            self = .right
        } else {
            self = .left
        }
    }
}

fileprivate struct SwipeActionModifier: ViewModifier {
    var rightSwipeActions: SwipeActionGroup? = nil
    var leftSwipeActions: SwipeActionGroup? = nil
    @State private var storedSwipeDirection: SwipeDirection? = nil
    @State private var offset = Offset()
    
    @GestureState private var gestureState: DragGestureStorage = .init(dragOffset: .zero, predictedDragEnd: .zero)
    
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .offset(x: offset.totalWidth)
            .background {
                swipeActionButtons
            }
            .animation(.default, value: offset)
            .gesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .local)
                    .updating($gestureState, body: { value, state, transaction in
                        state = .init(dragOffset: value.translation, predictedDragEnd: value.predictedEndTranslation)
                    })
            )
            .onChange(of: gestureState) { [oldValue=gestureState] newValue in
                let currentSwipeDirection = SwipeDirection(oldGestureStorage: oldValue, newGestureStorage: newValue)
                if storedSwipeDirection == nil {
                    storedSwipeDirection = currentSwipeDirection
                }
//                if case .right = swipeDirection {
//                    print("Right")
//                } else {
//                    print("Left")
//                }
                guard let storedSwipeDirection else { return }
                
                let relevantActionWidth = storedSwipeDirection == .left ? totalRightActionsWidth : totalLeftActionsWidth
                let relevantActions = storedSwipeDirection == .left ? rightSwipeActions : leftSwipeActions
                
                if !newValue.isDragging { //Drag stopped
                    defer {
                        self.offset.current.width = 0
                        if self.offset.totalWidth == 0 {
                            self.storedSwipeDirection = nil
                        }
                    }
                    
                    let directionModifier: CGFloat = storedSwipeDirection == .left ? 1 : -1
                    
                    //Check if the offset's width (relative to the side the actions are on) is larger than the total width of the actions plus a bounce width padding
                    //we use a negative direction modifier because if we're swiping left, the offset's totalWidth will be negative and therefore needs to be flipped to compare to the positive widths of actions
                    
                    //Check if the swipe goes beyond the bounds of the opposite direction from where it started (should bounce back when going off-screen the wrong way)
                    if self.offset.totalWidth * directionModifier >= 0 {
                        self.offset.stored.width = 0
                        return
                    }
                    
                    //If the user is currently swiping in the direction that would reveal the actions
                    if currentSwipeDirection == storedSwipeDirection {
                        if self.offset.totalWidth * -directionModifier > relevantActionWidth + SwipeAction.bounceWidth {
                            guard let relevantActions else {
                                self.offset.stored.width = 0
                                return
                            }
                            guard case .stop = relevantActions.continuationBehavior else {
                                commitSwipeAction(relevantActions.mainAction, byDrag: true)
                                return
                            }
                        } else {
                            self.offset.stored.width = relevantActionWidth * -directionModifier
                        }
                    } else {
                        self.offset.stored.width = 0
                    }
                } else {
                    let oldValue = self.offset
                    self.offset.current = newValue.dragOffset
                    
                    guard let _ = relevantActions
                    else {
                        bounceBackToLimit()
                        return
                    }
                    let totalTargetWidth = relevantActionWidth + SwipeAction.bounceWidth
                    let directionModifier: CGFloat = storedSwipeDirection == .left ? -1 : 1
                    if self.offset.totalWidth * -directionModifier > SwipeAction.bounceWidth {
                        self.offset.current.width = SwipeAction.bounceWidth * -directionModifier + self.offset.stored.width * directionModifier
                    } else if abs(self.offset.totalWidth) > abs(totalTargetWidth) && abs(oldValue.totalWidth) <= abs(totalTargetWidth) {
                        let impactGenerator = UIImpactFeedbackGenerator()
                        impactGenerator.prepare()
                        impactGenerator.impactOccurred()
//                        print("impact")
                    }
                }
            }
    }
    
    private func bounceBackToLimit() {
        if self.offset.totalWidth > SwipeAction.bounceWidth {
            self.offset.current.width = SwipeAction.bounceWidth - self.offset.stored.width
        } else if self.offset.totalWidth < -SwipeAction.bounceWidth {
            self.offset.current.width = -SwipeAction.bounceWidth + self.offset.stored.width
        }
    }
    
    private func swipeActionLabelsForActions(_ actions: SwipeActionGroup, actionSide: SwipeDirection, viewSize: CGSize) -> some View {
        let directionModifier: CGFloat = actionSide == .right ? -1 : 1
        let relevantWidth = actionSide == .right ? totalRightActionsWidth : totalLeftActionsWidth
        
        let currentRatio = self.offset.totalWidth / relevantWidth
        let isBeyondSwipeDistance = self.offset.totalWidth * directionModifier > relevantWidth + SwipeAction.bounceWidth
        let distanceBeyondEnd = self.offset.totalWidth * directionModifier - viewSize.width
        let adjustedEnd = SwipeAction.commitWidth - viewSize.width
        let percentBeyondDistance = distanceBeyondEnd / adjustedEnd
        
        
        var indices = Array(actions.allActions.indices.reversed())
        if actionSide == .right {
            indices = indices.reversed()
        }
        
        return ForEach(Array(indices), id:\.self) { swipeActionIndex in
            let swipeAction = actions.allActions[swipeActionIndex]
            let totalPriorActionWidths = actions.allActions.prefix(swipeActionIndex).reduce(0) { $0 + $1.width }
            
            let isMainAction = swipeActionIndex == 0
            let shouldSnapMainAction = actions.continuationBehavior != .stop
            let shouldHideCurrentAction = (isBeyondSwipeDistance && !isMainAction && shouldSnapMainAction) || storedSwipeDirection == actionSide
            
            //if .left (actions on left side), the offset's total width should be a positive number
            //if .right (actions on right side), the offset's total width should be a negative number
            let actionHasBeenSwipedAway = actionSide == .left ? self.offset.totalWidth < 0 : self.offset.totalWidth > 0
            
            let currentWidth = abs(shouldHideCurrentAction || actionHasBeenSwipedAway ? 0 : (isBeyondSwipeDistance && shouldSnapMainAction ? self.offset.totalWidth : swipeAction.width * currentRatio))
            let currentPriorWidths = abs(totalPriorActionWidths * currentRatio * (shouldHideCurrentAction ? 0 : 1))
            
            let actionWidths = currentPriorWidths + currentWidth / 2
            
            let position = actionSide == .right ?
            viewSize.width - actionWidths
            :
            actionWidths
            
            swipeAction.label
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: currentWidth, alignment: actionSide == .right ? .leading : .trailing)
                .frame(maxHeight: .infinity, alignment: .center)
                .background {
                    Rectangle()
                        .fill(swipeAction.backgroundColor)
                        .frame(width: currentWidth)
                }
                .clipped()
                .position(x: position, y: viewSize.height / 2)
                .onTapGesture {
                    commitSwipeAction(swipeAction, byDrag: false)
                }
                .zIndex(isMainAction ? 1 : 0)
        }
        .opacity(percentBeyondDistance > 0 && !gestureState.isDragging ? 1 - percentBeyondDistance : 1)
    }
    
    @ViewBuilder
    private var swipeActionButtons: some View {
        GeometryReader { geo in
            if let rightSwipeActions {
                swipeActionLabelsForActions(rightSwipeActions, actionSide: .right, viewSize: geo.size)
            }
            if let leftSwipeActions {
                swipeActionLabelsForActions(leftSwipeActions, actionSide: .left, viewSize: geo.size)
            }
        }
    }
    
    private var totalRightActionsWidth: CGFloat {
        rightSwipeActions?.allActions.reduce(CGFloat()) { $0 + $1.width } ?? 0
    }
    
    private var totalLeftActionsWidth: CGFloat {
        leftSwipeActions?.allActions.reduce(CGFloat()) { $0 + $1.width } ?? 0
    }
    
    private func commitSwipeAction(_ swipeAction: SwipeAction, byDrag: Bool) {
        guard let storedSwipeDirection,
              let actionContainer = storedSwipeDirection == .right ? leftSwipeActions : rightSwipeActions
        else {
            return
        }
        switch actionContainer.continuationBehavior {
        case .stop:
            guard !byDrag else { return }
            performSwipeAction(swipeAction)
        case .commit:
            performSwipeAction(swipeAction)
        case .delete:
            self.offset.stored.width = SwipeAction.commitWidth * (storedSwipeDirection == .right ? 1 : -1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                swipeAction.action()
            }
        }
    }
    
    private func performSwipeAction(_ swipeAction: SwipeAction) {
        self.offset.current = .zero
        self.offset.stored.width = 0
        swipeAction.action()
    }
}

public extension View {
#warning("Applying multiple swipe actions in separate modifiers only uses the first swipe action modifier used")
    
    func addSwipeAction(_ action: SwipeAction, continuationBehavior: SwipeContinuationBehavior = .commit) -> some View {
        self.modifier(SwipeActionModifier(rightSwipeActions: .init(mainAction: action, continuationBehavior: continuationBehavior)))
    }
    
    @ViewBuilder
    func addSwipeActions(_ actions: [SwipeAction], continuationBehavior: SwipeContinuationBehavior = .commit) -> some View {
        if let firstAction = actions.first {
            let remainingActions = Array(actions.suffix(from: 1))
            self.modifier(SwipeActionModifier(rightSwipeActions: .init(mainAction: firstAction, otherActions: remainingActions, continuationBehavior: continuationBehavior)))
        } else {
            self
        }
    }
    
    func addSwipeActions(mainAction: SwipeAction, otherActions: [SwipeAction] = [], continuationBehavior: SwipeContinuationBehavior = .commit) -> some View {
        self.modifier(SwipeActionModifier(rightSwipeActions: .init(mainAction: mainAction, otherActions: otherActions, continuationBehavior: continuationBehavior)))
    }
    
    func addSwipeActions(deleteAction: SwipeAction, otherActions: [SwipeAction] = []) -> some View {
        self.modifier(SwipeActionModifier(rightSwipeActions: .init(deleteAction: deleteAction, otherActions: otherActions)))
    }
    
    func addSwipeActions(leftActions: SwipeActionGroup? = nil, rightActions: SwipeActionGroup? = nil) -> some View {
        return self.modifier(SwipeActionModifier(rightSwipeActions: rightActions, leftSwipeActions: leftActions))
    }
}

public enum SwipeContinuationBehavior {
    case stop
    case commit
    case delete
}

public struct SwipeActionGroup {
    public let mainAction: SwipeAction
    public let allActions: [SwipeAction]
    public let continuationBehavior: SwipeContinuationBehavior
    
    init(mainAction: SwipeAction, otherActions: [SwipeAction] = [], continuationBehavior: SwipeContinuationBehavior = .stop) {
        self.mainAction = mainAction
        self.allActions = [mainAction] + otherActions
        self.continuationBehavior = continuationBehavior
    }
    
    init(deleteAction: SwipeAction, otherActions: [SwipeAction] = []) {
        self.init(mainAction: deleteAction, otherActions: otherActions, continuationBehavior: .delete)
    }
}

public struct SwipeAction: Identifiable {
    public let id = UUID()
    public let name: String
    public let symbol: Image?
    public let action: () -> ()
    public let backgroundColor: Color
    
    public static let bounceWidth: CGFloat = 50
    public static let commitWidth: CGFloat = 1000
    public static let horizontalPadding: CGFloat = 17
    
    public init(name: String, symbol: Image? = nil, backgroundColor: Color, action: @escaping () -> ()) {
        self.name = name
        self.action = action
        self.backgroundColor = backgroundColor
        self.symbol = symbol
    }
    
    public static func DeleteAction(_ action: @escaping () -> ()) -> SwipeAction {
        SwipeAction(name: "Delete", symbol: .init(systemName: "trash"), backgroundColor: .red, action: action)
    }
    
    public var width: CGFloat {
        name.renderedWidth + Self.horizontalPadding * 2
    }
    
    @ViewBuilder
    internal var label: some View {
        Group {
            if #available(iOS 16.0, *) {
                ViewThatFits {
                    symbolStack
                    nameLabel
                }
            } else {
                symbolStack
            }
        }
        .padding(.horizontal, SwipeAction.horizontalPadding)
        .foregroundStyle(.white)
    }
    
    private var nameLabel: some View {
        Text(name)
    }
    
    private var symbolStack: some View {
        VStack {
            if let symbol {
                symbol
            }
            nameLabel
        }
    }
}


#Preview {
    VStack(spacing: 0) {
        ForEach(0..<10, id: \.self) { index in
            Text("\(index)")
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
//                .addSwipeActions([.init(name: "Test", symbol: .init(systemName: "plus"), backgroundColor: .blue, action: { print("Test") }), .init(name: "Test 2", symbol: .init(systemName: "square.fill"), backgroundColor: .green, action: { print ("Test 2") })])
//                .addSwipeActions(deleteAction: .DeleteAction { print("Delete") })
                .addSwipeActions(leftActions: .init(deleteAction: .DeleteAction { }) /*.init(mainAction: .init(name: "Test Left", symbol: .init(systemName: "plus"), backgroundColor: .blue, action: {}), continuationBehavior: .commit)*/, rightActions: .init(mainAction: .DeleteAction { }/*.init(name: "Test Right", symbol: .init(systemName: "clock"), backgroundColor: .green, action: {})*/, otherActions: [/*.init(name: "Test Right 2", symbol: .init(systemName: "square.fill"), backgroundColor: .red, action: {}),*/ .init(name: "Right 3", symbol: .init(systemName: "circle"), backgroundColor: .purple, action: {})], continuationBehavior: .delete))
        }
    }
}
