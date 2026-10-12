const { test } = require('node:test');
const assert = require('node:assert/strict');
const { ShareImportModel } = require('../ios/ShareExtension/Resources/model.js');

const draft = () => ({ title: 'Lime pie', original_language: 'en', measurement_system: 'us',
  import_key: 'a'.repeat(64), source_text: 'recipe text',
  ingredients: [{ id: 'new-ingredients-0', original_text: '1 lime', ingredient_name: 'lime', quantity_decimal: '1' }],
  steps: [{ id: 'new-steps-0', instruction: 'Bake for 20 minutes.' }],
  actions: [{ id: 'new-actions-0', step_id: 'new-steps-0', action_type: 'timer', duration_seconds: 1200 }],
  category_assignments: [{ label: 'Pies', parent_label: 'Desserts' }],
  groups: [], photos: [], tags: [], pairings: [], photo_suggestions: [{ url: 'https://example.com/food.jpg' }],
  edit_options: { categories: [] } });

function fixture(overrides = {}) {
  const calls = [];
  const handlers = {
    read: () => [{ name: 'pie.pdf', body: { kind: 'file', file_base64: 'fixture' } },
                 { name: 'text', body: { kind: 'text', text: 'bread' } }],
    signIn: () => ({ households: [{ id: '1', name: 'First table' }, { id: '2', name: 'Other table' }] }),
    analyze: () => ({ recipe: draft(), questions: [] }),
    save: () => ({ recipe: { id: '42' } }), close: () => undefined, ...overrides,
  };
  const model = new ShareImportModel(async (action, values) => {
    calls.push({ action, values: structuredClone(values) });
    return handlers[action](values);
  });
  return { model, calls };
}

test('read, login and analysis never save; explicit save sends edited structured recipe to selected table', async () => {
  const { model, calls } = fixture();
  await model.read();
  await model.signIn(' joe@example.com ', 'password');
  model.household = '2';
  await model.analyze();
  assert.equal(calls.some(c => c.action === 'save'), false);
  model.draft.title = 'Reviewed lime pie';
  await model.save();
  const saved = calls.find(c => c.action === 'save').values;
  assert.equal(saved.household, '2');
  assert.equal(saved.body.title, 'Reviewed lime pie');
  assert.deepEqual(saved.body.actions, draft().actions);
  assert.deepEqual(saved.body.category_assignments, draft().category_assignments);
  assert.equal(saved.body.photo_suggestions, undefined);
  assert.equal(saved.body.edit_options, undefined);
  assert.equal(model.saved, 1);
  assert.equal(model.index, 1);
  assert.equal(model.inputs[0], null);
  assert.equal(model.draft, null);
  assert.equal(model.finished, false);
});

test('clarification requires answers, preserves import identity, and does not save', async () => {
  let round = 0;
  const { model, calls } = fixture({ analyze: () => ({ recipe: draft(), questions: round++ ? [] : ['How much lime?'] }) });
  await model.read(); await model.signIn('joe@example.com', 'password'); await model.analyze();
  await assert.rejects(model.save(), /reviewing/);
  await assert.rejects(model.analyze(['']), /Answer each/);
  await model.analyze(['2 limes']);
  const body = calls.filter(c => c.action === 'analyze')[1].values.body;
  assert.equal(body.kind, 'answers');
  assert.equal(body.import_identity, 'a'.repeat(64));
  assert.equal(body.recipe.photo_suggestions, undefined);
  assert.deepEqual(body.answers, [{ question: 'How much lime?', answer: '2 limes' }]);
  assert.equal(model.questions.length, 0);
  assert.equal(calls.some(c => c.action === 'save'), false);
});

test('analysis and rejected saves retain input and edits for retry', async () => {
  let analysis = 0, saves = 0;
  const { model } = fixture({
    analyze: () => { if (!analysis++) throw Error('Server busy'); return { recipe: draft(), questions: [] }; },
    save: () => { if (!saves++) throw Error('Please enter title.'); return { recipe: { id: '42' } }; }
  });
  await model.read(); await model.signIn('joe@example.com', 'password');
  await assert.rejects(model.analyze(), /Server busy/);
  assert.equal(model.inputs[0].body.file_base64, 'fixture');
  await model.analyze(); model.draft.title = 'Edited';
  await assert.rejects(model.save(), /Please enter/);
  assert.equal(model.index, 0); assert.equal(model.draft.title, 'Edited');
  await model.save(); assert.equal(model.saved, 1);
});

test('cancel and skip do not save; close releases pending content', async () => {
  const { model, calls } = fixture();
  await model.read(); await model.signIn('joe@example.com', 'password'); await model.analyze();
  model.skip(); assert.equal(model.draft, null); assert.equal(model.index, 1);
  await model.close();
  assert.equal(model.inputs.length, 0); assert.equal(model.closed, true);
  assert.equal(calls.some(c => c.action === 'save'), false);
  await assert.rejects(model.save());
});

test('double taps cannot submit duplicate saves', async () => {
  let finish;
  const { model, calls } = fixture({ save: () => new Promise(resolve => finish = resolve) });
  await model.read(); await model.signIn('joe@example.com', 'password'); await model.analyze();
  const saving = model.save();
  await assert.rejects(model.save(), /Wait/);
  finish({ recipe: { id: '42' } }); await saving;
  assert.equal(calls.filter(c => c.action === 'save').length, 1);
});

test('failed login and empty household membership never analyze or save', async () => {
  const { model, calls } = fixture({ signIn: () => ({ households: [] }) });
  await model.read(); await assert.rejects(model.signIn('joe@example.com', 'password'), /Join or create/);
  await assert.rejects(model.analyze(), /Choose your table/);
  assert.equal(calls.some(c => c.action === 'analyze' || c.action === 'save'), false);
});

test('each attachment requires its own review and explicit save', async () => {
  const { model, calls } = fixture();
  await model.read(); await model.signIn('joe@example.com', 'password');
  await model.analyze(); await model.save();
  assert.equal(calls.filter(c => c.action === 'save').length, 1);
  await model.analyze(); await model.save();
  assert.equal(calls.filter(c => c.action === 'analyze')[1].values.body.text, 'bread');
  assert.equal(model.finished, true); assert.equal(model.saved, 2);
});

test('a lost save response cannot be retried and accidentally create a duplicate', async () => {
  const { model, calls } = fixture({ save: () => { throw Error('Save outcome unknown. Check your table.'); } });
  await model.read(); await model.signIn('joe@example.com', 'password'); await model.analyze();
  await assert.rejects(model.save(), /Save outcome unknown/);
  assert.equal(model.saveUncertain, true);
  await assert.rejects(model.save(), /previous save may have succeeded/);
  assert.equal(calls.filter(c => c.action === 'save').length, 1);
});
