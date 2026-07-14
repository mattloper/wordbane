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
import { setIcons, setGeneratedIcons, bonkIcon, creatureIcon, boonIcon, tombstone } from './icons.js';
import * as WB from './wordbank.js';

const DATA = '../shared_data/'; // served from the repo root (e.g. GitHub Pages / http.server)
// Art skins — loaded from shared_data/styles.json at boot (the single source of
// truth). [key, label] pairs; the chosen key is persisted in localStorage and names
// the folder under shared_data/art/<kind>/.
let STYLES = [];
let artStyle = localStorage.getItem('wordplay.style') || 'storybook';
const artUrl = (kind, subject) => `${DATA}art/${kind}/${artStyle}/${subject}.png`;

// The title logo for the current skin (art/logo/<style>.png), falling back to text.
function updateTitleLogo() {
  const img = $('title-logo');
  img.onload = () => { img.classList.remove('hidden'); $('title-text').classList.add('hidden'); };
  img.onerror = () => { img.classList.add('hidden'); $('title-text').classList.remove('hidden'); };
  img.src = `${DATA}art/logo/${artStyle}.png`;
}
const $ = (id) => document.getElementById(id);

// Show the big enemy portrait: the baked AI image if it exists, else the emoji.
function showPortrait(kind, subject, emoji) {
  const img = $('portrait-img');
  img.onload = () => {
    img.classList.remove('hidden');
    $('portrait').classList.add('hidden');
  };
  img.onerror = () => {
    img.classList.add('hidden');
    $('portrait').classList.remove('hidden');
    $('portrait').textContent = emoji;
  };
  img.src = artUrl(kind, subject);
}
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

// Phones: mirror the *visible* viewport (which shrinks when the keyboard opens, while
// the page itself does not on iOS) into CSS vars so the play screen can size to it and
// keep the input above the keyboard. A no-op on browsers without visualViewport.
function trackViewport() {
  const vv = window.visualViewport;
  if (!vv) return;
  const apply = () => {
    const s = document.documentElement.style;
    s.setProperty('--vvh', `${vv.height}px`);
    s.setProperty('--vvt', `${vv.offsetTop}px`);
  };
  vv.addEventListener('resize', apply);
  vv.addEventListener('scroll', apply);
  apply();
}

// Touch devices get an in-page keyboard instead of the native one: the OS keyboard can't
// be resized and its open/close churns the layout, so on a coarse pointer we suppress it
// (readonly input) and drive the same #entry field from our own keys.
const KB_ROWS = [
  ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
  ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
  ['z', 'x', 'c', 'v', 'b', 'n', 'm', 'back'],
];
function onKey(e) {
  const btn = e.target.closest('button.key');
  if (!btn) return;
  e.preventDefault(); // keep focus/scroll/zoom out of it, and respond on press
  const k = btn.dataset.k;
  const inp = $('entry');
  inp.value = k === 'back' ? inp.value.slice(0, -1) : inp.value + k;
  inp.dispatchEvent(new Event('input')); // refresh the damage preview
}
function setupTouchInput() {
  if (!window.matchMedia || !matchMedia('(pointer: coarse)').matches) return;
  document.body.classList.add('touch');
  const inp = $('entry');
  inp.readOnly = true; // guarantees the native keyboard never opens
  inp.setAttribute('inputmode', 'none');
  const kb = $('kb');
  for (const row of KB_ROWS) {
    const r = document.createElement('div');
    r.className = 'kb-row';
    for (const k of row) {
      const b = document.createElement('button');
      b.className = k === 'back' ? 'key key-wide' : 'key';
      b.dataset.k = k;
      b.textContent = k === 'back' ? '⌫' : k;
      r.appendChild(b);
    }
    kb.appendChild(r);
  }
  kb.addEventListener('pointerdown', onKey);
}

