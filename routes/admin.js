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
