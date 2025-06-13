#!/bin/bash

# Setup script for Grade 12 Infinity TVL AFA website
# Run with: bash setup.sh <your_name> <admin_password> <git_repo_url>

set -e

# Check for required arguments
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <your_name> <admin_password> <git_repo_url>"
  exit 1
fi

YOUR_NAME="$1"
ADMIN_PASSWORD="$2"
GIT_REPO_URL="$3"

# Generate a simple SHA-256 hash for the admin password
HASHED_PASSWORD=$(echo -n "$ADMIN_PASSWORD" | shasum -a 256 | awk '{print $1}')
# Generate a random SECRET_KEY
SECRET_KEY=$(openssl rand -hex 16)

# Define project directory
PROJECT_DIR="./"
echo "Setting up project in $PROJECT_DIR..."

# Create project directory structure
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"
mkdir -p public/{css,js,uploads} views/partials

# Check for Node.js, npm, and Git
if ! command -v node &> /dev/null; then
  echo "Node.js is not installed. Please install it and try again."
  exit 1
fi
if ! command -v npm &> /dev/null; then
  echo "npm is not installed. Please install it and try again."
  exit 1
fi
if ! command -v git &> /dev/null; then
  echo "Git is not installed. Please install it and try again."
  exit 1
fi

# Create package.json
cat > package.json << 'EOF'
{
  "name": "grade12-infinity-tvl-afa",
  "version": "1.0.0",
  "description": "Website for Grade 12 Infinity TVL AFA",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "express": "^4.21.0",
    "ejs": "^3.1.10",
    "multer": "^1.4.5-lts.1",
    "jsonwebtoken": "^9.0.2"
  },
  "devDependencies": {
    "nodemon": "^3.1.7"
  }
}
EOF

# Install dependencies
echo "Installing dependencies..."
npm install

# Create config.json
cat > config.json << EOF
{
  "admin": {
    "username": "admin",
    "password": "$HASHED_PASSWORD"
  },
  "git": {
    "repo": "$GIT_REPO_URL",
    "branch": "main"
  },
  "secret_key": "$SECRET_KEY"
}
EOF

# Create server.js
cat > server.js << 'EOF'
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
EOF

# Create database.json
cat > database.json << 'EOF'
{
  "students": [],
  "teachers": [],
  "gallery": []
}
EOF

# Create .gitignore
cat > .gitignore << 'EOF'
node_modules/
.env
EOF

# Create views/index.ejs
cat > views/index.ejs << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Home - Grade 12 Infinity TVL AFA</title>
  <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
  <link href="https://fonts.googleapis.com/css2?family=Lora:wght@400;700&family=Roboto:wght@400;700&display=swap" rel="stylesheet">
  <link href="/css/styles.css" rel="stylesheet">
</head>
<body class="bg-afa-light font-lora">
  <%- include('partials/header', { currentPage: 'home' }) %>
  <main class="container mx-auto px-6 py-12">
    <section class="text-center bg-afa-card bg-opacity-80 p-8 rounded-lg shadow-lg animate-leaf-fall">
      <h2 class="text-4xl font-bold text-afa-dark mb-4 font-roboto">Welcome to Grade 12 Infinity TVL AFA</h2>
      <p class="text-lg text-gray-700 max-w-2xl mx-auto">Join our community of Agri-Fishery Arts enthusiasts, learning sustainable farming, aquaculture, and innovative agricultural techniques to cultivate a greener future.</p>
    </section>
  </main>
  <%- include('partials/footer') %>
  <script src="/js/main.js"></script>
</body>
</html>
EOF

# Create views/students.ejs
cat > views/students.ejs << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Students - Grade 12 Infinity TVL AFA</title>
  <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
  <link href="https://fonts.googleapis.com/css2?family=Lora:wght@400;700&family=Roboto:wght@400;700&display=swap" rel="stylesheet">
  <link href="/css/styles.css" rel="stylesheet">
</head>
<body class="bg-afa-light font-lora">
  <%- include('partials/header', { currentPage: 'students' }) %>
  <main class="container mx-auto px-6 py-12">
    <h2 class="text-3xl font-bold text-afa-dark mb-6 font-roboto animate-leaf-fall">Our Students</h2>
    <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-6">
      <% students.forEach(student => { %>
        <div class="bg-afa-card p-6 rounded-lg shadow-md hover:shadow-xl hover:scale-105 transition-all duration-300 animate-leaf-fall">
          <p class="text-lg text-gray-800"><%= student.name %></p>
        </div>
      <% }) %>
    </div>
  </main>
  <%- include('partials/footer') %>
  <script src="/js/main.js"></script>
