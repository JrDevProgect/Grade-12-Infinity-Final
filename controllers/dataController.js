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
