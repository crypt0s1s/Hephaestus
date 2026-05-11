import Anvil
import SwiftUI

@MainActor
struct RouteHost: View {
    @ObservedObject var router: Router<AnyRouteInput, AnyModalInput>
    let registry: DestinationRegistry
    let context: RouteBuildContext

    var body: some View {
        Group {
            if let route = router.path.last {
                buildRoute(route)
            } else {
                ProgressView("Opening Hephaestus...")
            }
        }
        .sheet(
            item: Binding(
                get: { router.modal },
                set: { if $0 == nil { router.dismissModal() } }
            )
        ) { modal in
            buildModal(modal)
        }
    }

    private func buildRoute(_ route: AnyRouteInput) -> AnyView {
        do {
            return try registry.buildRoute(route, context: context)
        } catch {
            return AnyView(RouteErrorView(error: error))
        }
    }

    private func buildModal(_ modal: AnyModalInput) -> AnyView {
        do {
            return try registry.buildModal(modal, context: context)
        } catch {
            return AnyView(RouteErrorView(error: error))
        }
    }
}