</body>
</html>
EOF

# Create views/teachers.ejs
cat > views/teachers.ejs << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Teachers - Grade 12 Infinity TVL AFA</title>
  <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
  <link href="https://fonts.googleapis.com/css2?family=Lora:wght@400;700&family=Roboto:wght@400;700&display=swap" rel="stylesheet">
  <link href="/css/styles.css" rel="stylesheet">
</head>
<body class="bg-afa-light font-lora">
  <%- include('partials/header', { currentPage: 'teachers' }) %>
  <main class="container mx-auto px-6 py-12">
    <h2 class="text-3xl font-bold text-afa-dark mb-6 font-roboto animate-leaf-fall">Our Teachers</h2>
    <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-6">
      <% teachers.forEach(teacher => { %>
        <div class="bg-afa-card p-6 rounded-lg shadow-md hover:shadow-xl hover:scale-105 transition-all duration-300 animate-leaf-fall">
          <p class="text-lg text-gray-800"><%= teacher.name %></p>
        </div>
      <% }) %>
    </div>
  </main>
  <%- include('partials/footer') %>
  <script src="/js/main.js"></script>
</body>
</html>
EOF

# Create views/gallery.ejs
cat > views/gallery.ejs << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Gallery - Grade 12 Infinity TVL AFA</title>
  <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
  <link href="https://fonts.googleapis.com/css2?family=Lora:wght@400;700&family=Roboto:wght@400;700&display=swap" rel="stylesheet">
  <link href="/css/styles.css" rel="stylesheet">
</head>
<body class="bg-afa-light font-lora">
  <%- include('partials/header', { currentPage: 'gallery' }) %>
  <main class="container mx-auto px-6 py-12">
    <h2 class="text-3xl font-bold text-afa-dark mb-6 font-roboto animate-leaf-fall">Gallery</h2>
    <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-6">
      <% gallery.forEach(image => { %>
        <div class="relative overflow-hidden rounded-lg shadow-md hover:shadow-xl transition-all duration-300 animate-leaf-fall">
          <img src="<%= image.path %>" alt="Gallery Image" class="w-full h-64 object-cover transform hover:scale-110 transition-transform duration-500">
        </div>
      <% }) %>
    </div>
  </main>
  <%- include('partials/footer') %>
  <script src="/js/main.js"></script>
</body>
</html>
EOF

# Create views/about.ejs
cat > views/about.ejs << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>About - Grade 12 Infinity TVL AFA</title>
  <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
  <link href="https://fonts.googleapis.com/css2?family=Lora:wght@400;700&family=Roboto:wght@400;700&display=swap" rel="stylesheet">
  <link href="/css/styles.css" rel="stylesheet">
</head>
<body class="bg-afa-light font-lora">
  <%- include('partials/header', { currentPage: 'about' }) %>
  <main class="container mx-auto px-6 py-12">
    <section class="text-center bg-afa-card bg-opacity-80 p-8 rounded-lg shadow-lg animate-leaf-fall">
      <h2 class="text-3xl font-bold text-afa-dark mb-4 font-roboto">About Us</h2>
      <p class="text-lg text-gray-700 max-w-2xl mx-auto">Grade 12 Infinity TVL AFA is dedicated to mastering Agri-Fishery Arts, equipping students with skills in sustainable agriculture, aquaculture, and food production to nurture the earth and feed the future.</p>
    </section>
  </main>
  <%- include('partials/footer') %>
  <script src="/js/main.js"></script>
</body>
</html>
EOF

# Create views/developer.ejs
cat > views/developer.ejs << EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Developer - Grade 12 Infinity TVL AFA</title>
  <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
  <link href="https://fonts.googleapis.com/css2?family=Lora:wght@400;700&family=Roboto:wght@400;700&display=swap" rel="stylesheet">
  <link href="/css/styles.css" rel="stylesheet">
