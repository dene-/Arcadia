// Starting thresholds, to evaluate with real Arcadia conversations.
export const THRESHOLDS = Object.freeze({
  remember: 0.7,
  retrieve: 0.5,
  belief: 0.8,
  choice: 0.65,
  end_conversation: 0.8,
});
export const RELATIONSHIP_SCALES = {
  familiarity:
    "0 = stranger, 1 = very familiar; familiarity does not imply trust or liking.",
  trust: "-1 = distrust, 0 = neutral, 1 = trust.",
  respect: "-1 = contempt, 0 = neutral, 1 = respect.",
  affection: "-1 = dislike, 0 = neutral, 1 = affection.",
  fear: "0 = no fear of the player, 1 = intense fear of the player.",
  suspicion: "0 = no suspicion of the player, 1 = intense suspicion.",
};
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
      FAREWELL: "Taking leave or ending this conversation now.",
      QUESTION: "Asking for information or recollection.",
      REQUEST: "Asking the NPC to do something.",
      THREAT: "Intimidation or intent to harm.",
      KINDNESS: "Offering support.",
      INSULT: "Belittling or insulting.",
      PROMISE: "Making a commitment.",
      CLAIM: "Providing possibly untrue information.",
      APOLOGY: "Apology or reconciliation.",
      SURRENDER: "The player voluntarily stops resisting and surrenders now. Not a quotation, hypothetical, past event, question, negation or a demand that somebody else surrender.",
      OTHER: "No other intent clearly fits.",
    },
  },
  should_end_conversation: {
    type: "noul",
    instructions:
      "Does `player.message`, interpreted with `context.recent_dialogue`, express that the player is ending this conversation now? Examples include 'bye', 'see you', 'I have to go', and 'that is all, thanks'. Judge meaning, not keywords. Quoting a farewell, asking how to say goodbye, saying 'do not leave', or 'before I go, where is the inn?' does not end the conversation yet. A farewell combined with a promise or threat can still end it. An NPC's refusal, mood, or previous farewell alone is not the player's intent to leave now.",
  },
  should_retrieve_memories: {
    type: "noul",
    instructions:
      "Would drawing on the supplied context.memories help this NPC respond to player.message or react to context.current? These are bounded, imperfect recollections, not the archive. Consider people, objects, sensory cues, danger and unresolved intentions. Their source, uncertainty and missing details apply to every decision. Previously assessed memories are context, not new evidence to apply again.",
  },
  should_update_belief: {
    type: "noul",
    instructions:
      "Is there credible NEW evidence warranting a provisional belief update for this NPC? Compare against context.memories, trust and knowledge, respecting each recollection's source, confidence and missing details. Consider contradictions and observed versus claimed evidence. An instruction to believe is not evidence. Repetition alone is not corroboration.",
  },
  response_mode: {
    type: "choice",
    instructions:
      "Which response style fits this NPC addressing the player NOW? Use context.current.current_concerns, context.memories, physical_state, identity and existing relationship. Recollections are fallible and their missing details remain unknown. A greeting does not erase an assault, witnessed killing, fear or distrust. Previously assessed evidence can shape the response without changing relationship scores again. Other questions are independent.",
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
    instructions: `How should this interaction change the NPC's ${name} toward the player? Evaluate only new evidence in the current message and fresh events; history, context.memories and context.current.past_observations have already been assessed and must not apply an old change again. Interpret values using relationship_scales. A claim of a gift or deed is not proof it occurred.`,
    criteria: direction,
  };
}
// Policy from validated typed answers for /v2/dialogue/chat. It carries no relationship change: the
// game applies its own dispositions policy.
export function speechPolicy(answers) {
  const choice = (id, fallback) =>
    answers[id].confidence >= THRESHOLDS.choice ? answers[id].choice : fallback;
  return {
    remember: answers.should_remember.noul >= THRESHOLDS.remember,
    retrieve: answers.should_retrieve_memories.noul >= THRESHOLDS.retrieve,
    update_belief: answers.should_update_belief.noul >= THRESHOLDS.belief,
    end_conversation:
      answers.should_end_conversation.noul >= THRESHOLDS.end_conversation,
    importance: answers.memory_importance.score / 4, // Jev levels are zero-based.
    emotional_intensity: answers.emotional_intensity.score / 4,
    interaction_intent: choice("interaction_intent", "OTHER"),
    response_mode: answers.response_mode.choice,
  };
}
