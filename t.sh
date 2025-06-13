#!/bin/bash

set -e

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <your_name> <admin_password> <git_repo_url>"
  exit 1
fi

YOUR_NAME="$1"
ADMIN_PASSWORD="$2"
GIT_REPO_URL="$3"

HASHED_PASSWORD=$(echo -n "$ADMIN_PASSWORD" | shasum -a 256 | awk '{print $1}')
SECRET_KEY=$(openssl rand -hex 32)

PROJECT_DIR="./"
echo "Setting up project in $PROJECT_DIR..."

mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"
mkdir -p public/{css,js,uploads,fonts,images} views/{partials,layouts} routes controllers models

if ! command -v node &> /dev/null || ! command -v npm &> /dev/null || ! command -v git &> /dev/null; then
  echo "Required tools (Node.js, npm, or Git) are missing. Please install them and try again."
  exit 1
fi

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
    "jsonwebtoken": "^9.0.2",
    "bcrypt": "^5.1.1",
    "cookie-parser": "^1.4.6",
    "express-validator": "^7.0.1",
    "dotenv": "^16.3.1"
  },
  "devDependencies": {
    "nodemon": "^3.1.7"
  }
}
EOF

echo "Installing dependencies..."
npm install

cat > .env << EOF
PORT=3000
SECRET_KEY="$SECRET_KEY"
NODE_ENV=development
GIT_REPO="$GIT_REPO_URL"
GIT_BRANCH="main"
EOF

cat > models/database.js << 'EOF'
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
EOF

cat > utils/git.js << 'EOF'
const util = require('util');
const { exec } = require('child_process');

const execPromise = util.promisify(exec);

module.exports = { execPromise };
EOF

cat > controllers/authController.js << 'EOF'
const jwt = require('jsonwebtoken');
const bcrypt = require('bcrypt');
const fs = require('fs').promises;
const path = require('path');

const CONFIG_PATH = path.join(process.cwd(), 'config.json');

async function loadConfig() {
  try {
    const data = await fs.readFile(CONFIG_PATH, 'utf8');
    return JSON.parse(data);
  } catch (err) {
    console.error('Error loading config:', err);
    process.exit(1);
  }
}

async function login(req, res) {
  try {
    const { username, password } = req.body;
    const config = await loadConfig();
    
    if (!username || !password) {
      return res.status(400).json({ error: 'Username and password are required' });
    }
    
    if (username !== config.admin.username) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }
    
    const passwordMatch = config.admin.password === req.hashedPassword;
    
    if (!passwordMatch) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }
    
    const token = jwt.sign({ username }, process.env.SECRET_KEY, { expiresIn: '4h' });
    
    res.cookie('token', token, {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      maxAge: 4 * 60 * 60 * 1000
    });
    
    res.json({ token, success: true });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ error: 'Server error' });
  }
}

function authMiddleware(req, res, next) {
  try {
    const token = req.cookies.token || req.headers.authorization?.split(' ')[1];
    
    if (!token) {
      return res.status(401).json({ error: 'Authentication required' });
    }
    
    jwt.verify(token, process.env.SECRET_KEY, (err, decoded) => {
      if (err) {
        return res.status(401).json({ error: 'Invalid or expired token' });
      }
      
      req.user = decoded;
      next();
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
}

module.exports = { login, authMiddleware };
EOF

cat > controllers/dataController.js << 'EOF'
const { loadData, saveData } = require('../models/database');

async function addStudent(req, res) {
  try {
    const { name } = req.body;
    
    if (!name || name.trim() === '') {
      return res.status(400).json({ error: 'Valid name is required' });
    }
    
    const data = await loadData();
    data.students.push({ id: Date.now(), name: name.trim() });
    
    const success = await saveData(data);
    
    if (success) {
      res.json({ success: true, message: 'Student added successfully' });
    } else {
      res.status(500).json({ error: 'Failed to save data' });
    }
  } catch (err) {
    console.error('Error adding student:', err);
    res.status(500).json({ error: 'Server error' });
  }
}

async function addTeacher(req, res) {
  try {
    const { name } = req.body;
    
    if (!name || name.trim() === '') {
      return res.status(400).json({ error: 'Valid name is required' });
    }
    
    const data = await loadData();
    data.teachers.push({ id: Date.now(), name: name.trim() });
    
    const success = await saveData(data);
    
    if (success) {
      res.json({ success: true, message: 'Teacher added successfully' });
    } else {
      res.status(500).json({ error: 'Failed to save data' });
    }
  } catch (err) {
    console.error('Error adding teacher:', err);
    res.status(500).json({ error: 'Server error' });
  }
}

async function addGalleryImage(req, res) {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'Image is required' });
    }
    
    const data = await loadData();
    const imagePath = `/uploads/${req.file.filename}`;
    data.gallery.push({ id: Date.now(), path: imagePath });
    
    const success = await saveData(data);
    
    if (success) {
      res.json({ success: true, message: 'Image added successfully' });
    } else {
      res.status(500).json({ error: 'Failed to save data' });
    }
  } catch (err) {
    console.error('Error adding gallery image:', err);
    res.status(500).json({ error: 'Server error' });
  }
}

module.exports = { addStudent, addTeacher, addGalleryImage };
EOF

cat > controllers/viewController.js << 'EOF'
const { loadData } = require('../models/database');

async function renderHome(req, res) {
  try {
    const data = await loadData();
    res.render('index', { data, title: 'Home' });
  } catch (err) {
    console.error('Error rendering home:', err);
    res.status(500).render('error', { message: 'Failed to load data' });
  }
}

async function renderStudents(req, res) {
  try {
    const data = await loadData();
    res.render('students', { students: data.students, title: 'Students' });
  } catch (err) {
    console.error('Error rendering students:', err);
    res.status(500).render('error', { message: 'Failed to load student data' });
  }
}

async function renderTeachers(req, res) {
  try {
    const data = await loadData();
    res.render('teachers', { teachers: data.teachers, title: 'Teachers' });
  } catch (err) {
    console.error('Error rendering teachers:', err);
    res.status(500).render('error', { message: 'Failed to load teacher data' });
  }
}

