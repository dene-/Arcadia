import 'dotenv/config';
import express from 'express';
import OpenAI from 'openai';

const PORT = 3536;
const PROMPT_ID = 'pmpt_69f8e4bcd6b88190a94b0e4f5780560200264e5a73f0b980';
const PROMPT_VERSION = '5';

let openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

const app = express();

app.use(express.json({ limit: '1mb' }));

app.post('/chat', async (req, res) => {
  try {
    if (!process.env.OPENAI_API_KEY) {
      res.status(500).json({ error: 'OPENAI_API_KEY is not configured.' });
      return;
    }

    const npcData = parseNpcData(req.body?.npcData);
    const response = await openai.responses.create({
      prompt: {
        id: PROMPT_ID,
        version: PROMPT_VERSION,
        variables: {
          name: npcData.name,
          age: npcData.age,
          sex: npcData.sex,
          job: npcData.job,
          personality: npcData.personality,
          family: npcData.family,
          intelligence: npcData.intelligence,
          memories: npcData.memories || ' ',
        },
      },
      input: [
        {
          role: 'user',
          content: req.body?.playerMessage || 'hey',
        },
      ],
      text: {
        format: {
          type: 'json_schema',
          name: 'NPC',
          strict: false,
          schema: {
            type: 'object',
            description: 'NPC',
            properties: {
              response: {
                type: 'string',
                description: 'The NPC response to the player. Plain text',
              },
              replies: {
                type: 'array',
                description:
                  'Player replies to the NPC response. The last reply is always to quit the conversation. All of them plain text',
                uniqueItems: true,
                minItems: 2,
                maxItems: 3,
                items: {
                  type: 'string',
                },
              },
            },
            required: ['response', 'replies'],
          },
        },
        verbosity: 'medium',
      },
      reasoning: {
        summary: null,
      },
      store: false,
      include: [
        'reasoning.encrypted_content',
        'web_search_call.action.sources',
      ],
    });

    const npcResponse = parseNpcResponse(response.output_text);

    console.log('Generated NPC response:', npcResponse);

    res.json(npcResponse);
  } catch (error) {
    console.error('/chat failed', error);
    res.status(500).json({
      error: error instanceof Error ? error.message : 'Unknown server error.',
    });
  }
});

app.listen(PORT, () => {
  console.log(`NPC chat server listening on http://localhost:${PORT}`);
  if (!process.env.OPENAI_API_KEY) {
    console.warn(
      'OPENAI_API_KEY is not configured. /chat will return 500 until it is set.',
    );
  }
});

function parseNpcData(rawNpcData) {
  try {
    return JSON.parse(rawNpcData);
  } catch (error) {
    throw new Error(
      `Invalid npcData JSON string: ${error instanceof Error ? error.message : 'Unknown parse error.'}`,
    );
  }
}

function sanitizeString(string) {
  return string
    .trim()
    .replaceAll('—', '; ')
    .replaceAll('’', "'")
    .replaceAll('“', '"')
    .replaceAll('”', '"');
}

function parseNpcResponse(outputText) {
  if (typeof outputText !== 'string' || outputText.trim() === '') {
    throw new Error('OpenAI returned an empty response.');
  }

  try {
    const payload = JSON.parse(outputText);
    if (
      typeof payload?.response !== 'string' ||
      payload.response.trim() === ''
    ) {
      throw new Error(
        'OpenAI response did not contain a valid NPC response string.',
      );
    }
    payload.response = sanitizeString(payload.response);
    payload.replies = payload.replies.map(sanitizeString);

    return payload;
  } catch (error) {
    throw new Error(
      `OpenAI response was not valid JSON: ${error instanceof Error ? error.message : 'Unknown parse error.'}`,
    );
  }
}
