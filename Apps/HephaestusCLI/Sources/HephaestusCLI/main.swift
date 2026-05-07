import Foundation
import HephaestusComposition
import HephaestusRuntime

@main
struct HephaestusCLI {
  static func main() async {
    let messages = Array(CommandLine.arguments.dropFirst())
    let inputMessages = messages.isEmpty ? readStdinMessages() : messages

    guard !inputMessages.isEmpty else {
      print("Usage: HephaestusCLI \"message\" [\"second message\" ...]")
      return
    }

    do {
      let harness = try RuntimeComposition.make(mockDelayNanoseconds: 120_000_000)
      let runID = await harness.createRun.createRun()
      try await runMessages(inputMessages, harness: harness, runID: runID)
    } catch {
      fputs("HephaestusCLI failed: \(error)\n", stderr)
      Foundation.exit(1)
    }
  }

  private static func runMessages(
    _ messages: [String],
    harness: RuntimeHarness,
    runID: UUID
  ) async throws {
    for message in messages {
      print("> \(message)")
      let stream = try await harness.streamUserMessage.streamUserMessage(
        runID: runID,
        text: message
      )

      var didStartAssistant = false
      for try await event in stream {
        didStartAssistant = handle(event, didStartAssistant: didStartAssistant)
      }
    }
  }

  private static func handle(_ event: RuntimeEvent, didStartAssistant: Bool) -> Bool {
    switch event {
    case .userMessageAccepted, .runCreated:
      return didStartAssistant
    case .contextPrepared(_, let count):
      print("[context: \(count) messages]")
    case .providerRequestPrepared(_, _, let model, let messageCount):
      print("[provider: \(model), \(messageCount) messages]")
    case .assistantTextDelta(_, let text):
      if !didStartAssistant {
        print("assistant: ", terminator: "")
      }
      print(text, terminator: "")
      fflush(stdout)
      return true
    case .assistantMessageCompleted:
      print("")
    case .turnCancelled:
      fputs("turn cancelled\n", stderr)
    case .turnFailed(_, let reason):
      fputs("turn failed: \(reason)\n", stderr)
    }
    return didStartAssistant
  }

  private static func readStdinMessages() -> [String] {
    var messages: [String] = []
    while let line = readLine() {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        messages.append(trimmed)
      }
    }
    return messages
  }
}