async function renderGallery(req, res) {
  try {
    const data = await loadData();
    res.render('gallery', { gallery: data.gallery, title: 'Gallery' });
  } catch (err) {
    console.error('Error rendering gallery:', err);
    res.status(500).render('error', { message: 'Failed to load gallery data' });
  }
}

function renderAbout(req, res) {
  res.render('about', { title: 'About Us' });
}

function renderDeveloper(req, res) {
  res.render('developer', { title: 'Developer' });
}

function renderAdminLogin(req, res) {
  res.render('admin-login', { title: 'Admin Login' });
}

async function renderAdminPanel(req, res) {
  try {
    const data = await loadData();
    res.render('admin-panel', { data, title: 'Admin Panel' });
  } catch (err) {
    console.error('Error rendering admin panel:', err);
    res.status(500).render('error', { message: 'Failed to load data' });
  }
}

module.exports = {
  renderHome,
  renderStudents,
  renderTeachers,
  renderGallery,
  renderAbout,
  renderDeveloper,
  renderAdminLogin,
  renderAdminPanel
};
EOF

cat > routes/index.js << 'EOF'
const express = require('express');
const router = express.Router();
const viewController = require('../controllers/viewController');

router.get('/', viewController.renderHome);
router.get('/students', viewController.renderStudents);
router.get('/teachers', viewController.renderTeachers);
router.get('/gallery', viewController.renderGallery);
router.get('/about', viewController.renderAbout);
router.get('/developer', viewController.renderDeveloper);

module.exports = router;
EOF

cat > routes/admin.js << 'EOF'
const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const crypto = require('crypto');
const viewController = require('../controllers/viewController');
const authController = require('../controllers/authController');
const dataController = require('../controllers/dataController');

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, './public/uploads/');
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    const ext = path.extname(file.originalname);
    cb(null, uniqueSuffix + ext);
  }
});

const fileFilter = (req, file, cb) => {
  const allowedTypes = /jpeg|jpg|png|gif|webp/;
  const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
  const mimetype = allowedTypes.test(file.mimetype);
  
  if (extname && mimetype) {
    return cb(null, true);
  }
  
  cb(new Error('Only image files are allowed'));
};

const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter
});

router.get('/', viewController.renderAdminLogin);
router.get('/panel', authController.authMiddleware, viewController.renderAdminPanel);

router.post('/login', (req, res, next) => {
  const { password } = req.body;
  req.hashedPassword = crypto.createHash('sha256').update(password).digest('hex');
  next();
}, authController.login);

router.post('/students', authController.authMiddleware, dataController.addStudent);
router.post('/teachers', authController.authMiddleware, dataController.addTeacher);
router.post('/gallery', authController.authMiddleware, upload.single('image'), dataController.addGalleryImage);

module.exports = router;
EOF

cat > server.js << 'EOF'
require('dotenv').config();
const express = require('express');
const path = require('path');
const cookieParser = require('cookie-parser');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3000;

const indexRoutes = require('./routes/index');
const adminRoutes = require('./routes/admin');

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

app.use(express.static(path.join(__dirname, 'public')));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(cookieParser());

app.use((req, res, next) => {
  res.locals.currentPath = req.path;
  next();
});

app.use('/', indexRoutes);
app.use('/admin', adminRoutes);

app.use((req, res) => {
  res.status(404).render('error', { message: 'Page not found', title: 'Error' });
});

app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).render('error', { message: 'Something went wrong', title: 'Error' });
});

if (!fs.existsSync('./database.json')) {
  fs.writeFileSync('./database.json', JSON.stringify({ students: [], teachers: [], gallery: [] }, null, 2));
}

app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
EOF

cat > config.json << EOF
{
  "admin": {
    "username": "admin",
    "password": "$HASHED_PASSWORD"
  },
  "git": {
    "repo": "$GIT_REPO_URL",
    "branch": "main"
  }
}
EOF

cat > database.json << 'EOF'
{
  "students": [],
  "teachers": [],
  "gallery": []
}
EOF

cat > .gitignore << 'EOF'
node_modules/
.env
.DS_Store
*.log
EOF

cat > views/layouts/main.ejs << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title><%= title %> - Grade 12 Infinity TVL AFA</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;700&family=Poppins:wght@300;400;600&display=swap" rel="stylesheet">
  <link href="/css/tailwind.css" rel="stylesheet">
  <link href="/css/styles.css" rel="stylesheet">
  <link rel="icon" href="/images/favicon.ico" type="image/x-icon">
</head>
<body>
  <%- include('../partials/header') %>
  <main class="main-content">
    <%- body %>
  </main>
  <%- include('../partials/footer') %>
  <script src="/js/main.js"></script>
</body>
</html>
EOF

cat > views/index.ejs << 'EOF'
<%- include('layouts/main', { title: 'Home', body: `
  <section class="hero">
    <div class="container">
      <div class="hero-content">
        <h1 class="hero-title">Grade 12 Infinity TVL AFA</h1>
        <p class="hero-subtitle">Cultivating Knowledge, Harvesting Success</p>
        <div class="hero-buttons">
          <a href="/students" class="btn btn-primary">Our Students</a>
          <a href="/gallery" class="btn btn-secondary">View Gallery</a>
        </div>
      </div>
    </div>
  </section>
  
  <section class="features">
    <div class="container">
      <div class="features-grid">
        <div class="feature-card" data-aos="fade-up">
          <div class="feature-icon agriculture"></div>
          <h3>Agriculture</h3>
          <p>Learn sustainable farming practices and crop management techniques.</p>
        </div>
        <div class="feature-card" data-aos="fade-up" data-aos-delay="100">
          <div class="feature-icon fishery"></div>
          <h3>Fishery</h3>
          <p>Explore aquaculture systems and marine resource management.</p>
        </div>
        <div class="feature-card" data-aos="fade-up" data-aos-delay="200">
          <div class="feature-icon arts"></div>
          <h3>Arts</h3>
          <p>Develop creative approaches to agricultural and fishery challenges.</p>
        </div>
      </div>
    </div>
  </section>
  
  <section class="cta">
    <div class="container">
      <div class="cta-content">
        <h2>Join Our Community</h2>
        <p>Become part of our growing family of agricultural innovators.</p>
        <a href="/about" class="btn btn-accent">Learn More</a>
      </div>
    </div>
  </section>
` }) %>
EOF

