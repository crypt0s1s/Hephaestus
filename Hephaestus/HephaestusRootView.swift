import AnvilTheme
import SwiftUI

struct HephaestusRootView: View {
    private let result: Result<HephaestusAppShell, Error>

    init() {
        result = Result {
            try HephaestusAppShell()
        }
    }

    var body: some View {
        Group {
            switch result {
            case .success(let shell):
                shell
            case .failure(let error):
                StartupErrorView(error: error)
            }
        }
        .anvilTheme(.hephaestus)
    }
}
