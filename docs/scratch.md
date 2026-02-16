Architecture-level insights

  6. 4,096-token hard limit — This is the API window for instructions + prompt + response combined. We're fine on budget now, but it means the
  instruction file can't grow much.

  7. "Not designed for world knowledge" — The specs say this directly. This is the root cause of hallucination. When context is thin, the model
  reaches for world knowledge it doesn't reliably have (Ghostbusters, accordion, "2009"). We're asking it to be creative, but at 3B it can only
  extract and rephrase what's given.

  8. @Generable structured output — The most powerful idea from the guides. A struct like:
  @Generable struct Commentary {
      @Guide(description: "The single most interesting fact from the context")
      var detail: String      // Generated first — forces extraction
      @Guide(description: "A warm 1-2 sentence observation about that detail")
      var commentary: String  // Generated second — grounded in the detail
  }
  Properties generate in declaration order, so detail would anchor commentary. This is the "place foundational properties first" pattern. It
  would structurally prevent hallucination by forcing the model to extract before it writes.

  9. Two-stage pipeline — Apple's Mail Smart Reply uses two separate prompts (extract questions → generate reply). We could do: extract key
  detail → write liner note. But this doubles latency.