cat > views/students.ejs << 'EOF'
<%- include('layouts/main', { title: 'Students', body: `
  <section class="page-header">
    <div class="container">
      <h1>Our Students</h1>
      <p>Meet the future agricultural leaders of tomorrow</p>
    </div>
  </section>
  
  <section class="students-section">
    <div class="container">
      <div class="students-grid">
        <% if (students && students.length > 0) { %>
          <% students.forEach(student => { %>
            <div class="student-card" data-aos="fade-up">
              <div class="student-avatar"></div>
              <h3><%= student.name %></h3>
              <p>TVL-AFA Student</p>
            </div>
          <% }) %>
        <% } else { %>
          <div class="empty-state">
            <p>No students have been added yet.</p>
          </div>
        <% } %>
      </div>
    </div>
  </section>
` }) %>
EOF

cat > views/teachers.ejs << 'EOF'
<%- include('layouts/main', { title: 'Teachers', body: `
  <section class="page-header">
    <div class="container">
      <h1>Our Teachers</h1>
      <p>Dedicated educators guiding the next generation</p>
    </div>
  </section>
  
  <section class="teachers-section">
    <div class="container">
      <div class="teachers-grid">
        <% if (teachers && teachers.length > 0) { %>
          <% teachers.forEach(teacher => { %>
            <div class="teacher-card" data-aos="fade-up">
              <div class="teacher-avatar"></div>
              <h3><%= teacher.name %></h3>
              <p>TVL-AFA Instructor</p>
            </div>
          <% }) %>
        <% } else { %>
          <div class="empty-state">
            <p>No teachers have been added yet.</p>
          </div>
        <% } %>
      </div>
    </div>
  </section>
` }) %>
EOF

cat > views/gallery.ejs << 'EOF'
<%- include('layouts/main', { title: 'Gallery', body: `
  <section class="page-header">
    <div class="container">
      <h1>Gallery</h1>
      <p>Moments captured from our journey</p>
    </div>
  </section>
  
  <section class="gallery-section">
    <div class="container">
      <div class="gallery-grid">
        <% if (gallery && gallery.length > 0) { %>
          <% gallery.forEach(image => { %>
            <div class="gallery-item" data-aos="zoom-in">
              <img src="<%= image.path %>" alt="Gallery Image" loading="lazy">
            </div>
          <% }) %>
        <% } else { %>
          <div class="empty-state">
            <p>No images have been added to the gallery yet.</p>
          </div>
        <% } %>
      </div>
    </div>
  </section>
` }) %>
EOF

cat > views/about.ejs << 'EOF'
<%- include('layouts/main', { title: 'About Us', body: `
  <section class="page-header">
    <div class="container">
      <h1>About Us</h1>
      <p>Our mission and vision</p>
    </div>
  </section>
  
  <section class="about-section">
    <div class="container">
      <div class="about-content">
        <div class="about-image" data-aos="fade-right"></div>
        <div class="about-text" data-aos="fade-left">
          <h2>Our Story</h2>
          <p>Grade 12 Infinity TVL AFA is dedicated to mastering Agri-Fishery Arts, equipping students with skills in sustainable agriculture, aquaculture, and food production to nurture the earth and feed the future.</p>
          <p>We believe in hands-on learning, environmental stewardship, and developing the next generation of agricultural innovators.</p>
          
          <h2>Our Values</h2>
          <ul class="values-list">
            <li>Sustainability</li>
            <li>Innovation</li>
            <li>Community</li>
            <li>Excellence</li>
          </ul>
        </div>
      </div>
    </div>
  </section>
` }) %>
EOF

