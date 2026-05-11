import Foundation
import SwiftUI

@MainActor
public protocol Interactor: ObservableObject {
    associatedtype State
    associatedtype Action

    var state: State { get }

    func handle(_ action: Action)
    func onAppear()
    func onDisappear()
}

extension Interactor {
    public func onAppear() {}
    public func onDisappear() {}
}
