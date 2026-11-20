import { apiKey } from './api-key.mjs';

const env = process.env;
env.MIDSCENE_MODEL_API_KEY = apiKey;
env.MIDSCENE_MODEL_BASE_URL = 'https://api.openai.com/v1';
env.MIDSCENE_MODEL_NAME = 'gpt-6-sol';
env.MIDSCENE_MODEL_FAMILY = 'gpt-6';
export const { agentFromWebDriverAgent } = await import('@midscene/ios');
