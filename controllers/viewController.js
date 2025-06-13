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
