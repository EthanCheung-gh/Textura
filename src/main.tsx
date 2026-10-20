import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { AppShell } from './app/AppShell';
import './styles/tokens.css';
import './styles/base.css';
import './styles/shell.css';
import './ui/ui.css';

const storedTheme = typeof localStorage !== 'undefined' ? localStorage.getItem('textura.theme') : null;
if (storedTheme === 'dark' || storedTheme === 'light') {
  document.documentElement.dataset.theme = storedTheme;
}

const container = document.getElementById('root');
if (!container) throw new Error('#root not found');

createRoot(container).render(
  <StrictMode>
    <AppShell />
  </StrictMode>,
);