async function boot() {
  trackViewport();
  setupTouchInput();
  // The generated emoji map is big and only needed once you play a word, so load it in
  // the background — it must not delay the title or the Play button. Absent = generic bonk.
  fetch(DATA + 'word_emoji.json').then((r) => r.json()).then(setGeneratedIcons).catch(() => {});

  const [rules, bank, dict, icons, styles] = await Promise.all([
    fetch(DATA + 'rules.json').then((r) => r.json()),
    fetch(DATA + 'word_bank.json').then((r) => r.json()),
    fetch(DATA + 'dictionary.json').then((r) => r.json()),
    fetch(DATA + 'icons.json').then((r) => r.json()),
    fetch(DATA + 'styles.json').then((r) => r.json()),
  ]);
  setRules(rules);
  setIcons(icons);
  STYLES = styles.styles.map((s) => [s.key, s.label]);
  if (!localStorage.getItem('wordplay.style')) artStyle = styles.default;
  lexicon = new Lexicon(dict.words);
  gauntlet = new Gauntlet();
  gauntlet.setup(bank);
  wireUI();
  showBest();
  updateTitleLogo();
  $('rules-body').textContent = RULES_TEXT;
  const play = $('play'); // title's already up; now that data's ready, let them start
  play.disabled = false;
  play.textContent = 'Play';
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
  bonkEnemy(res.word); // fling the word's emoji at the enemy
  const gain = res.dealt * num('gauntlet', 'score_per_damage', 3); // dealt already boosted
  S.score += gain;
  const uses = res.covered.length ? `  [uses ${upperLetters(res.covered).join(', ')}]` : '';
  logMsg(`You: ${res.word} hits for ${res.dealt}${uses}  +${gain}`);

  if (res.won) {
    const bonus = S.chapter * num('gauntlet', 'chapter_bonus', 25);
    S.score += bonus;
    S.hp = S.battle.player_hp;
    logMsg(`Chapter ${S.chapter} cleared!  (+${bonus} score)  Choose a reward.`);
    showPortrait('tombstone', S.creature || '', tombstone()); // R.I.P.
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
    btn.innerHTML =
      `<img class="art hidden" alt="" src="${artUrl('boon', boon.id)}"` +
      ` onload="this.classList.remove('hidden');this.nextElementSibling.classList.add('hidden')">` +
      `<div class="emoji">${boonIcon(boon.id)}</div>` +
      `<div class="label">${boon.label}</div><div class="desc">${boon.desc}</div>`;
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
    'Turn its weapons against it by using their letters';

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
  S.creature = owner ? owner.text : '';
  if (!S.choosing && !S.over) showPortrait('creature', S.creature, creatureIcon(S.creature));

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
      `<div class="pts">${value}</div></div><div class="bar"></div>`;
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
// Briefly transform the enemy portrait (whichever of emoji/img is showing), then reset.
function nudgePortrait(transform, { delay = 0, hold = 130 } = {}) {
  for (const p of [$('portrait'), $('portrait-img')]) {
    setTimeout(() => {
      p.style.transform = transform;
      setTimeout(() => (p.style.transform = ''), hold);
    }, delay);
  }
}
function lungePortrait() {
  nudgePortrait('translateX(14px) scale(1.25)');
}
const BONK_MS = 1300; // total flight time
const BONK_IMPACT = 0.26; // offset at which the emoji strikes — recoil derives from this
const GRAVITY = 'cubic-bezier(.5,0,.9,.45)'; // accelerating fall after the hit
// Fling the played word's emoji in from the left to "bonk" the enemy, then recoil it.
// bonkIcon() layers hand-curated icons over the generated map, with a '💥' fallback.
function bonkEnemy(word) {
  const fx = document.createElement('div');
  fx.className = 'bonk';
  fx.textContent = bonkIcon(word);
  $('portrait-holder').appendChild(fx);
  fx.animate(
    [
      // Offsets are % of the portrait box, so the arc scales with the portrait
      // (which is smaller on phones) and stays aligned. fly in from upper-left...
      { offset: 0, transform: 'translate(-70%,-40%) scale(.4) rotate(-30deg)', opacity: 0,
        easing: 'cubic-bezier(.2,.7,.3,1)' },
      // ...smack the enemy's left flank (stays off-center, projectile-sized)...
      { offset: BONK_IMPACT, transform: 'translate(-28%,-4%) scale(1.05) rotate(8deg)', opacity: 1,
        easing: 'ease-out' },
      // ...little pop up, then gravity takes over...
      { offset: 0.4, transform: 'translate(-25%,-15%) scale(.95) rotate(-4deg)', opacity: 1,
        easing: GRAVITY },
      { offset: 0.72, transform: 'translate(-17%,31%) scale(.8) rotate(20deg)', opacity: 1,
        easing: GRAVITY },
      // ...and tumbles off the bottom, fading as it falls.
      { offset: 1, transform: 'translate(-9%,107%) scale(.6) rotate(44deg)', opacity: 0 },
    ],
    { duration: BONK_MS },
  ).onfinish = () => fx.remove();
  // recoil fires when the emoji lands — kept in lockstep with the impact keyframe.
  nudgePortrait('translateX(11px) rotate(5deg)', { delay: BONK_MS * BONK_IMPACT, hold: 120 });
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
  $('strike-touch').onclick = onStrike; // big touch-only button; same handler
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

  // Options: pick the baked art style.
  const sel = $('style-select');
  sel.innerHTML = STYLES.map(([k, label]) => `<option value="${k}">${label}</option>`).join('');
  sel.value = artStyle;
  sel.onchange = () => {
    artStyle = sel.value;
    localStorage.setItem('wordplay.style', artStyle);
    updateTitleLogo(); // swap the title logo to match the skin
    if (S.battle && !S.over && !S.choosing) renderEnemy(); // redraw monster in the new skin
  };
  $('options').onclick = () => $('options-panel').classList.add('show');
  $('options-close').onclick = () => $('options-panel').classList.remove('show');

  // In-game hamburger menu.
  const closeMenu = () => $('menu').classList.add('hidden');
  $('menu-btn').onclick = (e) => {
    e.stopPropagation();
    $('menu').classList.toggle('hidden');
  };
  $('menu-howto').onclick = () => { closeMenu(); $('rules').classList.add('show'); };
  $('menu-options').onclick = () => { closeMenu(); $('options-panel').classList.add('show'); };
  $('menu-main').onclick = () => { closeMenu(); showBest(); $('title').classList.add('show'); };
  document.addEventListener('click', closeMenu); // click anywhere else closes it
}

boot();
