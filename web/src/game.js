// The browser game — the shared, hackable build. Drives the same core logic
// (poolbattle/gauntlet/boons/lexicon) that the Godot version uses, rendered to the
// DOM with emoji art. No server: it fetches the shared JSON data and saves the high
// score to localStorage.
import { setRules, num } from './rules.js';
import { Lexicon, coveredLetters, upperLetters, letterWeight } from './lexicon.js';
import { Gauntlet } from './gauntlet.js';
import { PoolBattle } from './poolbattle.js';
import * as Boons from './boons.js';
import { Rng } from './rng.js';
import { creatureIcon, weaponIcon, boonIcon, TOMBSTONE } from './icons.js';
import * as WB from './wordbank.js';

const DATA = '../game/data/'; // served from the repo root (e.g. GitHub Pages / http.server)
const $ = (id) => document.getElementById(id);
const RULES_TEXT =
  'Each enemy is a POOL OF LETTERS with an HP bar equal to their total rarity weight.\n\n' +
  'Type ANY real word using its letters — it deals damage equal to the rarity weight of the ' +
  'letters it covers. Rare letters (j, x, q, z) hit hardest, but common ones chip away too, so ' +
  'you never get stuck.\n\n' +
  "Drain the HP to 0 to clear the chapter and pick a reward. You can't type the enemy's own " +
  'weapon words, and no word twice per run. The enemy hits you every turn — so kill fast.\n\n' +
  'You lose at 0 HP. Score = damage dealt + how deep you go.';

let lexicon, gauntlet;
const S = {}; // run state

// --- boot --------------------------------------------------------------------

async function boot() {
  const [rules, bank, dict] = await Promise.all([
    fetch(DATA + 'rules.json').then((r) => r.json()),
    fetch(DATA + 'word_bank.json').then((r) => r.json()),
    fetch(DATA + 'dictionary.json').then((r) => r.json()),
  ]);
  setRules(rules);
  lexicon = new Lexicon(dict.words);
  gauntlet = new Gauntlet();
  gauntlet.setup(bank);
  wireUI();
  showBest();
  $('rules-body').textContent = RULES_TEXT;
  $('title').classList.add('show');
}

// --- run / battle flow -------------------------------------------------------

function startRun() {
  S.maxHp = num('gauntlet', 'start_hp', 36);
  S.hp = S.maxHp;
  S.chapter = 1;
  S.score = 0;
  S.over = false;
  S.choosing = false;
  S.hints = 0;
  S.letterMult = {};
  S.used = [];
  S.log = [];
  S.rng = new Rng(Date.now() >>> 0);
  gauntlet.rng = S.rng;
  $('title').classList.remove('show');
  $('gameover').classList.remove('show');
  startEnemy();
  logMsg('A foe blocks your path. Spell from its letters to drain its HP!');
}

function startEnemy() {
  S.choosing = false;
  const enemy = gauntlet.generate(S.chapter);
  S.battle = new PoolBattle();
  S.battle.lexicon = lexicon;
  S.battle.used = S.used; // no-reuse spans the whole run
  S.battle.letter_mult = S.letterMult;
  S.battle.begin(enemy, S.hp, S.maxHp);
  $('entry').value = '';
  render();
  $('entry').focus();
}

function onStrike() {
  if (S.over || S.choosing) return;
  const res = S.battle.tryMove($('entry').value);
  if (!res.ok) {
    $('action-line').textContent = 'Can’t: ' + (res.reason || 'invalid');
    return;
  }
  $('entry').value = '';
  const gain = res.dealt * num('gauntlet', 'score_per_damage', 3); // dealt already boosted
  S.score += gain;
  const uses = res.covered.length ? `  [uses ${upperLetters(res.covered).join(', ')}]` : '';
  logMsg(`You: ${res.word} hits for ${res.dealt}${uses}  +${gain}`);

  if (res.won) {
    const bonus = S.chapter * num('gauntlet', 'chapter_bonus', 25);
    S.score += bonus;
    S.hp = S.battle.player_hp;
    logMsg(`Chapter ${S.chapter} cleared!  (+${bonus} score)  Choose a reward.`);
    $('portrait').textContent = TOMBSTONE; // R.I.P.
    offerBoons();
    return;
  }
  if (res.damage > 0) {
    logMsg(`   enemy strikes for ${res.damage}`);
    lungePortrait();
  }
  S.hp = S.battle.player_hp;
  if (res.lost) return lose();
  render();
}