</head>
<body class="bg-afa-light font-lora">
  <%- include('partials/header', { currentPage: 'developer' }) %>
  <main class="container mx-auto px-6 py-12">
    <section class="text-center bg-afa-card bg-opacity-80 p-8 rounded-lg shadow-lg animate-leaf-fall">
      <h2 class="text-3xl font-bold text-afa-dark mb-4 font-roboto">Developer</h2>
      <p class="text-lg text-gray-700 max-w-2xl mx-auto">This website was crafted by $YOUR_NAME, a passionate TVL-AFA student blending technology with agriculture.</p>
    </section>
  </main>
  <%- include('partials/footer') %>
  <script src="/js/main.js"></script>
</body>
</html>
EOF

# Create views/admin-login.ejs
cat > views/admin-login.ejs << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Admin Login - Grade 12 Infinity TVL AFA</title>
  <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
  <link href="https://fonts.googleapis.com/css2?family=Lora:wght@400;700&family=Roboto:wght@400;700&display=swap" rel="stylesheet">
  <link href="/css/styles.css" rel="stylesheet">
</head>
<body class="bg-afa-light font-lora flex items-center justify-center min-h-screen">
  <div class="bg-afa-card p-8 rounded-lg shadow-lg w-full max-w-md animate-leaf-fall">
    <h2 class="text-2xl font-bold text-afa-dark mb-6 text-center font-roboto">Admin Login</h2>
    <form id="login-form" class="space-y-4">
      <div>
        <label class="block text-sm font-medium text-gray-700">Username</label>
        <input type="text" id="username" name="username" class="w-full p-3 border rounded-lg focus:ring-2 focus:ring-afa-green transition-all duration-300" required>
      </div>
      <div>
        <label class="block text-sm font-medium text-gray-700">Password</label>
        <input type="password" id="password" name="password" class="w-full p-3 border rounded-lg focus:ring-2 focus:ring-afa-green transition-all duration-300" required>
      </div>
      <button type="submit" class="w-full bg-afa-green text-white p-3 rounded-lg hover:bg-afa-dark transition-all duration-300 flex items-center justify-center">
        <span>Login</span>
        <svg id="login-spinner" class="hidden w-5 h-5 ml-2 animate-spin" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
      </button>
      <p id="login-error" class="text-red-500 text-sm hidden">Invalid credentials</p>
    </form>
  </div>
  <script src="/js/main.js"></script>
</body>
</html>
EOF

# Create views/admin-panel.ejs
cat > views/admin-panel.ejs << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Admin Panel - Grade 12 Infinity TVL AFA</title>
  <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
  <link href="https://fonts.googleapis.com/css2?family=Lora:wght@400;700&family=Roboto:wght@400;700&display=swap" rel="stylesheet">
  <link href="/css/styles.css" rel="stylesheet">
</head>
<body class="bg-afa-light font-lora">
  <%- include('partials/header', { currentPage: 'admin' }) %>
  <main class="container mx-auto px-6 py-12">
    <h2 class="text-3xl font-bold text-afa-dark mb-6 font-roboto animate-leaf-fall">Admin Panel</h2>
    <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
      <div class="bg-afa-card p-6 rounded-lg shadow-md animate-leaf-fall">
        <h3 class="text-xl font-bold text-afa-dark mb-4 font-roboto">Add Student</h3>
        <form id="student-form" action="/admin/students" method="POST" class="space-y-4">
          <input type="text" name="name" placeholder="Student Name" class="w-full p-3 border rounded-lg focus:ring-2 focus:ring-afa-green transition-all duration-300" required>
          <button type="submit" class="w-full bg-afa-green text-white p-3 rounded-lg hover:bg-afa-dark transition-all duration-300 flex items-center justify-center">
            <span>Add</span>
            <svg id="student-spinner" class="hidden w-5 h-5 ml-2 animate-spin" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
          </button>
          <p id="student-error" class="text-red-500 text-sm hidden"></p>
        </form>
      </div>
      <div class="bg-afa-card p-6 rounded-lg shadow-md animate-leaf-fall">
        <h3 class="text-xl font-bold text-afa-dark mb-4 font-roboto">Add Teacher</h3>
        <form id="teacher-form" action="/admin/teachers" method="POST" class="space-y-4">
          <input type="text" name="name" placeholder="Teacher Name" class="w-full p-3 border rounded-lg focus:ring-2 focus:ring-afa-green transition-all duration-300" required>
          <button type="submit" class="w-full bg-afa-green text-white p-3 rounded-lg hover:bg-afa-dark transition-all duration-300 flex items-center justify-center">
            <span>Add</span>
            <svg id="teacher-spinner" class="hidden w-5 h-5 ml-2 animate-spin" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
          </button>
          <p id="teacher-error" class="text-red-500 text-sm hidden"></p>
        </form>
      </div>
      <div class="bg-afa-card p-6 rounded-lg shadow-md animate-leaf-fall">
        <h3 class="text-xl font-bold text-afa-dark mb-4 font-roboto">Upload to Gallery</h3>
        <form id="gallery-form" action="/admin/gallery" method="POST" enctype="multipart/form-data" class="space-y-4">
          <input type="file" name="image" accept="image/*" class="w-full p-3 border rounded-lg" required>
          <button type="submit" class="w-full bg-afa-green text-white p-3 rounded-lg hover:bg-afa-dark transition-all duration-300 flex items-center justify-center">
            <span>Upload</span>
            <svg id="gallery-spinner" class="hidden w-5 h-5 ml-2 animate-spin" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
          </button>
          <p id="gallery-error" class="text-red-500 text-sm hidden"></p>
        </form>
      </div>
    </div>
  </main>
  <%- include('partials/footer') %>
  <script src="/js/main.js"></script>