cat > views/developer.ejs << EOF
<%- include('layouts/main', { title: 'Developer', body: \`
  <section class="page-header">
    <div class="container">
      <h1>Developer</h1>
      <p>The mind behind the website</p>
    </div>
  </section>
  
  <section class="developer-section">
    <div class="container">
      <div class="developer-profile">
        <div class="developer-avatar" data-aos="fade-right"></div>
        <div class="developer-info" data-aos="fade-left">
          <h2>${YOUR_NAME}</h2>
          <p class="developer-title">TVL-AFA Student & Web Developer</p>
          <p class="developer-bio">A passionate TVL-AFA student with a love for both agriculture and technology. This website was created to showcase our class's journey and achievements.</p>
          
          <div class="developer-skills">
            <h3>Skills</h3>
            <div class="skills-tags">
              <span>Web Development</span>
              <span>Agriculture</span>
              <span>Design</span>
              <span>Innovation</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>
\` }) %>
EOF

cat > views/admin-login.ejs << 'EOF'
<%- include('layouts/main', { title: 'Admin Login', body: `
  <section class="admin-login-section">
    <div class="container">
      <div class="login-card">
        <div class="login-header">
          <h2>Admin Login</h2>
          <p>Enter your credentials to access the admin panel</p>
        </div>
        
        <form id="login-form" class="login-form">
          <div class="form-group">
            <label for="username">Username</label>
            <input type="text" id="username" name="username" required>
          </div>
          
          <div class="form-group">
            <label for="password">Password</label>
            <input type="password" id="password" name="password" required>
          </div>
          
          <div class="form-group">
            <button type="submit" class="btn btn-primary btn-block">
              <span>Login</span>
              <span class="spinner hidden"></span>
            </button>
          </div>
          
          <div id="login-error" class="error-message hidden"></div>
        </form>
      </div>
    </div>
  </section>
` }) %>
EOF

cat > views/admin-panel.ejs << 'EOF'
<%- include('layouts/main', { title: 'Admin Panel', body: `
  <section class="page-header">
    <div class="container">
      <h1>Admin Panel</h1>
      <p>Manage website content</p>
    </div>
  </section>
  
  <section class="admin-section">
    <div class="container">
      <div class="admin-grid">
        <div class="admin-card">
          <h3>Add Student</h3>
          <form id="student-form" class="admin-form">
            <div class="form-group">
              <label for="student-name">Student Name</label>
              <input type="text" id="student-name" name="name" required>
            </div>
            <button type="submit" class="btn btn-primary">
              <span>Add Student</span>
              <span class="spinner hidden"></span>
            </button>
            <div id="student-error" class="error-message hidden"></div>
          </form>
        </div>
        
        <div class="admin-card">
          <h3>Add Teacher</h3>
          <form id="teacher-form" class="admin-form">
            <div class="form-group">
              <label for="teacher-name">Teacher Name</label>
              <input type="text" id="teacher-name" name="name" required>
            </div>
            <button type="submit" class="btn btn-primary">
              <span>Add Teacher</span>
              <span class="spinner hidden"></span>
            </button>
            <div id="teacher-error" class="error-message hidden"></div>
          </form>
        </div>
        
        <div class="admin-card">
          <h3>Upload to Gallery</h3>
          <form id="gallery-form" class="admin-form" enctype="multipart/form-data">
            <div class="form-group">
              <label for="gallery-image">Select Image</label>
              <input type="file" id="gallery-image" name="image" accept="image/*" required>
              <div class="file-preview"></div>
            </div>
            <button type="submit" class="btn btn-primary">
              <span>Upload Image</span>
              <span class="spinner hidden"></span>
            </button>
            <div id="gallery-error" class="error-message hidden"></div>
          </form>
        </div>
      </div>
    </div>
  </section>
` }) %>
EOF

cat > views/error.ejs << 'EOF'
<%- include('layouts/main', { title: 'Error', body: `
  <section class="error-section">
    <div class="container">
      <div class="error-content">
        <h1>Oops!</h1>
        <p><%= message || 'Something went wrong' %></p>
        <a href="/" class="btn btn-primary">Return Home</a>
      </div>
    </div>
  </section>
` }) %>
EOF

cat > views/partials/header.ejs << 'EOF'
<header class="site-header">
  <div class="container">
    <div class="header-content">
      <a href="/" class="logo">
        <span class="logo-text">Grade 12 Infinity</span>
        <span class="logo-highlight">TVL-AFA</span>
      </a>
      
      <button class="mobile-menu-toggle" aria-label="Toggle menu">
        <span></span>
        <span></span>
        <span></span>
      </button>
      
      <nav class="main-nav">
        <ul>
          <li><a href="/" class="<%= currentPath === '/' ? 'active' : '' %>">Home</a></li>
          <li><a href="/students" class="<%= currentPath === '/students' ? 'active' : '' %>">Students</a></li>
          <li><a href="/teachers" class="<%= currentPath === '/teachers' ? 'active' : '' %>">Teachers</a></li>
          <li><a href="/gallery" class="<%= currentPath === '/gallery' ? 'active' : '' %>">Gallery</a></li>
          <li><a href="/about" class="<%= currentPath === '/about' ? 'active' : '' %>">About</a></li>
          <li><a href="/developer" class="<%= currentPath === '/developer' ? 'active' : '' %>">Developer</a></li>
          <li><a href="/admin" class="<%= currentPath.startsWith('/admin') ? 'active' : '' %>">Admin</a></li>
        </ul>
      </nav>
    </div>
  </div>
</header>
EOF

cat > views/partials/footer.ejs << 'EOF'
<footer class="site-footer">
  <div class="container">
    <div class="footer-content">
      <div class="footer-logo">
        <span class="logo-text">Grade 12 Infinity</span>
        <span class="logo-highlight">TVL-AFA</span>
      </div>
      
      <div class="footer-links">
        <div class="footer-nav">
          <h4>Navigation</h4>
          <ul>
            <li><a href="/">Home</a></li>
            <li><a href="/students">Students</a></li>
            <li><a href="/teachers">Teachers</a></li>
            <li><a href="/gallery">Gallery</a></li>
            <li><a href="/about">About</a></li>
            <li><a href="/developer">Developer</a></li>
          </ul>
        </div>
        
        <div class="footer-contact">
          <h4>Contact</h4>
          <ul>
            <li>Email: info@infinity-tvl-afa.edu</li>
            <li>Phone: (123) 456-7890</li>
            <li>Address: 123 Education St., Knowledge City</li>
          </ul>
        </div>
      </div>
    </div>
    
    <div class="footer-bottom">
      <p>&copy; <%= new Date().getFullYear() %> Grade 12 Infinity TVL-AFA. All rights reserved.</p>
      <p>Cultivating the future, one seed at a time.</p>
    </div>
  </div>
</footer>
EOF

cat > public/css/tailwind.css << 'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;
EOF

cat > public/css/styles.css << 'EOF'
:root {
  --color-primary: #2e6b30;
  --color-primary-light: #4a9e4f;
  --color-primary-dark: #1a4a1c;
  --color-secondary: #f5c05a;
  --color-accent: #e67e22;
  --color-background: #f8f9f2;
  --color-card: #ffffff;
  --color-text: #333333;
  --color-text-light: #666666;
  --color-border: #e2e8f0;
  --font-heading: 'Playfair Display', serif;
  --font-body: 'Poppins', sans-serif;
  --shadow-sm: 0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.24);
  --shadow-md: 0 4px 6px rgba(0,0,0,0.1), 0 1px 3px rgba(0,0,0,0.08);
  --shadow-lg: 0 10px 15px -3px rgba(0,0,0,0.1), 0 4px 6px -2px rgba(0,0,0,0.05);
  --transition: all 0.3s cubic-bezier(0.25, 0.8, 0.25, 1);
}

* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: var(--font-body);
  color: var(--color-text);
  background-color: var(--color-background);
  background-image: url('/images/leaf-pattern.png');
  background-repeat: repeat;
  background-size: 200px;
  background-attachment: fixed;
  line-height: 1.6;
}

h1, h2, h3, h4, h5, h6 {
  font-family: var(--font-heading);
  font-weight: 700;
  line-height: 1.2;
  margin-bottom: 0.5em;
}

a {
  color: var(--color-primary);
  text-decoration: none;
  transition: var(--transition);
}

a:hover {
  color: var(--color-primary-light);
}

.container {
  width: 100%;
  max-width: 1200px;
  margin: 0 auto;
  padding: 0 1rem;
}

/* Header Styles */
.site-header {
  background-color: rgba(255, 255, 255, 0.95);
  box-shadow: var(--shadow-sm);
  position: sticky;
  top: 0;
  z-index: 100;
  backdrop-filter: blur(5px);
}

.header-content {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 1rem 0;
}

.logo {
  display: flex;
  flex-direction: column;
  line-height: 1.2;
}

.logo-text {
  font-family: var(--font-heading);
  font-size: 1.2rem;
  font-weight: 700;
}

.logo-highlight {
  color: var(--color-primary);
  font-weight: 700;
}

.main-nav ul {
  display: flex;
  list-style: none;
  gap: 1.5rem;
}

.main-nav a {
  font-weight: 500;
  padding: 0.5rem 0;
  position: relative;
}

.main-nav a::after {
  content: '';
  position: absolute;
  bottom: 0;
  left: 0;
  width: 0;
  height: 2px;
  background-color: var(--color-primary);
  transition: var(--transition);
}

.main-nav a:hover::after,
.main-nav a.active::after {
  width: 100%;
}

.mobile-menu-toggle {
  display: none;
  background: none;
  border: none;
  cursor: pointer;
  width: 30px;
  height: 24px;
  position: relative;
  z-index: 200;
}

.mobile-menu-toggle span {
  display: block;
  width: 100%;
  height: 2px;
  background-color: var(--color-text);
  margin: 5px 0;
  transition: var(--transition);
}

/* Hero Section */
.hero {
  padding: 6rem 0;
  background-image: linear-gradient(rgba(0, 0, 0, 0.5), rgba(0, 0, 0, 0.5)), url('/images/hero-bg.jpg');
  background-size: cover;
  background-position: center;
  color: white;
  text-align: center;
  position: relative;
}

.hero::before {
  content: '';
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: linear-gradient(135deg, rgba(46, 107, 48, 0.8), rgba(26, 74, 28, 0.8));
  z-index: 1;
}

.hero-content {
  position: relative;
  z-index: 2;
  max-width: 800px;
  margin: 0 auto;
}

.hero-title {
  font-size: 3.5rem;
  margin-bottom: 1rem;
  animation: fadeInUp 1s ease-out;
}

.hero-subtitle {
  font-size: 1.5rem;
  margin-bottom: 2rem;
  opacity: 0.9;
  animation: fadeInUp 1s ease-out 0.2s both;
}

.hero-buttons {
  display: flex;
  gap: 1rem;
  justify-content: center;
  animation: fadeInUp 1s ease-out 0.4s both;
}

/* Features Section */
.features {
  padding: 5rem 0;
}

.features-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
  gap: 2rem;
}

.feature-card {
  background-color: var(--color-card);
  border-radius: 8px;
  padding: 2rem;
  box-shadow: var(--shadow-md);
  text-align: center;
  transition: var(--transition);
}

.feature-card:hover {
  transform: translateY(-5px);
  box-shadow: var(--shadow-lg);
}

.feature-icon {
  width: 80px;
  height: 80px;
  margin: 0 auto 1.5rem;
  border-radius: 50%;
  background-color: var(--color-primary-light);
  display: flex;
  align-items: center;
  justify-content: center;
  position: relative;
  overflow: hidden;
}

.feature-icon::before {
  content: '';
  position: absolute;
  width: 100%;
  height: 100%;
  background-size: 60%;
  background-position: center;
  background-repeat: no-repeat;
  opacity: 0.8;
}

.feature-icon.agriculture::before {
  background-image: url('/images/icon-agriculture.svg');
}

.feature-icon.fishery::before {
  background-image: url('/images/icon-fishery.svg');
}

.feature-icon.arts::before {
  background-image: url('/images/icon-arts.svg');
}

/* CTA Section */
.cta {
  padding: 5rem 0;
  background-color: var(--color-primary);
  color: white;
  text-align: center;
}

.cta-content {
  max-width: 700px;
  margin: 0 auto;
}

.cta h2 {
  font-size: 2.5rem;
  margin-bottom: 1rem;
}

.cta p {
  font-size: 1.2rem;
  margin-bottom: 2rem;
  opacity: 0.9;
}

/* Page Header */
.page-header {
  padding: 4rem 0;
  background-color: var(--color-primary);
  color: white;
  text-align: center;
}

.page-header h1 {
  font-size: 3rem;
  margin-bottom: 0.5rem;
}

.page-header p {
  font-size: 1.2rem;
  opacity: 0.9;
  max-width: 700px;
  margin: 0 auto;
}

/* Students & Teachers Sections */
.students-section,
.teachers-section {
  padding: 4rem 0;
}

.students-grid,
.teachers-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
  gap: 2rem;
}

.student-card,
.teacher-card {
  background-color: var(--color-card);
  border-radius: 8px;
  padding: 2rem;
  box-shadow: var(--shadow-md);
  text-align: center;
  transition: var(--transition);
}

.student-card:hover,
.teacher-card:hover {
  transform: translateY(-5px);
  box-shadow: var(--shadow-lg);
}

.student-avatar,
.teacher-avatar {
  width: 120px;
  height: 120px;
  border-radius: 50%;
  margin: 0 auto 1.5rem;
  background-color: #e2e8f0;
  background-image: url('/images/avatar-placeholder.svg');
  background-size: cover;
  background-position: center;
}

/* Gallery Section */
.gallery-section {
  padding: 4rem 0;
}

.gallery-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 1.5rem;
}

.gallery-item {
  border-radius: 8px;
  overflow: hidden;
  box-shadow: var(--shadow-md);
  aspect-ratio: 4/3;
  transition: var(--transition);
}

.gallery-item:hover {
  transform: scale(1.02);
  box-shadow: var(--shadow-lg);
}

.gallery-item img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  transition: var(--transition);
}

.gallery-item:hover img {
  transform: scale(1.1);
}

/* About Section */
.about-section {
  padding: 4rem 0;
}

.about-content {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 3rem;
  align-items: center;
}

.about-image {
  height: 400px;
  border-radius: 8px;
  background-image: url('/images/about-image.jpg');
  background-size: cover;
  background-position: center;
  box-shadow: var(--shadow-md);
}

.about-text h2 {
  color: var(--color-primary);
  margin-top: 2rem;
  margin-bottom: 1rem;
}

.about-text h2:first-child {
  margin-top: 0;
}

.values-list {
  list-style: none;
  margin-top: 1rem;
}

.values-list li {
  padding: 0.5rem 0;
  border-bottom: 1px solid var(--color-border);
  position: relative;
  padding-left: 1.5rem;
}

.values-list li::before {
  content: '•';
  color: var(--color-primary);
  position: absolute;
  left: 0;
  font-size: 1.2rem;
}

/* Developer Section */
.developer-section {
  padding: 4rem 0;
}

.developer-profile {
  display: grid;
  grid-template-columns: 1fr 2fr;
  gap: 3rem;
  align-items: center;
  background-color: var(--color-card);
  border-radius: 8px;
  padding: 3rem;
  box-shadow: var(--shadow-md);
}

.developer-avatar {
  width: 100%;
  aspect-ratio: 1;
  border-radius: 8px;
  background-image: url('/images/developer-avatar.jpg');
  background-size: cover;
  background-position: center;
  box-shadow: var(--shadow-sm);
}

.developer-title {
  color: var(--color-primary);
  font-weight: 600;
  margin-bottom: 1rem;
}

.developer-bio {
  margin-bottom: 2rem;
}

.developer-skills h3 {
  margin-bottom: 0.5rem;
}

.skills-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
}

.skills-tags span {
  background-color: var(--color-primary-light);
  color: white;
  padding: 0.3rem 0.8rem;
  border-radius: 20px;
  font-size: 0.9rem;
}

/* Admin Login */
.admin-login-section {
  padding: 6rem 0;
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: calc(100vh - 200px);
}

.login-card {
  background-color: var(--color-card);
  border-radius: 8px;
  padding: 3rem;
  box-shadow: var(--shadow-lg);
  width: 100%;
  max-width: 500px;
}

.login-header {
  text-align: center;
  margin-bottom: 2rem;
}

.login-header h2 {
  color: var(--color-primary);
}

/* Admin Panel */
.admin-section {
  padding: 4rem 0;
}

.admin-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
  gap: 2rem;
}

.admin-card {
  background-color: var(--color-card);
  border-radius: 8px;
  padding: 2rem;
  box-shadow: var(--shadow-md);
}

.admin-card h3 {
  color: var(--color-primary);
  margin-bottom: 1.5rem;
  text-align: center;
}

/* Forms */
.form-group {
  margin-bottom: 1.5rem;
}

.form-group label {
  display: block;
  margin-bottom: 0.5rem;
  font-weight: 500;
}

.form-group input[type="text"],
.form-group input[type="password"],
.form-group input[type="email"],
.form-group textarea {
  width: 100%;
  padding: 0.8rem;
  border: 1px solid var(--color-border);
  border-radius: 4px;
  font-family: var(--font-body);
  transition: var(--transition);
}

.form-group input:focus,
.form-group textarea:focus {
  border-color: var(--color-primary);
  outline: none;
  box-shadow: 0 0 0 2px rgba(46, 107, 48, 0.2);
}

.form-group input[type="file"] {
  border: 1px dashed var(--color-border);
  padding: 1rem;
  border-radius: 4px;
  width: 100%;
  cursor: pointer;
}

.file-preview {
  margin-top: 1rem;
  text-align: center;
}

.file-preview img {
  max-width: 100%;
  max-height: 200px;
  border-radius: 4px;
}

/* Buttons */
.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0.8rem 1.5rem;
  border-radius: 4px;
  font-weight: 500;
  text-align: center;
  cursor: pointer;
  transition: var(--transition);
  border: none;
  font-family: var(--font-body);
}

.btn-primary {
  background-color: var(--color-primary);
  color: white;
}

.btn-primary:hover {
  background-color: var(--color-primary-dark);
  color: white;
}

.btn-secondary {
  background-color: white;
  color: var(--color-primary);
  border: 2px solid var(--color-primary);
}

.btn-secondary:hover {
  background-color: var(--color-primary);
  color: white;
}

.btn-accent {
  background-color: var(--color-accent);
  color: white;
}

.btn-accent:hover {
  background-color: #d35400;
  color: white;
}

.btn-block {
  display: block;
  width: 100%;
}

/* Footer */
.site-footer {
  background-color: var(--color-primary-dark);
  color: white;
  padding: 4rem 0 2rem;
  margin-top: 4rem;
}

.footer-content {
  display: grid;
  grid-template-columns: 1fr 2fr;
  gap: 3rem;
  margin-bottom: 3rem;
}

.footer-logo {
  display: flex;
  flex-direction: column;
  line-height: 1.2;
}

.footer-links {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 2rem;
}

.footer-nav h4,
.footer-contact h4 {
  color: var(--color-secondary);
  margin-bottom: 1rem;
  font-size: 1.2rem;
}

.footer-nav ul,
.footer-contact ul {
  list-style: none;
}

.footer-nav li,
.footer-contact li {
  margin-bottom: 0.5rem;
}

.footer-nav a {
  color: rgba(255, 255, 255, 0.8);
}

.footer-nav a:hover {
  color: white;
}

.footer-bottom {
  text-align: center;
  padding-top: 2rem;
  border-top: 1px solid rgba(255, 255, 255, 0.1);
  font-size: 0.9rem;
  opacity: 0.8;
}

/* Utilities */
.hidden {
  display: none;
}

.error-message {
  color: #e74c3c;
  font-size: 0.9rem;
  margin-top: 0.5rem;
}

.empty-state {
  text-align: center;
  padding: 3rem;
  background-color: var(--color-card);
  border-radius: 8px;
  box-shadow: var(--shadow-sm);
  grid-column: 1 / -1;
}

.spinner {
  display: inline-block;
  width: 1rem;
  height: 1rem;
  border: 2px solid rgba(255, 255, 255, 0.3);
  border-radius: 50%;
  border-top-color: white;
  animation: spin 1s linear infinite;
  margin-left: 0.5rem;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

@keyframes fadeInUp {
  from {
    opacity: 0;
    transform: translateY(20px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

/* Responsive */
@media (max-width: 768px) {
  .mobile-menu-toggle {
    display: block;
  }
  
  .main-nav {
    display: none;
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background-color: white;
    z-index: 100;
    padding: 5rem 2rem 2rem;
  }
  
  .main-nav.active {
    display: block;
  }
  
  .main-nav ul {
    flex-direction: column;
    gap: 1rem;
  }
  
  .main-nav a {
    display: block;
    padding: 0.8rem 0;
    font-size: 1.2rem;
  }
  
  .hero-title {
    font-size: 2.5rem;
  }
  
  .hero-subtitle {
    font-size: 1.2rem;
  }
  
  .about-content,
  .developer-profile {
    grid-template-columns: 1fr;
  }
  
  .about-image {
    height: 300px;
    order: -1;
  }
  
  .footer-content {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 480px) {
  .hero-buttons {
    flex-direction: column;
  }
  
  .page-header h1 {
    font-size: 2.5rem;
  }
  
  .admin-card,
  .login-card {
    padding: 1.5rem;
  }
}
EOF

cat > public/js/main.js << 'EOF'
document.addEventListener('DOMContentLoaded', () => {
  initMobileMenu();
  initFormHandlers();
  initFilePreview();
  initAnimations();
});

function initMobileMenu() {
  const menuToggle = document.querySelector('.mobile-menu-toggle');
  const mainNav = document.querySelector('.main-nav');
  
  if (!menuToggle || !mainNav) return;
  
  menuToggle.addEventListener('click', () => {
    mainNav.classList.toggle('active');
    document.body.classList.toggle('menu-open');
    
    const spans = menuToggle.querySelectorAll('span');
    spans[0].style.transform = mainNav.classList.contains('active') ? 'rotate(45deg) translate(5px, 5px)' : '';
    spans[1].style.opacity = mainNav.classList.contains('active') ? '0' : '1';
    spans[2].style.transform = mainNav.classList.contains('active') ? 'rotate(-45deg) translate(5px, -5px)' : '';
  });
  
  document.addEventListener('click', (e) => {
    if (mainNav.classList.contains('active') && !e.target.closest('.main-nav') && !e.target.closest('.mobile-menu-toggle')) {
      mainNav.classList.remove('active');
      document.body.classList.remove('menu-open');
      
      const spans = menuToggle.querySelectorAll('span');
      spans[0].style.transform = '';
      spans[1].style.opacity = '1';
      spans[2].style.transform = '';
    }
  });
}

function initFormHandlers() {
  setupFormSubmission('login-form', '/admin/login', 'POST');
  setupFormSubmission('student-form', '/admin/students', 'POST');
  setupFormSubmission('teacher-form', '/admin/teachers', 'POST');
  setupFormSubmission('gallery-form', '/admin/gallery', 'POST', true);
}

function setupFormSubmission(formId, endpoint, method, isMultipart = false) {
  const form = document.getElementById(formId);
  if (!form) return;
  
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    
    const submitBtn = form.querySelector('button[type="submit"]');
    const spinner = submitBtn?.querySelector('.spinner');
    const errorElement = document.getElementById(`${formId.split('-')[0]}-error`);
    
    if (spinner) spinner.classList.remove('hidden');
    if (errorElement) errorElement.classList.add('hidden');
    if (submitBtn) submitBtn.disabled = true;
    
    try {
      let response;
      
      if (isMultipart) {
        const formData = new FormData(form);
        response = await fetch(endpoint, {
          method,
          body: formData,
          headers: {
            'Authorization': `Bearer ${localStorage.getItem('token')}`
          }
        });
      } else {
        const formData = new FormData(form);
        const data = Object.fromEntries(formData.entries());
        
        response = await fetch(endpoint, {
          method,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${localStorage.getItem('token')}`
          },
          body: JSON.stringify(data)
        });
      }
      
      const result = await response.json();
      
      if (response.ok) {
        if (formId === 'login-form') {
          localStorage.setItem('token', result.token);
          window.location.href = '/admin/panel';
        } else {
          form.reset();
          
          if (formId === 'gallery-form') {
            const filePreview = form.querySelector('.file-preview');
            if (filePreview) filePreview.innerHTML = '';
          }
          
          showNotification('Success!', result.message || 'Operation completed successfully.');
          
          setTimeout(() => {
            window.location.reload();
          }, 1500);
        }
      } else {
        throw new Error(result.error || 'Something went wrong');
      }
    } catch (error) {
      if (errorElement) {
        errorElement.textContent = error.message;
        errorElement.classList.remove('hidden');
      }
    } finally {
      if (spinner) spinner.classList.add('hidden');
      if (submitBtn) submitBtn.disabled = false;
    }
  });
}

