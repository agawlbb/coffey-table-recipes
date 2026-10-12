'use strict';
let sequence = 0;
const pending = new Map();
function request(action, values = {}) {
  return new Promise((resolve, reject) => {
    const id = ++sequence;
    if (action !== 'close') pending.set(id, { resolve, reject });
    window.webkit.messageHandlers.recipeShare.postMessage({ id, action, ...values });
    if (action === 'close') resolve();
  });
}
window.recipeShareReply = (id, value, error) => {
  const waiter = pending.get(id);
  if (!waiter) return;
  pending.delete(id);
  if (error) waiter.reject(new Error(error)); else waiter.resolve(value);
};
const model = new ShareImportModel(request);
const screen = document.getElementById('screen');
const status = document.getElementById('status');
const error = document.getElementById('error');
const close = document.getElementById('close');
close.onclick = () => {
  if (model.busy && !confirm('Cancel this import? A save already sent to the server may still finish.')) return;
  model.close();
};
function el(tag, text, parent = screen) {
  const node = document.createElement(tag);
  if (text !== undefined) node.textContent = text;
  parent.appendChild(node);
  return node;
}
function button(text, action, parent = screen) {
  const node = el('button', text, parent);
  node.type = 'button';
  node.onclick = action;
  return node;
}
function field(title, value, parent = screen, multiline = false) {
  const label = el('label', undefined, parent);
  el('span', title, label);
  const input = el(multiline ? 'textarea' : 'input', undefined, label);
  input.value = value ?? '';
  return input;
}
async function work(message, action, success) {
  error.hidden = true;
  status.textContent = message;
  screen.querySelectorAll('button, input, textarea, select').forEach(n => n.disabled = true);
  try { await action(); if (!model.closed) success(); }
  catch (e) { if (!model.closed) { error.textContent = e.message; error.hidden = false; status.textContent = 'Your input is still here.'; } }
  finally {
    screen.querySelectorAll('button, input, textarea, select').forEach(n => n.disabled = false);
    if (model.saveUncertain) {
      const save = document.getElementById('save');
      if (save) save.disabled = true;
    }
  }
}
function login() {
  screen.replaceChildren();
  status.textContent = 'Sign in to save to your table. Nothing is saved until you review and tap Save.';
  const form = el('form');
  const email = field('Email', '', form); email.type = 'email'; email.autocomplete = 'username'; email.required = true;
  const password = field('Password', '', form); password.type = 'password'; password.autocomplete = 'current-password'; password.required = true;
  const submit = el('button', 'Sign in', form); submit.type = 'submit';
  form.onsubmit = e => {
    e.preventDefault();
    work('Signing in…', () => model.signIn(email.value, password.value), () => { password.value = ''; choose(); });
  };
  el('p', 'Use your app email and password. Google-only accounts can set an email password using Forgot password in the app. Sign-in lasts for this share session.', form).className = 'hint';
}
function choose() {
  screen.replaceChildren();
  if (model.finished) { complete(); return; }
  status.textContent = `Recipe ${model.index + 1} of ${model.inputs.length}`;
  el('h2', model.inputs[model.index].name);
  const label = el('label'); el('span', 'Save to table', label);
  const select = el('select', undefined, label);
  model.households.forEach(h => { const option = el('option', h.name, select); option.value = String(h.id); });
  select.value = model.household;
  select.onchange = () => model.household = select.value;
  const input = model.inputs[model.index].body;
  if (input.kind === 'text' || input.kind === 'website') {
    const key = input.kind === 'text' ? 'text' : 'url';
    const source = field(key === 'text' ? 'Shared text' : 'Website link', input[key], screen, key === 'text');
    source.oninput = () => input[key] = source.value;
  } else el('p', 'This file will be analyzed to prepare a recipe for your review.');
  button('Prepare recipe', () => work('Preparing your recipe…', () => model.analyze(), review));
  button('Skip this item', () => { model.skip(); choose(); }).className = 'secondary';
}
const hiddenKeys = new Set(['id', 'revision', 'import_key', 'source_text', 'edit_options', 'photo_suggestions', 'import_warnings', 'group_id', 'step_id', 'position', 'household_id', 'recipe_id']);
const numericKeys = new Set(['servings', 'prep_minutes', 'cook_minutes', 'total_minutes', 'quantity_decimal', 'quantity_numerator', 'quantity_denominator', 'quantity_max_decimal', 'duration_seconds', 'temperature_value']);
const booleanKeys = new Set(['is_optional', 'is_main_ingredient', 'scale_quantity']);
function title(key) {
  const names = { category_assignments: 'Browse categories', yield_text: 'Recipe yield',
    prep_minutes: 'Preparation time (minutes)', cook_minutes: 'Cooking time (minutes)',
    total_minutes: 'Total time (minutes)', quantity_decimal: 'Exact decimal quantity',
    quantity_numerator: 'Fraction numerator', quantity_denominator: 'Fraction denominator',
    us: 'US', source_type: 'Source', original_text: 'Ingredient as written' };
  return names[key] || key.replaceAll('_', ' ').replace(/^./, c => c.toUpperCase());
}
function editObject(object, parent, keys = Object.keys(object)) {
  keys.filter(key => Object.hasOwnProperty.call(object, key)).forEach(key => {
    const value = object[key];
    if (hiddenKeys.has(key) || key.startsWith('_')) return;
    if (Array.isArray(value)) {
      if (!value.length) return;
      const details = el('details', undefined, parent); el('summary', `${title(key)} (${value.length})`, details);
      value.forEach((row, i) => {
        const group = el('fieldset', undefined, details); el('legend', `${title(key)} ${i + 1}`, group);
        if (row && typeof row === 'object') editObject(row, group);
        else el('p', String(row), group);
      });
    } else if (value && typeof value === 'object') {
      const details = el('details', undefined, parent); el('summary', title(key), details); editObject(value, details);
    } else {
      if (key === 'measurement_system') {
        const label = el('label', undefined, parent); el('span', title(key), label);
        const select = el('select', undefined, label);
        ['metric', 'us', 'mixed', 'unspecified'].forEach(v => { const o = el('option', title(v), select); o.value = v; });
        select.value = value; select.onchange = () => object[key] = select.value; return;
      }
      const input = field(title(key), value, parent, ['description', 'instruction', 'notes', 'source_reference'].includes(key));
      if (booleanKeys.has(key)) { input.type = 'checkbox'; input.checked = Boolean(Number(value)); }
      if (numericKeys.has(key)) { input.type = 'number'; input.step = 'any'; }
      input.oninput = () => object[key] = booleanKeys.has(key) ? (input.checked ? 1 : 0) : (input.value === '' ? null : input.value);
    }
  });
}
function review() {
  screen.replaceChildren();
  if (model.questions.length) {
    status.textContent = 'Answer these questions to finish preparing the recipe.';
    const answers = model.questions.map(q => field(q, '', screen, true));
    button('Continue', () => work('Updating the recipe…', () => model.analyze(answers.map(a => a.value)), review));
  } else {
    status.textContent = 'Review and edit before saving. You can edit the full recipe again in the app after saving.';
    el('h2', `Save to ${model.households.find(h => String(h.id) === model.household)?.name || 'your table'}`);
    (model.draft.import_warnings || []).forEach(w => el('p', w));
    const primary = ['title', 'description', 'ingredients', 'steps', 'category_assignments', 'notes'];
    editObject(model.draft, screen, primary);
    const details = el('details'); el('summary', 'Yield, times and other details', details);
    editObject(model.draft, details, Object.keys(model.draft).filter(key => !primary.includes(key)));
    const save = button('Save recipe', () => work('Saving recipe…', () => model.save(), () => {
      if (model.finished) complete();
      else { choose(); status.textContent = 'Recipe saved. Review the next shared item.'; }
    }));
    save.id = 'save';
  }
  button('Discard this item', () => { if (confirm('Discard this recipe without saving?')) { model.skip(); choose(); } }).className = 'secondary';
}
function complete() {
  screen.replaceChildren();
  status.textContent = model.saved ? `${model.saved} recipe${model.saved === 1 ? '' : 's'} saved. Open the app to see them at your table.` : 'No recipes saved.';
  close.textContent = 'Done';
  button('Done', () => model.close());
}
async function start() {
  screen.replaceChildren();
  await work('Reading shared content…', () => model.read(), login);
  if (!model.inputs.length) button('Retry reading', start);
}
start();