function onHint() {
  if (S.over || S.choosing || S.hints <= 0) return;
  const w = lexicon.bestWord(S.battle.letters().join(''), S.used.concat(S.battle.weapons()));
  if (!w) {
    $('action-line').textContent = 'Hint: no fresh word found.';
    return;
  }
  S.hints -= 1;
  $('hint').textContent = `Hint (${S.hints})`;
  $('hint').classList.toggle('hidden', S.hints <= 0);
  $('action-line').textContent = `Hint: try '${w}'   (${S.hints} left)`;
}

function lose() {
  S.over = true;
  const record = recordBest(S.chapter, S.score);
  logMsg(`DEFEATED in chapter ${S.chapter}. Final score: ${S.score}.`);
  $('gameover-stats').innerHTML =
    `Reached chapter ${S.chapter} &middot; Score ${S.score}` + (record ? '<br>★ New best! ★' : '');
  $('gameover').classList.add('show');
}

// --- boons -------------------------------------------------------------------

function offerBoons() {
  S.choosing = true;
  const row = $('boons');
  row.innerHTML = '';
  for (const boon of Boons.offer(S.rng)) {
    const btn = document.createElement('button');
    btn.className = 'boon';
    btn.innerHTML = `<div class="emoji">${boonIcon(boon.id)}</div><div class="label">${boon.label}</div><div class="desc">${boon.desc}</div>`;
    btn.onclick = () => takeBoon(boon);
    row.appendChild(btn);
  }
  render();
}

function takeBoon(boon) {
  const s = { hp: S.hp, max_hp: S.maxHp, hints: S.hints, letter_mult: S.letterMult };
  Boons.apply(boon, s);
  S.hp = s.hp;
  S.maxHp = s.max_hp;
  S.hints = s.hints;
  S.letterMult = s.letter_mult;
  logMsg(`Boon: ${boon.label}`);
  S.chapter += 1;
  startEnemy();
}

// --- rendering ---------------------------------------------------------------

function render() {
  const b = S.battle;
  $('chapter').textContent = `CHAPTER ${S.chapter}`;
  $('score').textContent = `SCORE ${S.score}`;
  $('enemy-head').textContent =
    'ENEMY  ·  spell words from its letters (reuse freely; not its own weapon words) to drain its HP';

  renderEnemy();
  const fighting = !S.over && !S.choosing;
  $('atk-badge').style.visibility = fighting ? 'visible' : 'hidden';
  $('atk-badge').textContent = `⚔ ${b.incomingDamage()}`;
  setHp('enemy', b.enemyHp(), b.enemyMaxHp());
  $('enemy-hplabel').textContent = `HP ${b.enemyHp()} / ${b.enemyMaxHp()}`;

  setHp('you', S.hp, S.maxHp);
  $('you-hplabel').textContent = `HP ${S.hp}/${S.maxHp}`;
  $('spent').textContent = `words spent: ${S.used.length}`;

  $('boons').classList.toggle('hidden', !S.choosing);
  $('controls').classList.toggle('hidden', !fighting);
  $('hint').classList.toggle('hidden', S.hints <= 0);
  $('hint').textContent = `Hint (${S.hints})`;
  updateActionLine();
}

