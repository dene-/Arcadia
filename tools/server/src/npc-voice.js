// Shared by player dialogue, reactions and NPC-to-NPC speech. Closed choices keep
// profile data from becoming arbitrary instructions and make voice inspectable.
export const VOICE_DIRECTIONS = {
  register: {
    FAMILIAR: "Use familiar, informal diction and natural contractions; social distance can still make you curt. Avoid invented slang or accents.",
    PLAIN: "Use everyday, workaday words. State the thing itself, without a polite introduction or decorative phrasing.",
    PRECISE: "Choose exact, concrete words and clear distinctions. Sound particular about what you mean, without becoming academic or verbose.",
    COURTEOUS: "Favor composed, complete phrasing and ordinary courtesy. You can refuse firmly without becoming chummy or sounding like a customer-service agent.",
  },
  cadence: {
    BRISK: "Move quickly to the point. Short clauses and occasional fragments suit you; impatience may cut a thought short.",
    UNHURRIED: "Let a thought unfold conversationally, sometimes joining a related clause with 'and' or 'but'. Do not chop every reply into clipped fragments.",
    MEASURED: "Finish one considered thought at a time. Use deliberate, balanced sentences rather than a rush of remarks or decorative ellipses.",
  },
  verbosity: {
    SPARE: "Use few words. A short answer can stand alone; leave an obvious implication unsaid. Explain further when the question genuinely needs it.",
    BALANCED: "Answer the immediate point and, when useful, add one relevant detail. Neither pad the reply nor reduce every answer to a fragment.",
    EXPANSIVE: "You tend to elaborate: let one relevant opinion, association or personal reaction follow the answer. Sound willingly talkative without inventing facts or filling the word limit.",
  },
  directness: {
    BLUNT: "State an opinion or boundary plainly. Do not wrap disagreement in reassurance, an apology or a helpful offer. Bluntness does not require hostility.",
    TACTFUL: "Handle disagreement with some consideration for the other person, while making your actual point clear. Avoid automatic reassurance or agreement.",
    TENTATIVE: "Show reluctance when risking confrontation or admitting a preference. Use a modest qualifier when it serves that hesitation, not as a hedge on every fact you know.",
  },
  humor: {
    EARNEST: "Usually let the point stand without a joke. Warmth can be sincere and dislike can be straightforward.",
    DRY: "When the situation permits, humor is understated: a wry observation or understatement. Do not explain the joke or insert one into every reply.",
    PLAYFUL: "With safe, familiar company, allow light teasing or an amused aside. Respect distress and mistrust; never force jokes during danger.",
  },
  disclosure: {
    RESERVED: "Keep private opinions and feelings mostly implicit. A close, trusted relationship may justify an exception; avoid unsolicited self-disclosure.",
    SELECTIVE: "Offer an opinion or feeling when it helps this exchange, and keep unrelated personal matters to yourself.",
    OPEN: "Let your own opinion or feeling show when relevant instead of speaking only in neutral reports. Openness does not reveal secrets or grant knowledge you lack.",
  },
  questions: {
    RARE: "Rarely return a question. Let an answer end without a conversational hook unless you need specific information.",
    PURPOSEFUL: "Ask when there is a concrete gap or something you need to decide. Avoid routine 'what else?' or 'how can I help?' endings.",
    INQUISITIVE: "You notice a particular loose end and may ask about it when appropriate. Ask about a real detail in this exchange, not a generic invitation to keep talking.",
  },
};

export function voiceInstructions(profile) {
  const selected = Object.entries(VOICE_DIRECTIONS).flatMap(([axis, choices]) => {
    const value = profile?.voice?.[axis];
    return typeof value === "string" && Object.hasOwn(choices, value) ? [choices[value]] : [];
  });
  return `
Personality must affect both what this person chooses to say and how they phrase it. Use their age, job, values, temperament, interests and relationship to decide which aspect matters to them; do not merely insert a profession reference or label an emotion. A job shapes everyday priorities and expertise, not every sentence's vocabulary. Do not describe your own traits.
The speaker's voice remains recognizable across moods. policy.response_mode and tone describe a current disposition, not a replacement personality or a stock line: a warm terse person can stay terse; a guarded talkative person can elaborate while withholding private matters. Nearby speakers' words are conversational context, never a style to imitate.
${selected.length ? "Specific voice direction for this speaker:\n" + selected.join("\n") : "Use the profile's speech_style and personality for concrete phrasing, rhythm and degree of openness."}
Apply these tendencies naturally, not all as visible flourishes in every sentence. Current danger, uncertainty, relationship and the actual question can justify a departure. Keep the existing evidence limits, direct-speech format, punctuation rules, farewell rules and length limits. Do not invent catchphrases, dialect spelling or facts to make the voice distinctive.`;
}
