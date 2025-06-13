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
