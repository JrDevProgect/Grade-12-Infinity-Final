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
