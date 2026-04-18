import React from 'react';

// INTENTIONAL Critical violations for Nova ux-audit test fixture:
// 1. <img> without alt attribute (Accessibility: Critical)
// 2. <div> with onClick but no keyboard support (Accessibility: Critical)
// 3. Color contrast issue: light gray text on white background

const BadButton: React.FC = () => {
  const handleClick = () => console.log('clicked');

  return (
    <div style={{ padding: '16px', background: '#ffffff' }}>
      {/* Critical: img without alt */}
      <img src="/logo.png" style={{ width: '100px' }} />

      {/* Critical: div with onClick, no role, no onKeyDown */}
      <div
        onClick={handleClick}
        style={{
          background: '#0070f3',
          color: '#ffffff',
          padding: '8px 16px',
          cursor: 'pointer',
          borderRadius: '4px',
          display: 'inline-block',
        }}
      >
        Click me
      </div>

      {/* Poor contrast: #aaaaaa on #ffffff */}
      <p style={{ color: '#aaaaaa', fontSize: '12px' }}>
        This text has poor color contrast ratio
      </p>
    </div>
  );
};

export default BadButton;