</body>
</html>
EOF

# Create views/partials/header.ejs
cat > views/partials/header.ejs << 'EOF'
<% 
  const navItems = [
    { name: 'Home', href: '/', id: 'home' },
    { name: 'Students', href: '/students', id: 'students' },
    { name: 'Teachers', href: '/teachers', id: 'teachers' },
    { name: 'Gallery', href: '/gallery', id: 'gallery' },
    { name: 'About', href: '/about', id: 'about' },
    { name: 'Developer', href: '/developer', id: 'developer' },
    { name: 'Admin', href: '/admin', id: 'admin' }
  ];
%>
<header class="bg-afa-dark text-white sticky top-0 z-50 shadow-lg">
  <div class="container mx-auto px-4 py-4 flex justify-between items-center">
    <h1 class="text-2xl font-bold font-roboto">Grade 12 Infinity TVL AFA</h1>
    <button id="burger" class="md:hidden focus:outline-none">
      <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16m-7 6h7"></path>
      </svg>
    </button>
    <nav id="nav" class="hidden md:flex space-x-6">
      <% navItems.forEach(item => { %>
        <a href="<%= item.href %>" class="nav-link <%= currentPage === item.id ? 'text-afa-green font-semibold' : 'hover:text-afa-green' %> transition-all duration-300 font-roboto"><%= item.name %></a>
      <% }) %>
    </nav>
  </div>
  <div id="mobile-nav" class="hidden md:hidden bg-afa-dark">
    <% navItems.forEach(item => { %>
      <a href="<%= item.href %>" class="block py-3 px-4 text-white hover:bg-afa-green hover:text-white transition-all duration-300 font-roboto <%= currentPage === item.id ? 'bg-afa-green' : '' %>"><%= item.name %></a>
    <% }) %>
  </div>
</header>
EOF

# Create views/partials/footer.ejs
cat > views/partials/footer.ejs << 'EOF'
<footer class="bg-afa-dark text-white py-6">
  <div class="container mx-auto px-4 text-center">
    <p class="text-sm font-lora">© 2025 Grade 12 Infinity TVL AFA. Cultivating the future, one seed at a time.</p>
  </div>
</footer>
EOF

# Create public/css/styles.css
cat > public/css/styles.css << 'EOF'
/* Custom styles for Grade 12 Infinity TVL AFA website */
@tailwind base;
@tailwind components;
@tailwind utilities;

@font-face {
  font-family: 'Lora';
  src: url('https://fonts.googleapis.com/css2?family=Lora:wght@400;700&display=swap');
}

@font-face {
  font-family: 'Roboto';
  src: url('https://fonts.googleapis.com/css2?family=Roboto:wght@400;700&display=swap');
}

body {
  @apply font-lora bg-afa-light;
  background-image: url('/uploads/leaf-pattern.png');
  background-repeat: repeat;
  background-size: 200px;
  background-opacity: 0.1;
}

