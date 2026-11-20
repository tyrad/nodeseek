import { readFileSync } from 'node:fs';
import { parseEnv } from 'node:util';

const { E2E_ENV_FILE, OPENAI_API_KEY } = process.env;
export const apiKey = E2E_ENV_FILE
  ? parseEnv(readFileSync(E2E_ENV_FILE, 'utf8')).OPENAI_API_KEY?.trim()
  : OPENAI_API_KEY?.trim();
if (!apiKey) throw new Error('请配置 OPENAI_API_KEY 或指向含该变量的 E2E_ENV_FILE');
