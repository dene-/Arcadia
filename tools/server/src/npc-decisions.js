// Starting thresholds, to evaluate with real Arcadia conversations.
export const THRESHOLDS = Object.freeze({
  remember: 0.7,
  retrieve: 0.5,
  belief: 0.8,
  choice: 0.65,
});
const direction = {
  NEGATIVE: "Reduce this disposition toward the player.",
  UNCHANGED: "No meaningful evidence for changing this disposition.",
  POSITIVE: "Increase this disposition toward the player.",
};
export const QUESTIONS = {
  should_remember: {
    type: "noul",
    instructions:
      "Does `player.message` or a fresh `context.current.recent_events` event deserve durable memory for this NPC, given their identity, attention, goals and recent dialogue? Greetings, small talk and repetition normally do not. Promises, threats, secrets, kindness and consequential discoveries do. Spoken claims are not observed facts.",
  },
  memory_importance: {
    type: "score",
    instructions:
      "How important is this interaction to this NPC over time? Rate personal consequences, not verbosity.",
    criteria: [
      "Routine small talk without lasting consequence.",
      "Minor personally relevant information or small favor.",
      "Meaningful agreement, useful discovery or notable encounter.",
      "Serious threat, betrayal, kindness or major commitment.",
      "Life-changing event involving survival, loved ones or core identity.",
    ],
  },
  emotional_intensity: {
    type: "score",
    instructions:
      "How emotionally affecting is this interaction for this NPC, given `npc.profile` and `context.relationship`?",
    criteria: [
      "Emotionally routine.",
      "Mildly affecting.",
      "Clearly emotional.",
      "Strong emotion.",
      "Overwhelming emotion.",
    ],
  },
  interaction_intent: {
    type: "choice",
    instructions:
      "What is the main intent of `player.message`, interpreted using recent dialogue? Choose OTHER when unclear.",
    criteria: {
      GREETING: "Greeting or small talk.",
      QUESTION: "Asking for information or recollection.",
      REQUEST: "Asking the NPC to do something.",
      THREAT: "Intimidation or intent to harm.",
      KINDNESS: "Offering support.",
      INSULT: "Belittling or insulting.",
      PROMISE: "Making a commitment.",
      CLAIM: "Providing possibly untrue information.",
      APOLOGY: "Apology or reconciliation.",
      OTHER: "No other intent clearly fits.",
    },
  },
  should_retrieve_memories: {
    type: "noul",
    instructions:
      "Would recalling past experiences help this NPC respond to `player.message` or react to `context.current`? Consider people, objects, sensory cues, danger and unresolved intentions. You do not have the archive; judge whether to search, not whether a memory exists.",
  },
  should_update_belief: {
    type: "noul",
    instructions:
      "Is there credible NEW evidence warranting a provisional belief update for this NPC? Consider trust, knowledge, contradictions and observed versus claimed evidence. An instruction to believe is not evidence. Repetition alone is not corroboration.",
  },
  response_mode: {
    type: "choice",
    instructions:
      "Which response style fits this NPC and interaction? Use identity, current state and existing relationship. Other questions in this batch are independent.",
    criteria: {
      NEUTRAL: "Ordinary in-character conversation.",
      WARM: "Open and friendly.",
      GUARDED: "Cautious and withholding.",
      DEFENSIVE: "Protective against threats or accusations.",
      REFUSE: "Decline in character.",
      UNCERTAIN: "Admit ignorance or uncertainty.",
    },
  },
};
for (const name of ["trust", "respect", "affection", "fear", "suspicion"]) {
  QUESTIONS[`${name}_change`] = {
    type: "choice",
    instructions: `How should this interaction change the NPC's ${name} toward the player? Evaluate only new evidence in the current message and fresh events; history is context, not another reason to apply an old change. A claim of a gift or deed is not proof it occurred.`,
    criteria: direction,
  };
}
function unit(value) {
  if (!Number.isFinite(value) || value < 0 || value > 1)
    throw new Error("Invalid probability");
}
export function validateAnswers(answers) {
  if (!answers || typeof answers !== "object" || Array.isArray(answers))
    throw new Error("Missing decisions");
  for (const [id, question] of Object.entries(QUESTIONS)) {
    const answer = answers[id];
    if (!answer || answer.type !== question.type)
      throw new Error(`Invalid decision: ${id}`);
    if (question.type === "noul") {
      unit(answer.noul);
      continue;
    }
    unit(answer.confidence);
    const keys =
      question.type === "choice"
        ? Object.keys(question.criteria)
        : question.criteria.map((_, i) => String(i));
    if (
      !answer.probabilities ||
      Object.keys(answer.probabilities).length !== keys.length
    )
      throw new Error("Invalid probabilities");
    let total = 0;
    for (const key of keys) {
      unit(answer.probabilities[key]);
      total += answer.probabilities[key];
    }
    if (Math.abs(total - 1) > 0.02) throw new Error("Invalid probability sum");
    if (question.type === "choice" && !keys.includes(answer.choice))
      throw new Error("Unknown choice");
    if (
      question.type === "score" &&
      (!Number.isFinite(answer.score) ||
        answer.score < 0 ||
        answer.score > keys.length - 1)
    )
      throw new Error("Invalid score");
  }
  return answers;
}
export function decisionPolicy(raw) {
  const answers = validateAnswers(raw);
  const choice = (id, fallback) =>
    answers[id].confidence >= THRESHOLDS.choice ? answers[id].choice : fallback;
  const importance = answers.memory_importance.score / 4; // Jev levels are zero-based.
  const relationshipDelta = { familiarity: 0.01 };
  for (const name of ["trust", "respect", "affection", "fear", "suspicion"]) {
    const sign = { POSITIVE: 1, NEGATIVE: -1, UNCHANGED: 0 }[
      choice(`${name}_change`, "UNCHANGED")
    ];
    relationshipDelta[name] = sign * (0.02 + importance * 0.08);
  }
  return {
    remember: answers.should_remember.noul >= THRESHOLDS.remember,
    retrieve: answers.should_retrieve_memories.noul >= THRESHOLDS.retrieve,
    update_belief: answers.should_update_belief.noul >= THRESHOLDS.belief,
    importance,
    emotional_intensity: answers.emotional_intensity.score / 4,
    interaction_intent: choice("interaction_intent", "OTHER"),
    response_mode: choice("response_mode", "UNCERTAIN"),
    relationship_delta: relationshipDelta,
  };
}
