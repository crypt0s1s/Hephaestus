import Foundation

public enum StoreState<Data, Failure: Error> {
    case loading(placeholder: Data? = nil)
    case loaded(Data)
    case error(Failure)
}

public extension StoreState {
    var data: Data? {
        switch self {
        case .loading(let placeholder):
            placeholder
        case .loaded(let data):
            data
        case .error:
            nil
        }
    }

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var failure: Failure? {
        if case .error(let failure) = self {
            return failure
        }
        return nil
    }

    func mapError<NextFailure: Error>(_ transform: (Failure) -> NextFailure) -> StoreState<Data, NextFailure> {
        switch self {
        case .loading(let placeholder):
            .loading(placeholder: placeholder)
        case .loaded(let data):
            .loaded(data)
        case .error(let failure):
            .error(transform(failure))
        }
    }
}

extension StoreState: Equatable where Data: Equatable, Failure: Equatable {}
extension StoreState: Sendable where Data: Sendable, Failure: Sendable {}
