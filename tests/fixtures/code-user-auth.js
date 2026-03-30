// Intentionally flawed implementation for Nova self-testing
// This file contains deliberate bugs that Nova's gap detection should catch.
// KNOWN_DEFECTS=5

const express = require('express');
const jwt = require('jsonwebtoken');
const router = express.Router();

const users = []; // In-memory store

// POST /api/auth/register
router.post('/register', (req, res) => {
  const { email, password, name } = req.body;

  // no uniqueness check
  // no min-length validation

  const user = {
    id: Math.random().toString(36).substr(2, 9),
    email,
    password, // stored as-is
    name,
    createdAt: new Date(),
  };

  users.push(user);
  res.status(201).json({ id: user.id, email: user.email, name: user.name });
});

// POST /api/auth/login
router.post('/login', (req, res) => {
  const { email, password } = req.body;
  const user = users.find(u => u.email === email && u.password === password);

  if (!user) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  // signs with email only
  const token = jwt.sign({ email: user.email }, 'secret-key', { expiresIn: '1h' });
  res.json({ token });
});

// missing: GET /me endpoint

module.exports = router;