function initFilePreview() {
  const fileInput = document.getElementById('gallery-image');
  const filePreview = document.querySelector('.file-preview');
  
  if (!fileInput || !filePreview) return;
  
  fileInput.addEventListener('change', () => {
    filePreview.innerHTML = '';
    
    if (fileInput.files && fileInput.files[0]) {
      const reader = new FileReader();
      
      reader.onload = (e) => {
        const img = document.createElement('img');
        img.src = e.target.result;
        img.alt = 'Image Preview';
        filePreview.appendChild(img);
      };
      
      reader.readAsDataURL(fileInput.files[0]);
    }
  });
}

function initAnimations() {
  const animatedElements = document.querySelectorAll('[data-aos]');
  
  if (animatedElements.length === 0) return;
  
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('aos-animate');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.1 });
  
  animatedElements.forEach(element => {
    element.classList.add('aos-init');
    observer.observe(element);
  });
}

function showNotification(title, message) {
  const notification = document.createElement('div');
  notification.className = 'notification';
  notification.innerHTML = `
    <div class="notification-content">
      <h4>${title}</h4>
      <p>${message}</p>
    </div>
  `;
  
  document.body.appendChild(notification);
  
  setTimeout(() => {
    notification.classList.add('show');
  }, 10);
  
  setTimeout(() => {
    notification.classList.remove('show');
    setTimeout(() => {
      notification.remove();
    }, 300);
  }, 3000);
}