.bg-afa-light {
  background-color: #f5f6f0;
}

.bg-afa-dark {
  background-color: #2e4f3b;
}

.text-afa-dark {
  color: #2e4f3b;
}

.bg-afa-card {
  background-color: #e8e8d5;
  background-image: linear-gradient(45deg, #f0e8c8, #e8e8d5);
}

.bg-afa-green {
  background-color: #4a7043;
}

.text-afa-green {
  color: #4a7043;
}

.nav-link:hover {
  @apply transform scale-105;
}

.animate-leaf-fall {
  animation: leafFall 1s ease-in-out;
}

@keyframes leafFall {
  0% { transform: translateY(-20px) rotate(5deg); opacity: 0; }
  50% { transform: translateY(10px) rotate(-5deg); }
  100% { transform: translateY(0) rotate(0); opacity: 1; }
}

input:focus, button:focus {
  @apply outline-none ring-2 ring-afa-green;
}

button {
  @apply rounded-lg border-2 border-afa-green;
}

.animate-spin {
  animation: spin 1s linear infinite;
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}
EOF

# Create public/js/main.js
cat > public/js/main.js << 'EOF'
document.addEventListener('DOMContentLoaded', () => {
  // Burger menu toggle
  const burger = document.getElementById('burger');
  const mobileNav = document.getElementById('mobile-nav');
  if (burger && mobileNav) {
    burger.addEventListener('click', () => {
      mobileNav.classList.toggle('hidden');
      mobileNav.classList.toggle('animate-leaf-fall');
    });
  }

  // Form submission handler
  const handleFormSubmit = async (formId, spinnerId, errorId, action, method, isMultipart = false) => {
    const form = document.getElementById(formId);
    const spinner = document.getElementById(spinnerId);
    const error = document.getElementById(errorId);
    if (!form) return;

    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      if (spinner) spinner.classList.remove('hidden');
      if (error) error.classList.add('hidden');

      try {
        const formData = isMultipart ? new FormData(form) : new FormData(form);
        const headers = isMultipart ? { 'Authorization': `Bearer ${localStorage.getItem('token')}` } : {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${localStorage.getItem('token')}`
        };
        const body = isMultipart ? formData : JSON.stringify(Object.fromEntries(formData));

        const res = await fetch(action, {
          method,
          headers,
          body
        });

        if (res.ok) {
          if (formId === 'login-form') {
            const { token } = await res.json();
            localStorage.setItem('token', token);
            window.location.href = '/admin/panel';
          } else {
            window.location.reload();
          }
        } else {
          const { error: errMsg } = await res.json();
          if (error) {
            error.textContent = errMsg || 'An error occurred';
            error.classList.remove('hidden');
          }
        }
      } catch (err) {
        if (error) {
          error.textContent = 'Network error, please try again';
          error.classList.remove('hidden');
        }
      } finally {
        if (spinner) spinner.classList.add('hidden');
      }
    });
  };

  // Initialize forms
  handleFormSubmit('login-form', 'login-spinner', 'login-error', '/admin/login', 'POST');
  handleFormSubmit('student-form', 'student-spinner', 'student-error', '/admin/students', 'POST');
  handleFormSubmit('teacher-form', 'teacher-spinner', 'teacher-error', '/admin/teachers', 'POST');
  handleFormSubmit('gallery-form', 'gallery-spinner', 'gallery-error', '/admin/gallery', 'POST', true);
});
EOF

# Create a placeholder leaf pattern (optional, replace with actual image if available)
touch public/uploads/leaf-pattern.png

# Initialize Git repository
echo "Initializing Git repository..."
git init
git remote add origin "$GIT_REPO_URL"
git add .
git commit -m "Initial commit"

# Print instructions
echo "Setup complete! To start the server:"
echo "1. cd $PROJECT_DIR"
echo "2. Configure Git authentication (e.g., SSH or HTTPS credentials)"
echo "3. Run: git push -u origin main"
echo "4. Run: npm start"
echo "Access the website at http://localhost:3000"
echo "Admin login: username=admin, password=$ADMIN_PASSWORD"
echo "Note: Replace public/uploads/leaf-pattern.png with an actual leaf pattern image for the background."
EOF

# Make the script executable
chmod +x setup.sh

