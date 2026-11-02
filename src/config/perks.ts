export type PerkId =
  | 'vampire' | 'piercing' | 'explosiveKills' | 'quickHands' | 'adrenaline' | 'thickSkin'
  | 'scavenger' | 'incendiary' | 'greed' | 'secondWind' | 'marathon' | 'bigGame';

export interface PerkDef {
  id: PerkId;
  name: string;
  description: string;
  maxStacks: number;
  /** Short glyph shown in the HUD perk tray. */
  glyph: string;
  color: string;
}

export const PERKS: Record<PerkId, PerkDef> = {
  vampire: { id: 'vampire', name: 'Vampire Bullets', description: 'Heal for 3% of all damage you deal.', maxStacks: 2, glyph: 'V', color: '#d6334a' },
  piercing: { id: 'piercing', name: 'Piercing Rounds', description: 'Bullets pass through +1 additional zombie.', maxStacks: 2, glyph: 'P', color: '#6bb7ff' },
  explosiveKills: { id: 'explosiveKills', name: 'Explosive Kills', description: '20% chance killed zombies explode, damaging others.', maxStacks: 2, glyph: 'X', color: '#ff8a2a' },
  quickHands: { id: 'quickHands', name: 'Quick Hands', description: 'Reload 30% faster.', maxStacks: 2, glyph: 'Q', color: '#ffd23a' },
  adrenaline: { id: 'adrenaline', name: 'Adrenaline', description: 'Kills restore stamina and briefly boost speed.', maxStacks: 1, glyph: 'A', color: '#5aff8a' },
  thickSkin: { id: 'thickSkin', name: 'Thick Skin', description: 'Take 12% less damage.', maxStacks: 3, glyph: 'T', color: '#b08a5a' },
  scavenger: { id: 'scavenger', name: 'Scavenger', description: '+50% drop chance and wider pickup magnet.', maxStacks: 2, glyph: 'S', color: '#a6e05a' },
  incendiary: { id: 'incendiary', name: 'Incendiary Rounds', description: 'Bullets have a 25% chance to set zombies on fire.', maxStacks: 2, glyph: 'I', color: '#ff5a2a' },
  greed: { id: 'greed', name: 'Greed', description: 'Earn 25% more coins.', maxStacks: 2, glyph: '$', color: '#ffcc33' },
  secondWind: { id: 'secondWind', name: 'Second Wind', description: 'Once per wave, survive a lethal hit with 1 HP.', maxStacks: 1, glyph: 'W', color: '#e0e0ff' },
  marathon: { id: 'marathon', name: 'Marathon', description: '+40% stamina, faster regen and cheaper rolls.', maxStacks: 1, glyph: 'M', color: '#5ad6ff' },
  bigGame: { id: 'bigGame', name: 'Big Game Hunter', description: '+35% damage against Brutes and Bosses.', maxStacks: 2, glyph: 'B', color: '#c45aff' },
};

export const PERK_IDS = Object.keys(PERKS) as PerkId[];