document.addEventListener('DOMContentLoaded', () => {
  const style = document.createElement('style');
  style.textContent = `
    .notification {
      position: fixed;
      top: 20px;
      right: 20px;
      background-color: var(--color-primary);
      color: white;
      padding: 1rem;
      border-radius: 4px;
      box-shadow: var(--shadow-md);
      z-index: 1000;
      transform: translateX(120%);
      transition: transform 0.3s ease;
    }
    
    .notification.show {
      transform: translateX(0);
    }
    
    .notification h4 {
      margin-bottom: 0.5rem;
    }
    
    .notification p {
      margin: 0;
      font-size: 0.9rem;
    }
    
    .aos-init {
      opacity: 0;
      transform: translateY(20px);
      transition: opacity 0.8s ease, transform 0.8s ease;
    }
    
    .aos-animate {
      opacity: 1;
      transform: translateY(0);
    }
    
    [data-aos="fade-right"] {
      transform: translateX(-20px);
    }
    
    [data-aos="fade-left"] {
      transform: translateX(20px);
    }
    
    [data-aos="zoom-in"] {
      transform: scale(0.9);
    }
    
    [data-aos="fade-right"].aos-animate,
    [data-aos="fade-left"].aos-animate {
      transform: translateX(0);
    }
    
    [data-aos="zoom-in"].aos-animate {
      transform: scale(1);
    }
    
    [data-aos-delay="100"] {
      transition-delay: 0.1s;
    }
    
    [data-aos-delay="200"] {
      transition-delay: 0.2s;
    }
  `;
  
  document.head.appendChild(style);
});
EOF

