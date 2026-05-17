import Testing

@testable import Hephaestus

struct ExternalWorkflowEventLineInterpreterTests {
    private let interpreter = ExternalWorkflowEventLineInterpreter()

    @Test
    func validJSONLineProducesWorkflowEvent() {
        let event = interpreter.event(
            from: #"{"type":"stepFinished","stepID":"build","title":"Build","status":"succeeded","summary":"pass"}"#
        )

        #expect(event?.type == .stepFinished)
        #expect(event?.stepID == "build")
        #expect(event?.title == "Build")
        #expect(event?.status == .succeeded)
        #expect(event?.summary == "pass")
    }

    @Test
    func plainProcessOutputBecomesVisibleLogChunk() {
        let event = interpreter.event(from: "Building for debugging...")

        #expect(event?.type == .logChunk)
        #expect(event?.title == "External workflow output")
        #expect(event?.summary == "Building for debugging...")
    }

    @Test
    func malformedJSONEventBecomesVisibleLogChunk() {
        let event = interpreter.event(from: #"{"type":"unknownEvent","summary":"bad"}"#)

        #expect(event?.type == .logChunk)
        #expect(event?.title == "Malformed external workflow event")
        #expect(event?.summary?.contains("Ignored malformed external workflow event") == true)
        #expect(event?.summary?.contains(#""unknownEvent""#) == true)
    }

    @Test
    func nonzeroExitBecomesFailedWorkflowFinishedEvent() {
        let event = ExternalWorkflowEvent.processExitFailure(exitCode: 9)

        #expect(event.type == .workflowFinished)
        #expect(event.status == .failed)
        #expect(event.summary == "External workflow process exited with code 9.")
    }
}
