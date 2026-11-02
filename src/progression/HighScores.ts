import { Storage } from '../core/Storage';

export interface HighScoreEntry {
  name: string;
  score: number;
  wave: number;
  kills: number;
  date: string;
}

const KEY = 'deadfall.highscores.v1';
export const MAX_ENTRIES = 10;
export const MAX_NAME_LENGTH = 14;

export function sanitizeName(name: string): string {
  const cleaned = name.replace(/[^\p{L}\p{N} _.\-!?]/gu, '').trim().slice(0, MAX_NAME_LENGTH);
  return cleaned.length > 0 ? cleaned : 'Survivor';
}

/** Sorts by score (desc), then wave (desc), then earlier date; keeps the top 10. */
export function insertScore(list: readonly HighScoreEntry[], entry: HighScoreEntry): { list: HighScoreEntry[]; rank: number } {
  const next = [...list, entry].sort((a, b) => b.score - a.score || b.wave - a.wave || a.date.localeCompare(b.date));
  const rank = next.indexOf(entry);
  const trimmed = next.slice(0, MAX_ENTRIES);
  return { list: trimmed, rank: rank < MAX_ENTRIES ? rank : -1 };
}

export function qualifies(list: readonly HighScoreEntry[], score: number): boolean {
  if (score <= 0) return false;
  if (list.length < MAX_ENTRIES) return true;
  return score > (list[list.length - 1] as HighScoreEntry).score;
}

function isEntry(v: unknown): v is HighScoreEntry {
  const e = v as HighScoreEntry;
  return !!e && typeof e.name === 'string' && typeof e.score === 'number' && typeof e.wave === 'number' && typeof e.kills === 'number' && typeof e.date === 'string';
}

/** Local top-10 leaderboard persisted in localStorage. */
export class HighScores {
  private entries: HighScoreEntry[];

  constructor() {
    const raw = Storage.get<unknown>(KEY, []);
    this.entries = Array.isArray(raw) ? raw.filter(isEntry).slice(0, MAX_ENTRIES) : [];
  }

  get list(): readonly HighScoreEntry[] {
    return this.entries;
  }

  qualifies(score: number): boolean {
    return qualifies(this.entries, score);
  }

  /** Adds an entry and returns its rank (0-based) or -1 if it didn't make the board. */
  add(name: string, score: number, wave: number, kills: number): number {
    const entry: HighScoreEntry = { name: sanitizeName(name), score: Math.round(score), wave, kills, date: new Date().toISOString() };
    const { list, rank } = insertScore(this.entries, entry);
    this.entries = list;
    Storage.set(KEY, this.entries);
    return rank;
  }

  get lastName(): string {
    return Storage.get<string>(`${KEY}.lastName`, '');
  }

  set lastName(name: string) {
    Storage.set(`${KEY}.lastName`, name);
  }
}