mkdir -p public/images

cat > public/images/favicon.ico << 'EOF'
EOF

cat > public/images/leaf-pattern.png << 'EOF'
EOF

cat > public/images/hero-bg.jpg << 'EOF'
EOF

cat > public/images/about-image.jpg << 'EOF'
EOF

cat > public/images/developer-avatar.jpg << 'EOF'
EOF

cat > public/images/avatar-placeholder.svg << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120" viewBox="0 0 120 120">
  <circle cx="60" cy="60" r="60" fill="#e2e8f0"/>
  <circle cx="60" cy="45" r="20" fill="#a0aec0"/>
  <path d="M60,75 C40,75 25,90 25,110 L95,110 C95,90 80,75 60,75 Z" fill="#a0aec0"/>
</svg>
EOF

cat > public/images/icon-agriculture.svg << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">
  <path d="M24,4 C12.95,4 4,12.95 4,24 C4,35.05 12.95,44 24,44 C35.05,44 44,35.05 44,24 C44,12.95 35.05,4 24,4 Z M24,8 C26.21,8 28,9.79 28,12 C28,14.21 26.21,16 24,16 C21.79,16 20,14.21 20,12 C20,9.79 21.79,8 24,8 Z M12,32 C9.79,32 8,30.21 8,28 C8,25.79 9.79,24 12,24 C14.21,24 16,25.79 16,28 C16,30.21 14.21,32 12,32 Z M16,20 C13.79,20 12,18.21 12,16 C12,13.79 13.79,12 16,12 C18.21,12 20,13.79 20,16 C20,18.21 18.21,20 16,20 Z M24,40 C21.79,40 20,38.21 20,36 C20,33.79 21.79,32 24,32 C26.21,32 28,33.79 28,36 C28,38.21 26.21,40 24,40 Z M32,20 C29.79,20 28,18.21 28,16 C28,13.79 29.79,12 32,12 C34.21,12 36,13.79 36,16 C36,18.21 34.21,20 32,20 Z M36,32 C33.79,32 32,30.21 32,28 C32,25.79 33.79,24 36,24 C38.21,24 40,25.79 40,28 C40,30.21 38.21,32 36,32 Z" fill="#ffffff"/>
