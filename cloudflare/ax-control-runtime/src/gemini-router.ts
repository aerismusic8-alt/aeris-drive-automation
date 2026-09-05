import type { GeminiResult } from './gemini-adapter';
import { generateGeminiText } from './gemini-adapter';

export type GeminiAccountStatus = 'AVAILABLE' | 'LIMITED' | 'FAILED' | 'COOLDOWN';

export type GeminiAccount = {
  id: string;
  apiKey: string;
};

type Clock = () => number;
type Generate = (account: GeminiAccount, prompt: string) => Promise<GeminiResult>;

type AccountState = {
  account: GeminiAccount;
  status: GeminiAccountStatus;
  cooldownUntil: number;
};

export type GeminiRouterResult =
  | { ok: true; text: string; accountId: string }
  | { ok: false; error: string };

export class GeminiRouter {
  private readonly states: AccountState[];
  private readonly generateWithAccount: Generate;
  private readonly cooldownMs: number;
  private readonly now: Clock;

  constructor(
    accounts: GeminiAccount[],
    generateWithAccount: Generate = (account, prompt) => generateGeminiText({ apiKey: account.apiKey, prompt }),
    options: { cooldownMs?: number; now?: Clock } = {},
  ) {
    this.states = accounts.map(account => ({ account, status: 'AVAILABLE', cooldownUntil: 0 }));
    this.generateWithAccount = generateWithAccount;
    this.cooldownMs = options.cooldownMs ?? 60_000;
    this.now = options.now ?? Date.now;
  }

  async generate(prompt: string): Promise<GeminiRouterResult> {
    const now = this.now();
    for (const state of this.states) {
      if (state.status === 'COOLDOWN' && state.cooldownUntil <= now) {
        state.status = 'AVAILABLE';
        state.cooldownUntil = 0;
      }
    }

    let attempted = false;
    for (const state of this.states) {
      if (state.status !== 'AVAILABLE') continue;
      attempted = true;
      const result = await this.generateWithAccount(state.account, prompt);
      if (result.ok) {
        state.status = 'AVAILABLE';
        return { ok: true, text: result.text, accountId: state.account.id };
      }

      if (result.error.includes('429') || result.error.includes('RATE') || result.error.includes('LIMIT')) {
        state.status = 'COOLDOWN';
        state.cooldownUntil = this.now() + this.cooldownMs;
      } else {
        state.status = 'FAILED';
      }
    }

    return {
      ok: false,
      error: attempted ? 'GEMINI_ALL_ACCOUNTS_UNAVAILABLE' : 'GEMINI_ALL_ACCOUNTS_UNAVAILABLE',
    };
  }

  getStatuses(): Array<{ id: string; status: GeminiAccountStatus }> {
    const now = this.now();
    return this.states.map(state => ({
      id: state.account.id,
      status: state.status === 'COOLDOWN' && state.cooldownUntil <= now ? 'AVAILABLE' : state.status,
    }));
  }
}
