# Next Step: Build The Agent Kernel POC

## Objective

The immediate next step is to build the smallest useful `agent kernel` inside the app.

This milestone is not about multi-agent workflows yet. It is about proving the basic runtime contract that everything else will depend on.

## Scope

Build a kernel that can:

1. Start a run.
2. Accept a user message.
3. Assemble context for the turn.
4. Send the request to an OpenAI-compatible endpoint.
5. Receive and expose the response.
6. Accept a second user message in the same run.
7. Produce a second response with continuity from prior state.

## Core Components

### Agent

- Fixed profile for now.
- Holds instructions, model selection hint, and context policy.

### Run

- Owns the ordered turn history.
- Represents the active session for one agent conversation.

### Provider Adapter

- Sends requests to an OpenAI-compatible endpoint.
- Keeps the wire format behind an internal interface.

### Context Manager

- Builds the model input from the current user message plus prior state.
- Starts simple, but should already be separate from the provider and runtime.

### Event Stream

- Emits request started, response started, response updated, response finished, and error events.
- Gives the UI and future persistence layer a stable observation point.

## Constraints

- Keep the design local-first.
- Avoid assuming a custom backend exists.
- Avoid coupling the kernel to any future workflow editor.
- Avoid burying context logic inside view code or provider code.

## Done Criteria

This step is complete when:

- A single agent can complete two sequential turns in one run.
- The second turn includes continuity from the first turn.
- Runtime events are visible in a structured way.
- The kernel boundary is clear enough that a second agent could be added later without redesigning the first one.

## After This Step

Once the kernel POC works, the next priorities should be:

1. Harden the kernel with streaming, errors, and persistence.
2. Turn it into a competent single-agent harness with stronger context management, persisted chats, skills, and tools.
3. Only then start defining multi-agent workflow primitives on top of the harness.
