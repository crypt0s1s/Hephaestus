public enum FoundryBackend {
    public static let id = HarnessBackendID(rawValue: "foundry")

    public static let descriptor = HarnessBackendDescriptor(
        id: id,
        displayName: "Foundry",
        availability: .available,
        capabilities: [
            .liveEvents,
            .conversation,
            .resume,
        ]
    )
}
