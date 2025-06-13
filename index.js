const express = require('express');
const path = require('path');
const fs = require('fs').promises;
const multer = require('multer');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const { exec } = require('child_process');
const util = require('util');
const execPromise = util.promisify(exec);

const app = express();
const PORT = 3000;

app.set('view engine', 'ejs');
app.use(express.static('public'));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const storage = multer.diskStorage({
  destination: './public/uploads/',
  filename: (req, file, cb) => {
    cb(null, Date.now() + path.extname(file.originalname));
  }
});
const upload = multer({ storage });

let config;
try {
  config = require('./config.json');
} catch (err) {
  console.error('Error loading config:', err);
  process.exit(1);
}

const SECRET_KEY = config.secret_key;

const loadData = async () => {
  try {
    const data = await fs.readFile('database.json', 'utf8');
    return JSON.parse(data);
  } catch (err) {
    return { students: [], teachers: [], gallery: [] };
  }
};

const saveData = async (data) => {
  try {
    await fs.writeFile('database.json', JSON.stringify(data, null, 2));
    await commitToGit('Update database.json');
  } catch (err) {
    console.error('Error saving data:', err);
  }
};

const commitToGit = async (message) => {
  try {
    await execPromise('git add .', { cwd: process.cwd() });
    await execPromise(`git commit -m "${message}"`, { cwd: process.cwd() });
    await execPromise(`git push origin ${config.git.branch}`, { cwd: process.cwd() });
    console.log('Git commit successful:', message);
  } catch (err) {
    console.error('Git commit failed:', err.message);
  }
};

const authMiddleware = (req, res, next) => {
  const token = req.headers['authorization']?.split(' ')[1];
  if (!token) return res.status(401).json({ error: 'Unauthorized' });
  try {
    jwt.verify(token, SECRET_KEY);
    next();
  } catch (err) {
    res.status(401).json({ error: 'Invalid token' });
  }
};

app.get('/', async (req, res) => {
  const data = await loadData();
  res.render('index', { data });
});

app.get('/students', async (req, res) => {
  const data = await loadData();
  res.render('students', { students: data.students });
});

app.get('/teachers', async (req, res) => {
  const data = await loadData();
  res.render('teachers', { teachers: data.teachers });
});

app.get('/gallery', async (req, res) => {
  const data = await loadData();
  res.render('gallery', { gallery: data.gallery });
});

app.get('/about', (req, res) => {
  res.render('about');
});

app.get('/developer', (req, res) => {
  res.render('developer');
});

app.get('/admin', (req, res) => {
  res.render('admin-login');
});

app.post('/admin/login', async (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) {
    return res.status(400).json({ error: 'Username and password are required' });
  }
  const hashedPassword = crypto.createHash('sha256').update(password).digest('hex');
  if (username === config.admin.username && hashedPassword === config.admin.password) {
    const token = jwt.sign({ username }, SECRET_KEY, { expiresIn: '1h' });
    res.json({ token });
  } else {
    res.status(401).json({ error: 'Invalid credentials' });
  }
});

app.get('/admin/panel', authMiddleware, async (req, res) => {
  const data = await loadData();
  res.render('admin-panel', { data });
});

app.post('/admin/students', authMiddleware, async (req, res) => {
  const { name } = req.body;
  if (!name) return res.status(400).json({ error: 'Name is required' });
  const data = await loadData();
  data.students.push({ id: Date.now(), name });
  await saveData(data);
  res.json({ success: true });
});

app.post('/admin/teachers', authMiddleware, async (req, res) => {
  const { name } = req.body;
  if (!name) return res.status(400).json({ error: 'Name is required' });
  const data = await loadData();
  data.teachers.push({ id: Date.now(), name });
  await saveData(data);
  res.json({ success: true });
});

app.post('/admin/gallery', authMiddleware, upload.single('image'), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'Image is required' });
  const data = await loadData();
  const imagePath = `/uploads/${req.file.filename}`;
  data.gallery.push({ id: Date.now(), path: imagePath });
  await saveData(data);
  await commitToGit(`Add gallery image ${req.file.filename}`);
  res.json({ success: true });
});

app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