function renderEnemy() {
  const tokens = S.battle.enemy.tokens || [];
  const owner = tokens.find((t) => t.kind === WB.KIND_CREATURE && t.is_owner);
  if (!S.choosing && !S.over) $('portrait').textContent = creatureIcon(owner ? owner.text : '');

  $('sentence').innerHTML = tokens
    .map((t) => {
      const cls = t.kind === WB.KIND_ITEM ? 'weapon' : 'plain';
      return `<span class="${cls}">${escapeHtml(t.text || '')}</span>`;
    })
    .join(' ');

  const row = $('letters');
  row.innerHTML = '';
  S.tileEls = {};
  for (const ch of S.battle.letters()) {
    const base = letterWeight(ch);
    const mult = S.letterMult[ch] || 1;
    const value = base * mult;
    const boosted = mult > 1;
    const hot = boosted || base >= 5;
    const el = document.createElement('div');
    el.className = 'tile' + (hot ? ' hot' : '');
    el.innerHTML =
      `<div class="box"><div class="glyph">${ch.toUpperCase()}</div>` +
      `<div class="pts">${boosted ? value + '×' : value}</div></div><div class="bar"></div>`;
    if (boosted) el.title = `${ch.toUpperCase()} is worth ${mult}× (Double boon)`;
    row.appendChild(el);
    S.tileEls[ch] = el;
  }
}

function updateActionLine() {
  if (S.over || S.choosing) {
    setDmg(0);
    return;
  }
  const typed = $('entry').value.trim();
  if (typed === '') {
    $('action-line').textContent = '';
    setDmg(0);
    highlightTiles([]);
    return;
  }
  const r = S.battle.check(typed);
  if (r.ok) {
    const covered = coveredLetters(typed, S.battle.letters().join(''));
    setDmg(r.dealt);
    $('action-line').textContent = `'${typed.toLowerCase()}' uses ${upperLetters(covered).join(', ')}`;
    highlightTiles(covered);
  } else {
    setDmg(0);
    $('action-line').textContent = r.reason || '';
    highlightTiles([]);
  }
}

function highlightTiles(covered) {
  const used = new Set(covered);
  for (const ch in S.tileEls) S.tileEls[ch].classList.toggle('used', used.has(ch));
}

function setDmg(n) {
  $('dmg').textContent = String(n);
}
function setHp(who, hp, max) {
  $(`${who}-hpfill`).style.width = `${max > 0 ? Math.max(0, (hp / max) * 100) : 0}%`;
}
function lungePortrait() {
  const p = $('portrait');
  p.style.transform = 'translateX(14px) scale(1.25)';
  setTimeout(() => (p.style.transform = ''), 130);
}
function logMsg(text) {
  S.log.push(text);
  if (S.log.length > 6) S.log.shift();
  $('log').textContent = S.log.join('\n');
}
function escapeHtml(s) {
  return s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
}

// --- high score (localStorage) -----------------------------------------------

function getBest() {
  try {
    return JSON.parse(localStorage.getItem('wordplay.best') || '{"depth":0,"score":0}');
  } catch {
    return { depth: 0, score: 0 };
  }
}
function recordBest(depth, score) {
  const best = getBest();
  if (score <= best.score) return false;
  localStorage.setItem('wordplay.best', JSON.stringify({ depth, score }));
  return true;
}
function showBest() {
  const b = getBest();
  $('best').textContent = b.score > 0 ? `Best:  chapter ${b.depth}  ·  score ${b.score}` : 'No runs yet — go set a record.';
}

// --- wiring ------------------------------------------------------------------

function wireUI() {
  $('strike').onclick = onStrike;
  $('hint').onclick = onHint;
  $('newrun').onclick = startRun;
  $('entry').addEventListener('input', updateActionLine);
  $('entry').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') onStrike();
  });
  $('play').onclick = startRun;
  $('howto').onclick = () => $('rules').classList.add('show');
  $('rules-close').onclick = () => $('rules').classList.remove('show');
  $('go-newrun').onclick = startRun;
  $('go-menu').onclick = () => {
    $('gameover').classList.remove('show');
    showBest();
    $('title').classList.add('show');
  };
}

boot();
