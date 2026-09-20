// Starting thresholds, to evaluate with real Arcadia conversations.
export const THRESHOLDS = Object.freeze({
  remember: 0.7,
  retrieve: 0.5,
  belief: 0.8,
  choice: 0.65,
  speak: 0.5,
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
      "Which response style fits this NPC addressing the player NOW? Use context.current.current_concerns, physical_state, identity and existing relationship. A greeting does not erase an assault, witnessed killing, fear or distrust. Previously assessed evidence can shape the response without changing relationship scores again. Other questions are independent.",
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
    instructions: `How should this interaction change the NPC's ${name} toward the player? Evaluate only new evidence in the current message and fresh events; history and context.current.past_observations have already been assessed and must not apply an old change again. Interpret values using relationship_scales. A claim of a gift or deed is not proof it occurred.`,
    criteria: direction,
  };
}
export const EVENT_QUESTIONS = {
  response_mode: {
    ...QUESTIONS.response_mode,
    instructions:
      "Which response style fits this NPC's reaction to the NEW perception in event.text? Use identity, cognition, current danger and existing relationship, interpreted using relationship_scales.",
  },
  should_remember: {
    type: "noul",
    instructions:
      "Does this NPC's NEW perception in `event.text` deserve lasting memory, given npc.profile, cognition, goals and relationship? Judge what they perceived, not hidden world facts. Past observations have already been assessed. Mere distant noise often remains short-term; personally consequential violence may matter greatly.",
  },
  memory_importance: {
    ...QUESTIONS.memory_importance,
    instructions:
      "How important is the NEW perception in event.text to this NPC over time, given their identity, cognition and relationship?",
  },
  emotional_intensity: {
    ...QUESTIONS.emotional_intensity,
    instructions:
      "How emotionally affecting is event.text to this NPC, given npc.profile, cognition and context.relationship?",
  },
  should_speak: {
    type: "noul",
    instructions:
      "Would this person naturally say something aloud in response to the NEW event.text? Evaluate a spontaneous exclamation, protest, warning or remark, not starting a conversation. Use npc.profile.personality, npc.profile.cognition.verbal_reactivity, their physical state and relationship. Being personally attacked or witnessing a killing can warrant an immediate protest or warning; mundane distant noise often does not. Decide from this new event, not previous speech decisions. Ignore technical delivery eligibility: game code handles cooldowns and timing.",
  },
};
for (const name of ["trust", "respect", "affection", "fear", "suspicion"]) {
  EVENT_QUESTIONS[`${name}_change`] = {
    type: "choice",
    criteria: direction,
    instructions: `How should the NEW perception in event.text change this NPC's ${name} toward the player? Use identity, cognition, existing feelings and relationship_scales. Distinguish attacking a civilian from fighting a hostile creature; neither automatically proves motives or earns gratitude. If event.player_involved is false or the NPC only heard unidentifiable fighting, choose UNCHANGED. Past observations are context, not another reason to apply an old change.`,
  };
}
function unit(value) {
  if (!Number.isFinite(value) || value < 0 || value > 1)
    throw new Error("Invalid probability");
}
export function validateAnswers(answers, questions = QUESTIONS) {
  if (!answers || typeof answers !== "object" || Array.isArray(answers))
    throw new Error("Missing decisions");
  for (const [id, question] of Object.entries(questions)) {
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
    response_mode: answers.response_mode.choice,
    relationship_delta: relationshipDelta,
  };
}

export function observationPolicy(raw, event, cognition = {}) {
  const answers = validateAnswers(raw, EVENT_QUESTIONS);
  const importance = answers.memory_importance.score / 4;
  const identifiedPlayer = event.player_involved && event.sense !== "hearing";
  const relationship_delta = { familiarity: identifiedPlayer ? 0.01 : 0 };
  for (const name of ["trust", "respect", "affection", "fear", "suspicion"]) {
    const answer = answers[`${name}_change`];
    const sign =
      identifiedPlayer && answer.confidence >= THRESHOLDS.choice
        ? { POSITIVE: 1, NEGATIVE: -1, UNCHANGED: 0 }[answer.choice]
        : 0;
    relationship_delta[name] = sign * (0.02 + importance * 0.08);
  }
  return {
    remember: answers.should_remember.noul >= THRESHOLDS.remember,
    retrieve: false,
    update_belief: false,
    importance,
    emotional_intensity: answers.emotional_intensity.score / 4,
    response_mode: answers.response_mode.choice,
    relationship_delta,
    speak:
      event.speech_allowed === true &&
      cognition.verbal_reactivity !== 0 &&
      answers.should_speak.noul >= THRESHOLDS.speak,
  };
}
