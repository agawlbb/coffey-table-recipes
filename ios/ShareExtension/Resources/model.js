'use strict';
const cloneRecipe = value => JSON.parse(JSON.stringify(value));

// The extension owns its input and login. Only an explicit Save writes a recipe.
class ShareImportModel {
  constructor(request) {
    this.request = request;
    this.inputs = [];
    this.index = 0;
    this.households = [];
    this.household = '';
    this.draft = null;
    this.questions = [];
    this.saved = 0;
    this.busy = false;
    this.closed = false;
    this.saveUncertain = false;
  }
  async exclusive(work) {
    if (this.busy || this.closed) throw new Error('Wait for the current request to finish.');
    this.busy = true;
    try { return await work(); } finally { this.busy = false; }
  }
  async read() {
    return this.exclusive(async () => {
      this.inputs = await this.request('read');
      if (!Array.isArray(this.inputs) || !this.inputs.length) throw new Error('No readable recipe was shared.');
    });
  }
  async signIn(email, password) {
    return this.exclusive(async () => {
      const data = await this.request('signIn', { email: email.trim(), password });
      this.households = data.households || [];
      if (!this.households.length) throw new Error('Join or create a table in the app, then share again.');
      this.household = String(this.households[0].id);
    });
  }
  async analyze(answers) {
    return this.exclusive(async () => {
      if (!this.household) throw new Error('Choose your table first.');
      let body = this.inputs[this.index].body;
      if (this.draft) {
        if (!answers || answers.length !== this.questions.length || answers.some(a => !a.trim())) {
          throw new Error('Answer each question, or enter “unknown”.');
        }
        const recipe = cloneRecipe(this.draft);
        delete recipe.photo_suggestions;
        body = { kind: 'answers', recipe, text: recipe.source_text || '', url: recipe.source_url,
          import_identity: recipe.import_key,
          answers: this.questions.map((question, i) => ({ question, answer: answers[i].trim() })) };
      }
      const data = await this.request('analyze', { household: this.household, body });
      if (!data.recipe || !Array.isArray(data.questions)) throw new Error('The server returned an unreadable draft. Try again.');
      this.draft = data.recipe;
      this.questions = data.questions;
    });
  }
  async save() {
    return this.exclusive(async () => {
      if (!this.draft || this.questions.length) throw new Error('Finish reviewing the recipe first.');
      if (this.saveUncertain) throw new Error('Check your table in the app before sharing again. The previous save may have succeeded.');
      if (!String(this.draft.title || '').trim()) throw new Error('Enter a recipe title.');
      const body = cloneRecipe(this.draft);
      delete body.photo_suggestions;
      delete body.edit_options;
      let data;
      try {
        data = await this.request('save', { household: this.household, body });
        if (!data.recipe || !data.recipe.id) throw new Error('Save outcome unknown. Check your table in the app before sharing again.');
      } catch (error) {
        if (error.message.startsWith('Save outcome unknown.')) this.saveUncertain = true;
        throw error;
      }
      this.saved++;
      this.advance();
    });
  }
  advance() {
    // Release large attachment bytes as soon as this input is finished.
    this.inputs[this.index] = null;
    this.index++;
    this.draft = null;
    this.questions = [];
    this.saveUncertain = false;
  }
  skip() { if (!this.busy && !this.closed) this.advance(); }
  close() { this.closed = true; this.inputs = []; this.draft = null; return this.request('close'); }
  get finished() { return this.index >= this.inputs.length; }
}
if (typeof module !== 'undefined') module.exports = { ShareImportModel };
