const fs = require('fs').promises;
const path = require('path');
const { execPromise } = require('../utils/git');

const DB_PATH = path.join(process.cwd(), 'database.json');

async function loadData() {
  try {
    const data = await fs.readFile(DB_PATH, 'utf8');
    return JSON.parse(data);
  } catch (err) {
    const defaultData = { students: [], teachers: [], gallery: [] };
    await fs.writeFile(DB_PATH, JSON.stringify(defaultData, null, 2));
    return defaultData;
  }
}

async function saveData(data) {
  try {
    await fs.writeFile(DB_PATH, JSON.stringify(data, null, 2));
    await commitToGit('Update database');
    return true;
  } catch (err) {
    console.error('Error saving data:', err);
    return false;
  }
}

async function commitToGit(message) {
  try {
    await execPromise('git add database.json');
    await execPromise(`git commit -m "${message}"`);
    await execPromise('git push origin main');
    return true;
  } catch (err) {
    console.error('Git commit failed:', err.message);
    return false;
  }
}

module.exports = { loadData, saveData };