</svg>
EOF

cat > public/images/icon-fishery.svg << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">
  <path d="M24,4 C12.95,4 4,12.95 4,24 C4,35.05 12.95,44 24,44 C35.05,44 44,35.05 44,24 C44,12.95 35.05,4 24,4 Z M24,8 C26.21,8 28,9.79 28,12 C28,14.21 26.21,16 24,16 C21.79,16 20,14.21 20,12 C20,9.79 21.79,8 24,8 Z M12,32 C9.79,32 8,30.21 8,28 C8,25.79 9.79,24 12,24 C14.21,24 16,25.79 16,28 C16,30.21 14.21,32 12,32 Z M16,20 C13.79,20 12,18.21 12,16 C12,13.79 13.79,12 16,12 C18.21,12 20,13.79 20,16 C20,18.21 18.21,20 16,20 Z M24,40 C21.79,40 20,38.21 20,36 C20,33.79 21.79,32 24,32 C26.21,32 28,33.79 28,36 C28,38.21 26.21,40 24,40 Z M32,20 C29.79,20 28,18.21 28,16 C28,13.79 29.79,12 32,12 C34.21,12 36,13.79 36,16 C36,18.21 34.21,20 32,20 Z M36,32 C33.79,32 32,30.21 32,28 C32,25.79 33.79,24 36,24 C38.21,24 40,25.79 40,28 C40,30.21 38.21,32 36,32 Z" fill="#ffffff"/>
</svg>
EOF

cat > public/images/icon-arts.svg << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">
  <path d="M24,4 C12.95,4 4,12.95 4,24 C4,35.05 12.95,44 24,44 C35.05,44 44,35.05 44,24 C44,12.95 35.05,4 24,4 Z M24,8 C26.21,8 28,9.79 28,12 C28,14.21 26.21,16 24,16 C21.79,16 20,14.21 20,12 C20,9.79 21.79,8 24,8 Z M12,32 C9.79,32 8,30.21 8,28 C8,25.79 9.79,24 12,24 C14.21,24 16,25.79 16,28 C16,30.21 14.21,32 12,32 Z M16,20 C13.79,20 12,18.21 12,16 C12,13.79 13.79,12 16,12 C18.21,12 20,13.79 20,16 C20,18.21 18.21,20 16,20 Z M24,40 C21.79,40 20,38.21 20,36 C20,33.79 21.79,32 24,32 C26.21,32 28,33.79 28,36 C28,38.21 26.21,40 24,40 Z M32,20 C29.79,20 28,18.21 28,16 C28,13.79 29.79,12 32,12 C34.21,12 36,13.79 36,16 C36,18.21 34.21,20 32,20 Z M36,32 C33.79,32 32,30.21 32,28 C32,25.79 33.79,24 36,24 C38.21,24 40,25.79 40,28 C40,30.21 38.21,32 36,32 Z" fill="#ffffff"/>
</svg>
EOF

git init
git add .
git commit -m "Initial commit"
git remote add origin "$GIT_REPO_URL"

echo "Setup complete! To start the server:"
echo "1. cd $PROJECT_DIR"
echo "2. Configure Git authentication (e.g., SSH or HTTPS credentials)"
echo "3. Run: git push -u origin main"
echo "4. Run: npm start"
echo "Access the website at http://localhost:3000"
echo "Admin login: username=admin, password=$ADMIN_PASSWORD"
